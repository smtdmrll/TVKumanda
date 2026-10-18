import SwiftUI

struct RemoteView: View {
    @Environment(TVStore.self) private var store
    @State private var showAmbilight = false
    @State private var showSettings = false
    @State private var showApps = false
    @State private var showKeyboard = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 16)
            DPad()
            Spacer(minLength: 24)
            HStack(spacing: 26) {
                RoundKey(key: .back, symbol: "chevron.backward", name: "Geri")
                RoundKey(key: .home, symbol: "house.fill", name: "Ana ekran")
                RoundKey(key: .options, symbol: "line.3.horizontal", name: "Menü")
            }
            Spacer(minLength: 18)
            HStack(spacing: 26) {
                RoundKey(key: .rewind, symbol: "backward.fill", name: "Geri sar", repeats: true)
                RoundKey(key: .playPause, symbol: "playpause.fill", name: "Oynat veya duraklat")
                RoundKey(key: .fastForward, symbol: "forward.fill", name: "İleri sar", repeats: true)
            }
            Spacer(minLength: 18)
            HStack(spacing: 16) {
                RoundKey(key: .mute, symbol: "speaker.slash.fill", name: "Sessiz")
                VolumePill()
                AmbilightKey { showAmbilight = true }
            }
            Spacer(minLength: 18)
            HStack(spacing: 12) {
                PillButton(title: "Uygulamalar", symbol: "square.grid.2x2.fill") { showApps = true }
                PillButton(title: "Klavye", symbol: "keyboard.fill") { showKeyboard = true }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.12), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .overlay(alignment: .bottom) { banner }
        .sheet(isPresented: $showAmbilight) {
            AmbilightView().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showApps) { AppsView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showKeyboard) { KeyboardView().presentationDetents([.medium]) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.credentials?.name ?? "TV")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.09)))
            }
            .foregroundStyle(.white)
            .accessibilityLabel("Ayarlar")
            Button { store.togglePower() } label: {
                Image(systemName: "power")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.red.opacity(store.link == .online ? 0.85 : 0.35)))
            }
            .foregroundStyle(.white)
            .sensoryFeedback(.impact(weight: .medium), trigger: store.link)
            .accessibilityLabel(store.link == .online ? "TV'yi kapat" : "TV'yi aç")
        }
    }

    private var statusColor: Color {
        switch store.link {
        case .online: .green
        case .standby: .orange
        case .offline: .red
        case .unknown: .gray
        }
    }

    private var statusText: String {
        switch store.link {
        case .online: "Bağlı"
        case .standby: "Bekleme modunda"
        case .offline: "Ulaşılamıyor"
        case .unknown: "Bağlanıyor…"
        }
    }

    @ViewBuilder private var banner: some View {
        if let message = store.message {
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color(white: 0.18)))
                .padding(.bottom, 6)
                .onTapGesture { store.message = nil }
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(5))
                    if store.message == message { store.message = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Large circular pad: arrows on the rim, OK in the middle.
struct DPad: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white.opacity(0.08)))
            VStack {
                arrow(.cursorUp, "chevron.up", "Yukarı")
                Spacer()
                arrow(.cursorDown, "chevron.down", "Aşağı")
            }
            HStack {
                arrow(.cursorLeft, "chevron.left", "Sol")
                Spacer()
                arrow(.cursorRight, "chevron.right", "Sağ")
            }
            KeyButton(.confirm, name: "Tamam") {
                Circle()
                    .fill(Color(white: 0.24))
                    .overlay(Circle().strokeBorder(.white.opacity(0.12)))
                    .overlay(Text("OK").font(.title3.weight(.semibold)).foregroundStyle(.white))
                    .frame(width: 108, height: 108)
                    .contentShape(Circle())
            }
        }
        .frame(width: 290, height: 290)
    }

    private func arrow(_ key: PhilipsKey, _ symbol: String, _ name: String) -> some View {
        KeyButton(key, repeats: true, name: name) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 88, height: 88)
                .contentShape(Rectangle())
        }
    }
}

struct VolumePill: View {
    @Environment(TVStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            KeyButton(.volumeDown, repeats: true, name: "Sesi azalt") {
                Image(systemName: "minus")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 58, height: 64)
                    .contentShape(Rectangle())
            }
            VStack(spacing: 2) {
                Image(systemName: store.volume?.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption)
                Text(store.volume.map { "\($0.current)" } ?? "–")
                    .font(.footnote.monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: 34)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ses düzeyi \(store.volume?.current ?? 0)")
            KeyButton(.volumeUp, repeats: true, name: "Sesi artır") {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 58, height: 64)
                    .contentShape(Rectangle())
            }
        }
        .foregroundStyle(.white)
        .background(Capsule().fill(.white.opacity(0.09)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
    }
}

/// Opens the Ambilight panel; the rainbow rim shows its state at a glance.
struct AmbilightKey: View {
    @Environment(TVStore.self) private var store
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(.white.opacity(0.09)))
                .overlay(
                    Circle().strokeBorder(
                        AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red], center: .center),
                        lineWidth: 3
                    )
                    .opacity(store.ambilightOn == true ? 1 : 0.35)
                )
        }
        .accessibilityLabel("Ambilight")
    }
}
