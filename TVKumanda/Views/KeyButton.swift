import SwiftUI

/// Sends its key the moment a finger lands; repeating keys keep firing while held.
struct KeyButton<Content: View>: View {
    private let key: PhilipsKey
    private let repeats: Bool
    private let name: String
    private let content: () -> Content

    @Environment(TVStore.self) private var store
    @State private var pressed = false
    @State private var taps = 0
    @State private var repeater: Task<Void, Never>?

    init(_ key: PhilipsKey, repeats: Bool = false, name: String, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        self.repeats = repeats
        self.name = name
        self.content = content
    }

    var body: some View {
        content()
            .scaleEffect(pressed ? 0.9 : 1)
            .brightness(pressed ? 0.15 : 0)
            .animation(.spring(duration: 0.18), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { begin() } }
                    .onEnded { _ in end() }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { store.press(key) }
    }

    private func begin() {
        pressed = true
        taps += 1
        // Held on the TV itself when possible; otherwise repeat single presses from here.
        guard !store.pressDown(key), repeats else { return }
        repeater = Task {
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                store.press(key)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func end() {
        pressed = false
        store.release(key)
        repeater?.cancel()
        repeater = nil
    }
}

/// Round glass key used for most of the remote.
struct RoundKey: View {
    let key: PhilipsKey
    let symbol: String
    let name: String
    var repeats = false
    var size: CGFloat = 64

    var body: some View {
        KeyButton(key, repeats: repeats, name: name) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(0.09)))
                .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                .contentShape(Circle())
        }
    }
}
