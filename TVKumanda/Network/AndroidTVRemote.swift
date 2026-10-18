import CryptoKit
import Foundation
import Network
import os

/// The client certificate the TV trusts after pairing (bundled; paired once from the Mac).
nonisolated enum ClientIdentity {
    static func load() -> SecIdentity? {
        guard let url = Bundle.main.url(forResource: "client", withExtension: "p12"),
              let data = try? Data(contentsOf: url) else { return nil }
        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: "tvkumanda-remote"] as CFDictionary
        guard SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
              let first = (items as? [[String: Any]])?.first,
              let identity = first[kSecImportItemIdentity as String] else { return nil }
        return (identity as! SecIdentity)
    }

    static func tls(_ identity: SecIdentity, queue: DispatchQueue,
                    onServerCertificate: (@Sendable (SecCertificate) -> Void)? = nil) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        if let local = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, local)
        }
        // The TV's certificate is self-signed; pairing is what makes the link trusted.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            if let leaf = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate])?.first {
                onServerCertificate?(leaf)
            }
            complete(true)
        }, queue)
        return NWParameters(tls: tls)
    }
}

/// Android TV Remote v2, port 6466: keys, app links and IME text over one long-lived TLS connection.
nonisolated final class AndroidTVRemote: @unchecked Sendable {
    enum Event: Sendable {
        case ready
        case closed
        case textField(active: Bool, value: String)
    }

    /// ping, key, ime, power, volume, app link
    private static let features = 1 | 2 | 4 | 32 | 64 | 512

    private let host: String
    private let identity: SecIdentity
    private let queue = DispatchQueue(label: "tvkumanda.atvremote")
    private let onEvent: @Sendable (Event) -> Void

    // Confined to `queue`.
    private var connection: NWConnection?
    private var buffer = Data()
    private var ready = false
    private var pending: [Data] = []

    // Text editing. The TV takes an edit only when it names the focused field (`fieldID`, from the app
    // info sent on focus) and the latest content version (bumped by the TV after every change). Edits
    // are inserted at the cursor, so they go one at a time, each waiting for the new version.
    private enum Edit { case insert(String), delete(Int) }
    private enum Waiting { case insert, delete }
    private var fieldID = 0
    private var contentVersion = 0
    private var fieldActive = false
    private var edits: [Edit] = []
    private var waiting: Waiting?
    private var waitTimer: DispatchWorkItem?

    init(host: String, identity: SecIdentity, onEvent: @escaping @Sendable (Event) -> Void) {
        self.host = host
        self.identity = identity
        self.onEvent = onEvent
    }

    func start() { queue.async { self.open() } }

    func stop() { queue.async { self.close() } }

    func sendKey(_ code: Int) {
        send(Proto.field(10, Proto.field(1, code) + Proto.field(2, 3)))
    }

    /// Key down; the TV repeats it on its own until `keyUp`, exactly like a held remote button.
    func keyDown(_ code: Int) {
        send(Proto.field(10, Proto.field(1, code) + Proto.field(2, 1)))
    }

    func keyUp(_ code: Int) {
        send(Proto.field(10, Proto.field(1, code) + Proto.field(2, 2)))
    }

    func openLink(_ link: String) {
        send(Proto.field(90, Proto.field(1, link)))
    }

    /// Inserts text at the TV's cursor; ignored unless a text field is focused there.
    func insert(_ text: String) {
        queue.async { self.queueEdit(.insert(text)) }
    }

    /// Deletes before the TV's cursor with the remote's DEL key.
    func deleteBackward(_ count: Int) {
        guard count > 0 else { return }
        queue.async { self.queueEdit(.delete(count)) }
    }

    private func queueEdit(_ edit: Edit) {
        guard fieldActive else { return }
        edits.append(edit)
        pumpEdits()
    }

    private func pumpEdits() {
        guard waiting == nil, ready, fieldActive, !edits.isEmpty else { return }
        switch edits.removeFirst() {
        case .insert(var text):
            while case .insert(let more)? = edits.first {
                text += more
                edits.removeFirst()
            }
            let cursor = text.unicodeScalars.count - 1
            let object = Proto.field(1, cursor) + Proto.field(2, cursor) + Proto.field(3, text)
            let edit = Proto.field(1, 1) + Proto.field(2, object)
            write(Proto.field(21, Proto.field(1, fieldID) + Proto.field(2, contentVersion) + Proto.field(3, edit)))
            hold(.insert, seconds: 0.8)
        case .delete(var count):
            while case .delete(let more)? = edits.first {
                count += more
                edits.removeFirst()
            }
            for _ in 0..<count { write(Proto.field(10, Proto.field(1, 67) + Proto.field(2, 3))) }
            hold(.delete, seconds: 0.3)
        }
    }

    /// Holds further edits until the TV reports the new content version, or the timeout passes.
    private func hold(_ kind: Waiting, seconds: Double) {
        waiting = kind
        waitTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.waiting = nil
            self.pumpEdits()
        }
        waitTimer = timer
        queue.asyncAfter(deadline: .now() + seconds, execute: timer)
    }

    private func fieldStatus(_ status: Data) {
        let fields = Proto.parse(status)
        if let version = fields.varint(1) { contentVersion = Int(version) }
        let value = fields.bytes(2).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        fieldActive = true
        onEvent(.textField(active: true, value: value))
        switch waiting {
        case .insert:
            waitTimer?.cancel()
            waiting = nil
            pumpEdits()
        case .delete:
            hold(.delete, seconds: 0.15) // one update per deleted character may still follow
        case nil:
            pumpEdits()
        }
    }

    private func send(_ message: Data) {
        queue.async { self.enqueue(message) }
    }

    private func enqueue(_ message: Data) {
        if ready, let connection {
            connection.send(content: Proto.frame(message), completion: .contentProcessed { _ in })
        } else {
            pending.append(message)
            open()
        }
    }

    private func open() {
        guard connection == nil else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 6466,
                                      using: ClientIdentity.tls(identity, queue: queue))
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        self.connection = connection
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func close() {
        guard let connection else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        self.connection = nil
        buffer.removeAll()
        ready = false
        fieldActive = false
        edits.removeAll()
        waiting = nil
        waitTimer?.cancel()
        if pending.count > 20 { pending.removeAll() }
        onEvent(.closed)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, connection === self.connection else { return }
            if let data {
                self.buffer.append(data)
                for frame in Proto.takeFrames(from: &self.buffer) { self.handle(frame) }
            }
            if isComplete || error != nil { return self.close() }
            self.receive(on: connection)
        }
    }

    private func write(_ message: Data) {
        connection?.send(content: Proto.frame(message), completion: .contentProcessed { _ in })
    }

    private func handle(_ frame: Data) {
        for (number, value) in Proto.parse(frame) {
            guard case let .bytes(body) = value else { continue }
            let fields = Proto.parse(body)
            switch number {
            case 1: // remote_configure: answer with the features both sides support
                let theirs = Int(fields.varint(1) ?? 0)
                let info = Proto.field(3, 1) + Proto.field(4, "1") + Proto.field(5, "atvremote") + Proto.field(6, "1.0.0")
                write(Proto.field(1, Proto.field(1, Self.features & theirs) + Proto.field(2, info)))
            case 2: // remote_set_active: session is usable from here on
                write(Proto.field(2, Proto.field(1, Self.features)))
                ready = true
                let queued = pending
                pending.removeAll()
                queued.forEach(write)
                onEvent(.ready)
            case 8: // ping
                write(Proto.field(9, Proto.field(1, Int(fields.varint(1) ?? 0))))
            case 20: // focus report: app info, plus the text field's status when one is focused
                if let app = fields.bytes(1), let id = Proto.parse(app).varint(1) { fieldID = Int(id) }
                if let status = fields.bytes(2) {
                    fieldStatus(status)
                } else {
                    fieldActive = false
                    edits.removeAll()
                    onEvent(.textField(active: false, value: ""))
                }
            case 22: // text field shown or changed
                if let status = fields.bytes(2) { fieldStatus(status) }
            default:
                break
            }
        }
    }
}

