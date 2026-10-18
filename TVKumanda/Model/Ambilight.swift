/// `ambilight/currentconfiguration` payload. Optional fields are left out of the JSON when nil.
nonisolated struct AmbilightConfig: Codable, Equatable, Sendable {
    var styleName: String
    var isExpert: Bool
    var menuSetting: String?
    var algorithm: String?
    var colorSettings: ColorSettings?

    nonisolated struct ColorSettings: Codable, Equatable, Sendable {
        var color: HSB
        var colorDelta: HSB
        var speed: Int
    }

    /// Philips uses 0...255 for all three channels.
    nonisolated struct HSB: Codable, Equatable, Sendable {
        var hue: Int
        var saturation: Int
        var brightness: Int
    }

    static func followVideo(_ setting: String) -> AmbilightConfig {
        AmbilightConfig(styleName: "FOLLOW_VIDEO", isExpert: false, menuSetting: setting)
    }

    static func followAudio(_ algorithm: String) -> AmbilightConfig {
        AmbilightConfig(styleName: "FOLLOW_AUDIO", isExpert: true, algorithm: algorithm)
    }

    static func fixedColor(_ color: HSB) -> AmbilightConfig {
        AmbilightConfig(styleName: "FOLLOW_COLOR", isExpert: true, algorithm: "MANUAL_HUE",
                        colorSettings: ColorSettings(color: color, colorDelta: HSB(hue: 0, saturation: 0, brightness: 0), speed: 255))
    }

    static let colorCycle = AmbilightConfig(styleName: "FOLLOW_COLOR", isExpert: true, algorithm: "AUTOMATIC_HUE")
}

/// Choices offered in the app. Identifiers come from the TV's `ambilight/supportedstyles`.
nonisolated enum AmbilightChoices {
    struct Option: Identifiable, Sendable {
        let id: String
        let title: String
    }

    static let video: [Option] = [
        Option(id: "STANDARD", title: "Standart"),
        Option(id: "NATURAL", title: "Doğal"),
        Option(id: "VIVID", title: "Canlı"),
        Option(id: "GAME", title: "Oyun"),
    ]

    static let audio: [Option] = [
        Option(id: "ENERGY_ADAPTIVE_BRIGHTNESS", title: "Enerji · parlaklık"),
        Option(id: "ENERGY_ADAPTIVE_COLORS", title: "Enerji · renk"),
        Option(id: "VU_METER", title: "VU metre"),
        Option(id: "SPECTRUM_ANALYZER", title: "Spektrum"),
        Option(id: "KNIGHT_RIDER_CLOCKWISE", title: "Kara Şimşek"),
        Option(id: "KNIGHT_RIDER_ALTERNATING", title: "Kara Şimşek · çift yön"),
        Option(id: "RANDOM_PIXEL_FLASH", title: "Rastgele flaş"),
        Option(id: "STROBO", title: "Stroboskop"),
        Option(id: "PARTY", title: "Parti"),
    ]
}

nonisolated struct TVVolume: Codable, Equatable, Sendable {
    var muted: Bool
    var current: Int
    var min: Int?
    var max: Int?
}
