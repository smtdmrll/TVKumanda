import SwiftUI

@main
struct TVKumandaApp: App {
    @State private var store = TVStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if store.isPaired {
                RemoteView()
            } else {
                PairingView()
            }
        }
        // Status is read only when the app comes to the front: no polling, nothing in the background.
        .task(id: phase) {
            store.setActive(phase == .active)
            if phase == .active { await store.refresh() }
        }
    }
}
