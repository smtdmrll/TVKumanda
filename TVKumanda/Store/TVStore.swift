import Foundation
import Observation

/// App state: the paired TV, its last known status, and an ordered queue of key presses.
@Observable
final class TVStore {
    enum Link: Equatable {
        case unknown, online, standby, offline
    }

    private(set) var credentials: TVCredentials?
    private(set) var link: Link = .unknown
    private(set) var volume: TVVolume?
    private(set) var ambilightOn: Bool?
    private(set) var ambilight: AmbilightConfig?
    private(set) var ticket: PairingTicket?
    private(set) var busy = false
    /// Google remote channel (apps and keyboard).
    private(set) var appChannelReady = false
    private(set) var textFieldActive = false
    /// What the focused TV text field currently holds.
    private(set) var tvText = ""
    private(set) var googleCodeShown = false
    var message: String?

    private var client: JointSpaceClient?
    private let keys: AsyncStream<PhilipsKey>.Continuation
    private var volumeRefresh: Task<Void, Never>?
    private var ambilightWrite: Task<Void, Never>?
    private let identity = ClientIdentity.load()
    private var androidRemote: AndroidTVRemote?
    private var googlePairing: AndroidTVPairing?
    private var heldKeys: Set<Int> = []

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: PhilipsKey.self, bufferingPolicy: .bufferingNewest(6))
        keys = continuation
        credentials = Keychain.load()
        client = credentials.map { JointSpaceClient(host: $0.host, credentials: $0) }
        makeAndroidRemote()
        // One consumer keeps presses in order; a fast double tap must not arrive reversed.
        Task { [weak self] in
            for await key in stream { await self?.deliver(key) }
        }
    }

    var isPaired: Bool { credentials != nil }

    // MARK: Remote

    func press(_ key: PhilipsKey) {
        keys.yield(key)
        if key == .volumeUp || key == .volumeDown || key == .mute { scheduleVolumeRefresh() }
    }

    /// Finger down. With the Android TV channel up the key stays pressed until `release`, so a browser
    /// cursor, scrolling or volume behave like a held remote button. Returns false when it fell back to
    /// a single Philips key press (the caller then repeats it itself).
    func pressDown(_ key: PhilipsKey) -> Bool {
        guard appChannelReady, let code = key.androidKeyCode, let androidRemote else {
            press(key)
            return false
        }
        heldKeys.insert(code)
        androidRemote.keyDown(code)
        return true
    }

    func release(_ key: PhilipsKey) {
        guard let code = key.androidKeyCode, heldKeys.remove(code) != nil else { return }
        androidRemote?.keyUp(code)
        if key == .volumeUp || key == .volumeDown || key == .mute { scheduleVolumeRefresh() }
    }

    func togglePower() {
        Task {
            guard let client else { return }
            do {
                if link == .online {
                    try await client.send(.standby)
                    link = .standby
                } else {
                    try await client.setPower(on: true)
                    link = .online
                    await refresh()
                }
            } catch {
                fail(error)
            }
        }
    }

    func refresh() async {
        guard let client else { return }
        do {
            let on = try await client.powerIsOn()
            link = on ? .online : .standby
            message = nil
            guard on else { return }
            async let volume = client.volume()
            async let lightOn = client.ambilightIsOn()
            async let light = client.ambilightConfig()
            self.volume = try? await volume
            ambilightOn = try? await lightOn
            ambilight = try? await light
        } catch {
            fail(error)
        }
    }

    private func deliver(_ key: PhilipsKey) async {
        guard let client else { return }
        do {
            try await client.send(key)
            if link != .standby { link = .online }
        } catch {
            fail(error)
        }
    }

    private func scheduleVolumeRefresh() {
        volumeRefresh?.cancel()
        volumeRefresh = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let client else { return }
            volume = try? await client.volume()
        }
    }

    // MARK: Ambilight

    func setAmbilight(on: Bool) {
        ambilightOn = on
        Task {
            guard let client else { return }
            do {
                try await client.setAmbilight(on: on)
                ambilight = try? await client.ambilightConfig()
            } catch {
                fail(error)
                ambilightOn = try? await client.ambilightIsOn()
            }
        }
    }

    /// Writes are coalesced so dragging the colour picker sends only the last colour.
    func apply(_ config: AmbilightConfig, debounce: Duration = .zero) {
        ambilight = config
        ambilightOn = true
        ambilightWrite?.cancel()
        ambilightWrite = Task {
            if debounce > .zero { try? await Task.sleep(for: debounce) }
            guard !Task.isCancelled, let client else { return }
            do { try await client.setAmbilight(config) } catch { fail(error) }
        }
    }

    // MARK: Pairing

    func beginPairing(host: String, name: String) async {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        defer { busy = false }
        message = nil
        do {
            ticket = try await JointSpaceClient(host: host, credentials: nil).requestPairing(name: name)
        } catch {
            fail(error)
        }
    }

    func finishPairing(pin: String) async {
        guard let ticket else { return }
        busy = true
        defer { busy = false }
        do {
            let paired = try await JointSpaceClient.completePairing(ticket, pin: pin)
            Keychain.save(paired)
            credentials = paired
            client = JointSpaceClient(host: paired.host, credentials: paired)
            makeAndroidRemote()
            self.ticket = nil
            message = nil
            await refresh()
        } catch {
            fail(error)
        }
    }

    func cancelPairing() {
        ticket = nil
        message = nil
    }

    func forget() {
        Keychain.delete()
        credentials = nil
        client = nil
        androidRemote?.stop()
        androidRemote = nil
        link = .unknown
        volume = nil
        ambilight = nil
        ambilightOn = nil
    }

    // MARK: Apps and keyboard (Android TV remote protocol)

    /// Connected only while the app is in front.
    func setActive(_ active: Bool) {
        if active { androidRemote?.start() } else { androidRemote?.stop() }
    }

    func launch(_ app: TVApp) {
        androidRemote?.openLink(app.link)
    }

    func enter() {
        androidRemote?.sendKey(66)
    }

    /// Mirrors a change of the phone's text box onto the TV field: deletions with DEL, new text inserted.
    func type(from old: String, to new: String) {
        guard let androidRemote else { return }
        let common = zip(old, new).prefix(while: { $0 == $1 }).count
        androidRemote.deleteBackward(old.count - common)
        let added = String(new.dropFirst(common))
        if !added.isEmpty { androidRemote.insert(added) }
    }

    func deleteOnTV() {
        androidRemote?.deleteBackward(1)
    }

    func clearTV() {
        androidRemote?.deleteBackward(max(tvText.count, 1))
    }

    func beginGooglePairing() async {
        guard let host = credentials?.host, let identity else { return }
        busy = true
        defer { busy = false }
        let pairing = AndroidTVPairing(host: host, identity: identity)
        do {
            try await pairing.start()
            googlePairing = pairing
            googleCodeShown = true
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func finishGooglePairing(code: String) async {
        guard let googlePairing else { return }
        busy = true
        defer { busy = false }
        do {
            try await googlePairing.finish(code: code)
            self.googlePairing = nil
            googleCodeShown = false
            androidRemote?.stop()
            androidRemote?.start()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func cancelGooglePairing() {
        googlePairing = nil
        googleCodeShown = false
    }

    private func makeAndroidRemote() {
        androidRemote?.stop()
        guard let host = credentials?.host, let identity else { return }
        androidRemote = AndroidTVRemote(host: host, identity: identity) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    private func handle(_ event: AndroidTVRemote.Event) {
        switch event {
        case .ready: appChannelReady = true
        case .closed:
            appChannelReady = false
            heldKeys.removeAll()
            textFieldActive = false
            tvText = ""
        case let .textField(active, value):
            textFieldActive = active
            tvText = value
        }
    }

    private func fail(_ error: Error) {
        if (error as? JointSpaceError) == .unreachable { link = .offline }
        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
