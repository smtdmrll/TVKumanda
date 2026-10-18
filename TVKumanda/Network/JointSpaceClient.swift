import CryptoKit
import Foundation
import os

nonisolated enum JointSpaceError: LocalizedError, Equatable {
    case unreachable
    case unauthorized
    case certificateChanged
    case badResponse(Int)
    case pairing(String)

    var errorDescription: String? {
        switch self {
        case .unreachable: "TV'ye ulaşılamıyor. TV açık ve aynı Wi-Fi ağında mı?"
        case .unauthorized: "TV bu telefonu tanımadı. Ayarlardan yeniden eşleştir."
        case .certificateChanged: "TV'nin güvenlik sertifikası değişti. Ayarlardan yeniden eşleştir."
        case .badResponse(let code): "TV beklenmeyen bir yanıt verdi (\(code))."
        case .pairing(let reason): "Eşleşme olmadı: \(reason)"
        }
    }
}

/// What a paired TV needs: digest credentials plus the TLS certificate seen at pairing time.
nonisolated struct TVCredentials: Codable, Equatable, Sendable {
    var host: String
    var name: String
    var deviceID: String
    var authKey: String
    var certificateSHA256: Data?
}

nonisolated struct PairingDevice: Codable, Sendable {
    let deviceName: String
    let deviceOS: String
    let appName: String
    let appID: String
    let type: String
    let id: String

    enum CodingKeys: String, CodingKey {
        case deviceName = "device_name", deviceOS = "device_os", appName = "app_name", appID = "app_id", type, id
    }
}

/// Result of `pair/request`: the TV is now showing a 4-digit PIN.
nonisolated struct PairingTicket: Sendable {
    let host: String
    let name: String
    let device: PairingDevice
    let authKey: String
    let timestamp: Int
    let certificateSHA256: Data?
}

/// Answers the TV's challenges: its self-signed certificate (pinned after pairing) and HTTP digest auth.
nonisolated final class JointSpaceAuth: NSObject, URLSessionTaskDelegate, Sendable {
    private let user: String?
    private let password: String?
    private let pinned: Data?
    private let seen = OSAllocatedUnfairLock<Data?>(initialState: nil)

    init(user: String?, password: String?, pinned: Data?) {
        self.user = user
        self.password = password
        self.pinned = pinned
    }

    var seenCertificate: Data? { seen.withLock { $0 } }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            guard let trust = space.serverTrust,
                  let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
                return (.cancelAuthenticationChallenge, nil)
            }
            let hash = Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data))
            seen.withLock { $0 = hash }
            if let pinned, pinned != hash { return (.cancelAuthenticationChallenge, nil) }
            return (.useCredential, URLCredential(trust: trust))
        case NSURLAuthenticationMethodHTTPDigest:
            // A second challenge means the credentials were refused: let the 401 through.
            guard let user, let password, challenge.previousFailureCount == 0 else { return (.performDefaultHandling, nil) }
            return (.useCredential, URLCredential(user: user, password: password, persistence: .forSession))
        default:
            return (.performDefaultHandling, nil)
        }
    }
}

