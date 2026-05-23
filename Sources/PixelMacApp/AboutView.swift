import SwiftUI

struct AboutView: View {
    let relayURL: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingIntegration = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(red: 0.45, green: 0.30, blue: 0.85))

            Text("pixel-agent")
                .font(.title.bold())

            Text("macOS için pixel-art mascot AI ajanı")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Versiyon \(version)")
                } icon: {
                    Image(systemName: "tag")
                        .frame(width: 18)
                }

                Label {
                    Text(relayURL)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "network")
                        .frame(width: 18)
                }

                Label {
                    Link("github.com/ErkutYavuzer/pixel-agent",
                         destination: URL(string: "https://github.com/ErkutYavuzer/pixel-agent")!)
                } icon: {
                    Image(systemName: "link")
                        .frame(width: 18)
                }

                Label {
                    Text("MIT lisansı")
                } icon: {
                    Image(systemName: "doc.text")
                        .frame(width: 18)
                }
            }
            .padding(.horizontal)

            Button {
                showingIntegration = true
            } label: {
                Label("MCP Entegrasyonu…", systemImage: "puzzlepiece.extension")
            }
            .padding(.top, 6)

            Button("Kapat", action: { dismiss() })
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 360)
        .sheet(isPresented: $showingIntegration) {
            IntegrationView()
        }
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}
