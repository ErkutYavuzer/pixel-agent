import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: RemoteSession

    var body: some View {
        if session.isAutoConnecting {
            VStack(spacing: 12) {
                ProgressView()
                Text("Otomatik bağlanılıyor...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let pairing = session.pairing {
                    Text(pairing.code)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(40)
        } else if session.isConnected {
            ChatView()
        } else {
            PairingScannerView { info in
                Task { await session.connect(pairing: info) }
            }
        }
    }
}
