import SwiftUI

struct AboutView: View {
    @EnvironmentObject var session: RemoteSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Bağlantı") {
                    if let pairing = session.pairing {
                        LabeledContent("Pairing kodu") {
                            Text(pairing.code)
                                .font(.caption.monospaced())
                        }
                        LabeledContent("Relay") {
                            Text(pairing.relayURL)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        Text("Eşleşmiş cihaz yok")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Circle()
                            .fill(session.isConnected ? .green : .secondary.opacity(0.6))
                            .frame(width: 8, height: 8)
                        Text(session.isConnected ? "Bağlı" : "Bağlı değil")
                    }

                    if let error = session.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Uygulama") {
                    LabeledContent("Versiyon", value: version)
                    LabeledContent("Build", value: build)
                    Link("github.com/ErkutYavuzer/pixel-agent",
                         destination: URL(string: "https://github.com/ErkutYavuzer/pixel-agent")!)
                }

                Section {
                    Button("Pairing'i sıfırla (yeniden QR tara)", role: .destructive) {
                        Task {
                            await session.disconnect(forget: true)
                            dismiss()
                        }
                    }
                } footer: {
                    Text("Mac'i değiştirirsen veya Mac'in IP'si değişirse bu işe yarar.")
                        .font(.caption)
                }
            }
            .navigationTitle("Hakkında")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    private var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
    }
}
