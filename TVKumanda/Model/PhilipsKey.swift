/// Remote keys understood by Philips JointSpace v6 (`POST /6/input/key`).
/// Names verified on the living-room TV (Philips Google TV TA1, API 6.1).
nonisolated enum PhilipsKey: String, Sendable {
    case standby = "Standby"
    case cursorUp = "CursorUp"
    case cursorDown = "CursorDown"
    case cursorLeft = "CursorLeft"
    case cursorRight = "CursorRight"
    case confirm = "Confirm"
    case back = "Back"
    case home = "Home"
    case options = "Options"
    case volumeUp = "VolumeUp"
    case volumeDown = "VolumeDown"
    case mute = "Mute"
    case playPause = "PlayPause"
    case rewind = "Rewind"
    case fastForward = "FastForward"

    /// The same key on the Android TV remote channel, where it can be held down like a real button.
    var androidKeyCode: Int? {
        switch self {
        case .standby: nil
        case .cursorUp: 19
        case .cursorDown: 20
        case .cursorLeft: 21
        case .cursorRight: 22
        case .confirm: 23
        case .back: 4
        case .home: 3
        case .options: 82
        case .volumeUp: 24
        case .volumeDown: 25
        case .mute: 164
        case .playPause: 85
        case .rewind: 89
        case .fastForward: 90
        }
    }
}
