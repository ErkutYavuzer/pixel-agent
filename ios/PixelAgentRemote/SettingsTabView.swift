import PixelRemote
import SwiftUI

/// iOS dashboard 4. tab — Ayarlar (B8).
///
/// Mevcut `AboutView` modal sheet'in tab eşdeğeri; ek olarak transport
/// label (LAN/Relay) + Mac public key fingerprint görünür ve eylem
/// butonları (disconnect / forget pairing) buraya taşındı.
struct SettingsTabView: View {
    @EnvironmentObject var session: RemoteSession
    @State private var showConfirmForget: Bool = false

    var body: some View {
        Form {
            connectionSection
            pairingSection
            macInfoSection
            appSection
            actionsSection
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            HStack {
                Circle()
                    .fill(session.isConnected ? .green : .secondary.opacity(0.6))
                    .frame(width: 10, height: 10)
                Text(session.isConnected ? "Bağlı" : "Bağlı değil")
                    .font(.body)
                Spacer()
                if let transport = session.transportLabel {
                    Text(transport)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (transport == "LAN" ? Color.green : Color.blue).opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(transport == "LAN" ? .green : .blue)
                }
            }
            if let error = session.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Durum")
        }
    }

    @ViewBuilder
    private var pairingSection: some View {
        if let pairing = session.pairing {
            Section {
                LabeledContent("Kod") {
                    Text(pairing.code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Relay") {
                    Text(pairing.relayURL)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Eşleşme")
            }
        } else {
            Section {
                Label("Henüz eşleşmemiş",
                      systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Text("Ana ekrana dön ve Mac QR kodunu tara.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Eşleşme")
            }
        }
    }

    @ViewBuilder
    private var macInfoSection: some View {
        if let pk = session.pairing?.macPublicKey {
            Section {
                Text(PublicKeyFormatter.format(pk))
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Mac genel anahtarı (ed25519)")
            } footer: {
                Text("ADR-0015: envelope imzaları bu anahtarla doğrulanır. QR'ı doğru cihazdan tarayıp taramadığını görsel doğrulamak için.")
                    .font(.caption2)
            }
        }
    }

    private var appSection: some View {
        Section {
            LabeledContent("Versiyon", value: Self.appVersion)
            LabeledContent("Build", value: Self.appBuild)
            Link("github.com/ErkutYavuzer/pixel-agent",
                 destination: URL(string: "https://github.com/ErkutYavuzer/pixel-agent")!)
        } header: {
            Text("Uygulama")
        }
    }

    private var actionsSection: some View {
        Section {
            if session.isConnected {
                Button {
                    Task { await session.disconnect(forget: false) }
                } label: {
                    Label("Bağlantıyı kapat", systemImage: "wifi.slash")
                }
            } else if let pairing = session.pairing {
                Button {
                    Task { await session.connect(pairing: pairing) }
                } label: {
                    Label("Yeniden bağlan", systemImage: "wifi")
                }
            }

            if session.pairing != nil {
                Button(role: .destructive) {
                    showConfirmForget = true
                } label: {
                    Label("Eşleşmeyi sıfırla", systemImage: "trash")
                }
            }
        } header: {
            Text("Eylemler")
        } footer: {
            Text("Eşleşmeyi sıfırlamak QR kodu yeniden tarama akışını başlatır. Mac'in IP'si değiştiyse gerekli.")
                .font(.caption2)
        }
        .alert("Eşleşmeyi sıfırla?", isPresented: $showConfirmForget) {
            Button("İptal", role: .cancel) {}
            Button("Sıfırla", role: .destructive) {
                Task { await session.disconnect(forget: true) }
            }
        } message: {
            Text("Persisted eşleşme bilgisi silinecek; ana ekrandan QR tarayarak yeniden eşleşmen gerekecek.")
        }
    }

    // MARK: - Metadata

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    private static var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
    }
}

