import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: RemoteSession

    var body: some View {
        if session.pairing != nil {
            ChatView()
        } else if session.isAutoConnecting {
            VStack(spacing: 12) {
                ProgressView()
                Text("Otomatik bağlanılıyor...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        } else {
            PairingScannerView { info in
                Task { await session.connect(pairing: info) }
            }
        }
    }
}
