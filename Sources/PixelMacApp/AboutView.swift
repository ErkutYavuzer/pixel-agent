import SwiftUI

struct AboutView: View {
    let relayURL: String
    @Environment(\.dismiss) private var dismiss

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

            Button("Kapat", action: { dismiss() })
                .keyboardShortcut(.cancelAction)
                .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 360)
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}
