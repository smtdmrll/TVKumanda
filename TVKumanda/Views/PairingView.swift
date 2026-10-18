import SwiftUI

struct PairingView: View {
    @Environment(TVStore.self) private var store
    @State private var discovery = TVDiscovery()
    @State private var manualHost = ""
    @State private var pin = ""
    @FocusState private var pinFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if let ticket = store.ticket {
                    Section {
                        TextField("4 haneli kod", text: $pin)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.title2.monospacedDigit())
                            .focused($pinFocused)
                        Button("Eşleştir") {
                            Task { await store.finishPairing(pin: pin) }
                        }
                        .disabled(pin.count < 4 || store.busy)
                        Button("Vazgeç", role: .cancel) {
                            store.cancelPairing()
                            pin = ""
                        }
                    } header: {
                        Text("\(ticket.name) ekranındaki kodu gir")
                    } footer: {
                        Text("Kod TV'de yaklaşık bir dakika görünür. Süre dolarsa vazgeçip yeniden dene.")
                    }
                } else {
                    Section {
                        ForEach(discovery.found) { tv in
                            Button { connect(tv) } label: {
                                Label(tv.name, systemImage: "tv")
                            }
                            .disabled(store.busy)
                        }
                        if discovery.found.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Ev ağında TV aranıyor…").foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Ağdaki TV'ler")
                    } footer: {
                        Text("TV açık olmalı ve telefonla aynı Wi-Fi ağında bulunmalı.")
                    }
                    Section("Adresi elle gir") {
                        TextField("Örn. 192.168.1.109", text: $manualHost)
                            .keyboardType(.decimalPad)
                        Button("Bu adrese bağlan") {
                            Task { await store.beginPairing(host: manualHost, name: "TV") }
                        }
                        .disabled(manualHost.isEmpty || store.busy)
                    }
                }
                if let message = store.message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle("TV'yi eşleştir")
            .overlay { if store.busy { ProgressView().controlSize(.large) } }
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
            .onChange(of: store.ticket != nil) { _, waitingForPin in
                pin = ""
                pinFocused = waitingForPin
            }
        }
    }

    private func connect(_ tv: TVDiscovery.Found) {
        Task {
            guard let host = await TVDiscovery.resolveIPv4(tv.endpoint) else {
                store.message = "TV'nin ağ adresi bulunamadı. Adresi elle girmeyi dene."
                return
            }
            await store.beginPairing(host: host, name: tv.name)
        }
    }
}

struct SettingsView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false
    @State private var googleCode = ""

    var body: some View {
        NavigationStack {
            List {
                if let tv = store.credentials {
                    Section("TV") {
                        LabeledContent("Ad", value: tv.name)
                        LabeledContent("Adres", value: tv.host)
                    }
                }
                Section {
                    LabeledContent("Durum", value: store.appChannelReady ? "Bağlı" : "Bağlı değil")
                    if store.googleCodeShown {
                        TextField("TV'deki 6 karakter", text: $googleCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.title3.monospaced())
                        Button("Eşleştir") {
                            Task { await store.finishGooglePairing(code: googleCode) }
                        }
                        .disabled(googleCode.count != 6 || store.busy)
                        Button("Vazgeç", role: .cancel) { store.cancelGooglePairing() }
                    } else {
                        Button("Kodla yeniden eşleştir") {
                            googleCode = ""
                            Task { await store.beginGooglePairing() }
                        }
                        .disabled(store.busy)
                    }
                    if let message = store.message {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Uygulamalar ve klavye")
                } footer: {
                    Text("TV'nin Google kumanda servisini kullanır. Bu telefon zaten eşli; yeniden eşleme yalnız TV sıfırlanırsa gerekir.")
                }
                Section {
                    Button("Eşleşmeyi kaldır", role: .destructive) { confirmForget = true }
                } footer: {
                    Text("Kaldırırsan TV'de çıkacak yeni bir kodla tekrar eşleştirmen gerekir.")
                }
                Section {
                    LabeledContent("Sürüm", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .confirmationDialog("Eşleşme kaldırılsın mı?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Kaldır", role: .destructive) {
                    store.forget()
                    dismiss()
                }
            }
        }
    }
}
