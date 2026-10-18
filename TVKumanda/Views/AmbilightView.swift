import SwiftUI
import UIKit

struct AmbilightView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .video
    @State private var color = Color(red: 1, green: 0.55, blue: 0.2)

    enum Mode: String, CaseIterable, Identifiable {
        case video = "Video"
        case audio = "Ses"
        case color = "Renk"
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Ambilight", isOn: Binding(
                        get: { store.ambilightOn ?? false },
                        set: { store.setAmbilight(on: $0) }
                    ))
                    Picker("Mod", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch mode {
                case .video:
                    Section("Videoyu takip et") {
                        ForEach(AmbilightChoices.video) { option in
                            row(option.title, selected: current("FOLLOW_VIDEO", setting: option.id)) {
                                store.apply(.followVideo(option.id))
                            }
                        }
                    }
                case .audio:
                    Section("Sesi takip et") {
                        ForEach(AmbilightChoices.audio) { option in
                            row(option.title, selected: current("FOLLOW_AUDIO", setting: option.id)) {
                                store.apply(.followAudio(option.id))
                            }
                        }
                    }
                case .color:
                    Section("Sabit renk") {
                        ColorPicker("Renk seç", selection: $color, supportsOpacity: false)
                        row("Renk döngüsü", selected: current("FOLLOW_COLOR", setting: "AUTOMATIC_HUE")) {
                            store.apply(.colorCycle)
                        }
                    }
                }
            }
            .navigationTitle("Ambilight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .onAppear { mode = Self.mode(for: store.ambilight) }
            .onChange(of: color) { _, newColor in
                store.apply(.fixedColor(Self.hsb(newColor)), debounce: .milliseconds(180))
            }
        }
    }

    private func current(_ style: String, setting: String) -> Bool {
        guard let config = store.ambilight, store.ambilightOn == true, config.styleName == style else { return false }
        return config.menuSetting == setting || config.algorithm == setting
    }

    private func row(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }

    private static func mode(for config: AmbilightConfig?) -> Mode {
        switch config?.styleName {
        case "FOLLOW_AUDIO": .audio
        case "FOLLOW_COLOR", "LOUNGE": .color
        default: .video
        }
    }

    /// Philips wants hue, saturation and brightness on a 0...255 scale.
    private static func hsb(_ color: Color) -> AmbilightConfig.HSB {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        func scale(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return AmbilightConfig.HSB(hue: scale(hue), saturation: scale(saturation), brightness: scale(brightness))
    }
}