/// Android TV Remote v2 pairing ("polo"), port 6467. The TV shows a 6-character hex code.
nonisolated final class AndroidTVPairing: @unchecked Sendable {
    enum Failure: LocalizedError {
        case connection, rejected, wrongCode

        var errorDescription: String? {
            switch self {
            case .connection: "TV'nin eşleme servisine bağlanılamadı."
            case .rejected: "TV eşlemeyi kabul etmedi."
            case .wrongCode: "Kod yanlış. TV'deki 6 karakteri kontrol et."
            }
        }
    }

    private let host: String
    private let identity: SecIdentity
    private let queue = DispatchQueue(label: "tvkumanda.pairing")
    private let serverCertificate = OSAllocatedUnfairLock<SecCertificate?>(uncheckedState: nil)
    private var connection: NWConnection?
    private var buffer = Data()

    init(host: String, identity: SecIdentity) {
        self.host = host
        self.identity = identity
    }

    /// Runs until the TV displays the code.
    func start() async throws {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 6467,
                                      using: ClientIdentity.tls(identity, queue: queue) { [serverCertificate] certificate in
                                          serverCertificate.withLockUnchecked { $0 = certificate }
                                      })
        self.connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = OSAllocatedUnfairLock(initialState: false)
            connection.stateUpdateHandler = { state in
                let result: Result<Void, Error>?
                switch state {
                case .ready: result = .success(())
                case .failed, .cancelled: result = .failure(Failure.connection)
                default: result = nil
                }
                guard let result, once.withLock({ done in defer { done = true }; return !done }) else { return }
                continuation.resume(with: result)
            }
            connection.start(queue: queue)
        }
        let encoding = Proto.field(1, 3) + Proto.field(2, 6) // hexadecimal, 6 symbols
        try await exchange(field: 10, Proto.field(1, "atvremote") + Proto.field(2, "TV Kumanda"), expect: 11)
        try await exchange(field: 20, Proto.field(1, encoding) + Proto.field(3, 1), expect: 20)
        try await exchange(field: 30, Proto.field(1, encoding) + Proto.field(2, 1), expect: 31)
    }

    /// Secret = SHA-256(client modulus, client exponent, server modulus, server exponent, code[2...]);
    /// its first byte must equal code[0..<2].
    func finish(code: String) async throws {
        defer { connection?.cancel() }
        let code = code.uppercased()
        guard code.count == 6, let codeBytes = Data(hex: String(code.dropFirst(2))), let check = UInt8(code.prefix(2), radix: 16),
              let clientCertificate = Self.certificate(of: identity),
              let client = Self.rsa(clientCertificate),
              let server = serverCertificate.withLockUnchecked({ $0 }).flatMap(Self.rsa) else { throw Failure.wrongCode }
        var hash = SHA256()
        hash.update(data: client.modulus)
        hash.update(data: client.exponent)
        hash.update(data: server.modulus)
        hash.update(data: server.exponent)
        hash.update(data: codeBytes)
        let secret = Data(hash.finalize())
        guard secret.first == check else { throw Failure.wrongCode }
        try await exchange(field: 40, Proto.field(1, secret), expect: 41)
    }

    private func exchange(field: Int, _ body: Data, expect: Int) async throws {
        guard let connection else { throw Failure.connection }
        let message = Proto.field(1, 2) + Proto.field(2, 200) + Proto.field(field, body)
        connection.send(content: Proto.frame(message), completion: .contentProcessed { _ in })
        let reply = Proto.parse(try await nextFrame())
        guard reply.varint(2) == 200, reply.has(expect) else { throw Failure.rejected }
    }

    private func nextFrame() async throws -> Data {
        while true {
            if let frame = Proto.takeFrames(from: &buffer).first { return frame }
            guard let connection else { throw Failure.connection }
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: Failure.connection) }
                    _ = isComplete
                    _ = error
                }
            }
            buffer.append(chunk)
        }
    }

    private static func certificate(of identity: SecIdentity) -> SecCertificate? {
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        return certificate
    }

    /// Modulus and exponent as unsigned big-endian bytes, read from the PKCS#1 RSAPublicKey.
    private static func rsa(_ certificate: SecCertificate) -> (modulus: Data, exponent: Data)? {
        guard let key = SecCertificateCopyKey(certificate),
              let der = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        var reader = DERReader(der)
        guard reader.enter(0x30), let modulus = reader.read(0x02), let exponent = reader.read(0x02) else { return nil }
        return (Data(modulus.drop(while: { $0 == 0 })), Data(exponent.drop(while: { $0 == 0 })))
    }
}

private nonisolated struct DERReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func enter(_ tag: UInt8) -> Bool { header(tag) != nil }

    mutating func read(_ tag: UInt8) -> [UInt8]? {
        guard let length = header(tag), index + length <= bytes.count else { return nil }
        defer { index += length }
        return Array(bytes[index..<index + length])
    }

    private mutating func header(_ tag: UInt8) -> Int? {
        guard index + 1 < bytes.count, bytes[index] == tag else { return nil }
        index += 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            length = 0
            for _ in 0..<count {
                guard index < bytes.count else { return nil }
                length = length << 8 | Int(bytes[index])
                index += 1
            }
        }
        return length
    }
}

private nonisolated extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
