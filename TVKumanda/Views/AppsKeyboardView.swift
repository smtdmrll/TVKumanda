import SwiftUI

struct AppsView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TVApp.all) { app in
                        Button {
                            store.launch(app)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: app.symbol)
                                    .font(.system(size: 26, weight: .semibold))
                                Text(app.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 92)
                            .background(RoundedRectangle(cornerRadius: 18).fill(app.color.gradient))
                        }
                        .accessibilityLabel("\(app.name) aç")
                    }
                }
                .padding()
                if !store.appChannelReady {
                    Label("TV'ye bağlanılıyor…", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Uygulamalar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
        }
    }
}

struct KeyboardView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// What has already been mirrored to the TV; edits are computed against this, not against `text`.
    @State private var sent = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label(store.textFieldActive ? "TV'deki yazı alanına yazılıyor" : "Önce TV'de bir yazı alanı seç",
                      systemImage: store.textFieldActive ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                    .font(.footnote)
                    .foregroundStyle(store.textFieldActive ? .green : .secondary)
                if store.textFieldActive {
                    Text(store.tvText.isEmpty ? "TV'deki alan boş" : "TV'de: \(store.tvText)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
                TextField("Yaz…", text: $text)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
                    .onSubmit {
                        store.enter()
                        focused = true
                    }
                HStack(spacing: 10) {
                    ForEach(["www.", ".com", ".com.tr"], id: \.self) { piece in
                        Button(piece) { text += piece }
                            .buttonStyle(.bordered)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        store.deleteOnTV()
                    } label: {
                        Label("Sil", systemImage: "delete.left")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        store.clearTV()
                        sent = ""
                        text = ""
                    } label: {
                        Label("Temizle", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button {
                        store.enter()
                    } label: {
                        Label("Git", systemImage: "return")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("TV Bro'da adres çubuğu için: Menü tuşu → adres alanı → OK. Netflix ve YouTube kendi ekran klavyelerini kullandığı için oralara telefondan yazı gitmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Klavye")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .onAppear { focused = true }
            .onChange(of: text) { _, new in
                store.type(from: sent, to: new)
                sent = new
            }
            // A newly focused TV field starts from its own content; the box here only collects new typing.
            .onChange(of: store.textFieldActive) { _, active in
                sent = ""
                text = ""
            }
        }
    }
}

/// Wide capsule used for the apps and keyboard entries.
struct PillButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(.white.opacity(0.09)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        }
        .foregroundStyle(.white)
    }
}
