import Network
import Observation
import os

/// Finds Philips TVs by their JointSpace Bonjour service ("6_Oturma Odası TV'si").
@Observable
final class TVDiscovery {
    struct Found: Identifiable, Hashable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
    }

    private(set) var found: [Found] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_philipstv_s_rpc._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        found = results.compactMap { result in
            guard case let .service(name, _, _, _) = result.endpoint else { return nil }
            return Found(id: name, name: Self.displayName(name), endpoint: result.endpoint)
        }
        .sorted { $0.name < $1.name }
    }

    /// Philips prefixes the API version: "6_Oturma Odası TV'si".
    static func displayName(_ raw: String) -> String {
        guard let underscore = raw.firstIndex(of: "_"), raw[..<underscore].allSatisfy(\.isNumber) else { return raw }
        return String(raw[raw.index(after: underscore)...])
    }

    /// Resolves a Bonjour service to an IPv4 address by opening, then dropping, a TCP connection.
    nonisolated static func resolveIPv4(_ endpoint: NWEndpoint) async -> String? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: endpoint, using: parameters)
        let address = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint, case let .ipv4(ip) = host {
                        // Built from the raw bytes: the description carries an interface suffix ("%en0").
                        once.resume(ip.rawValue.map(String.init).joined(separator: "."))
                    } else {
                        once.resume(nil)
                    }
                case .failed, .cancelled:
                    once.resume(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { once.resume(nil) }
        }
        connection.cancel()
        return address
    }
}

private nonisolated final class ResumeOnce: Sendable {
    private let done = OSAllocatedUnfairLock(initialState: false)
    private let continuation: CheckedContinuation<String?, Never>

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: String?) {
        let first = done.withLock { finished in
            defer { finished = true }
            return !finished
        }
        if first { continuation.resume(returning: value) }
    }
}
