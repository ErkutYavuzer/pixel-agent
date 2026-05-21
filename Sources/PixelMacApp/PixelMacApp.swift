import SwiftUI

@main
struct PixelMacApp: App {
    var body: some Scene {
        WindowGroup("pixel-agent") {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("pixel-agent — Hafta 1 foundation")
            .font(.title2)
            .padding(40)
    }
}