/// Philips JointSpace v6: HTTPS on port 1926, digest auth after a PIN pairing.
nonisolated final class JointSpaceClient: Sendable {
    let host: String
    private let pinned: Data?
    private let auth: JointSpaceAuth
    private let session: URLSession

    /// Shared HMAC key of Philips' own remote apps, published in open-source JointSpace clients.
    private static let sharedKey = Data(base64Encoded:
        "ZmVay1EQVFOaZhwQ4Kv81ypLAZNczV9sG4KkseXWn1NEk6cXmPKO/MCa9sryslvLCFMnNe4Z4CPXzToowvhHvA==")!

    init(host: String, credentials: TVCredentials?) {
        self.host = host
        pinned = credentials?.certificateSHA256
        auth = JointSpaceAuth(user: credentials?.deviceID, password: credentials?.authKey, pinned: credentials?.certificateSHA256)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 8
        config.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: config, delegate: auth, delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    // MARK: Pairing

    func requestPairing(name: String) async throws -> PairingTicket {
        let device = PairingDevice(deviceName: "iPhone", deviceOS: "iOS", appName: "TV Kumanda",
                                   appID: "com.sametdemirel.tvkumanda", type: "native", id: Self.randomID())
        let body = PairRequest(access: .init(scope: ["read", "write", "control"]), device: device)
        let reply = try JSONDecoder().decode(PairReply.self, from: try await perform("pair/request", body: body))
        guard reply.errorID == "SUCCESS", let key = reply.authKey, let timestamp = reply.timestamp else {
            throw JointSpaceError.pairing(reply.errorText ?? reply.errorID ?? "bilinmeyen yanıt")
        }
        return PairingTicket(host: host, name: name, device: device, authKey: key, timestamp: timestamp,
                             certificateSHA256: auth.seenCertificate)
    }

    /// Second step: digest auth with the temporary key, plus an HMAC-SHA1 of timestamp + PIN.
    static func completePairing(_ ticket: PairingTicket, pin: String) async throws -> TVCredentials {
        let credentials = TVCredentials(host: ticket.host, name: ticket.name, deviceID: ticket.device.id,
                                        authKey: ticket.authKey, certificateSHA256: ticket.certificateSHA256)
        let client = JointSpaceClient(host: ticket.host, credentials: credentials)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data("\(ticket.timestamp)\(pin)".utf8),
                                                        using: SymmetricKey(data: sharedKey))
        let body = PairGrant(auth: .init(appID: "1", timestamp: ticket.timestamp,
                                         signature: Data(mac).base64EncodedString(), pin: pin),
                             device: ticket.device)
        let reply = try JSONDecoder().decode(PairReply.self, from: try await client.perform("pair/grant", body: body))
        guard reply.errorID == "SUCCESS" else {
            throw JointSpaceError.pairing(reply.errorText ?? reply.errorID ?? "bilinmeyen yanıt")
        }
        return credentials
    }

    // MARK: Remote

    func send(_ key: PhilipsKey) async throws {
        _ = try await perform("input/key", body: ["key": key.rawValue])
    }

    func powerIsOn() async throws -> Bool {
        let reply = try JSONDecoder().decode([String: String].self, from: try await perform("powerstate"))
        return reply["powerstate"] == "On"
    }

    func setPower(on: Bool) async throws {
        _ = try await perform("powerstate", body: ["powerstate": on ? "On" : "Standby"])
    }

    func volume() async throws -> TVVolume {
        try JSONDecoder().decode(TVVolume.self, from: try await perform("audio/volume"))
    }

    // MARK: Ambilight

    func ambilightIsOn() async throws -> Bool {
        let reply = try JSONDecoder().decode([String: String].self, from: try await perform("ambilight/power"))
        return reply["power"] == "On"
    }

    func setAmbilight(on: Bool) async throws {
        _ = try await perform("ambilight/power", body: ["power": on ? "On" : "Off"])
    }

    func ambilightConfig() async throws -> AmbilightConfig {
        try JSONDecoder().decode(AmbilightConfig.self, from: try await perform("ambilight/currentconfiguration"))
    }

    func setAmbilight(_ config: AmbilightConfig) async throws {
        _ = try await perform("ambilight/currentconfiguration", body: config)
    }

    // MARK: Transport

    private func perform(_ path: String) async throws -> Data {
        try await perform(path, payload: nil)
    }

    private func perform(_ path: String, body: some Encodable) async throws -> Data {
        try await perform(path, payload: try JSONEncoder().encode(body))
    }

    private func perform(_ path: String, payload: Data?) async throws -> Data {
        guard let url = URL(string: "https://\(host):1926/6/\(path)") else { throw JointSpaceError.unreachable }
        var request = URLRequest(url: url)
        if let payload {
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let pinned, let seen = auth.seenCertificate, seen != pinned { throw JointSpaceError.certificateChanged }
            throw JointSpaceError.unreachable
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 401: throw JointSpaceError.unauthorized
        case let code: throw JointSpaceError.badResponse(code)
        }
    }

    private static func randomID() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<16).map { _ in chars.randomElement()! })
    }
}

private nonisolated struct PairRequest: Encodable {
    struct Access: Encodable { let scope: [String] }
    let access: Access
    let device: PairingDevice
}

private nonisolated struct PairGrant: Encodable {
    struct Auth: Encodable {
        let appID: String
        let timestamp: Int
        let signature: String
        let pin: String
        enum CodingKeys: String, CodingKey {
            case appID = "auth_appId", timestamp = "auth_timestamp", signature = "auth_signature", pin
        }
    }
    let auth: Auth
    let device: PairingDevice
}

private nonisolated struct PairReply: Decodable {
    let errorID: String?
    let errorText: String?
    let authKey: String?
    let timestamp: Int?

    enum CodingKeys: String, CodingKey {
        case errorID = "error_id", errorText = "error_text", authKey = "auth_key", timestamp
    }
}
