import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: RemoteSession

    var body: some View {
        if session.isConnected {
            ChatView()
        } else {
            PairingScannerView { info in
                Task { await session.connect(pairing: info) }
            }
        }
    }
}
