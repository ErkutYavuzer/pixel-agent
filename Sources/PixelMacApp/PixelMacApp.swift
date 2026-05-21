import PixelBackends
import PixelCore
import SwiftUI

@main
struct PixelMacApp: App {
    var body: some Scene {
        WindowGroup("pixel-agent") {
            RootView()
                .frame(minWidth: 480, minHeight: 360)
        }
    }
}

struct RootView: View {
    @State private var backend: AnthropicBackend?
    @State private var initError: String?

    init() {
        do {
            let backend = try AnthropicBackend()
            _backend = State(initialValue: backend)
            _initError = State(initialValue: nil)
        } catch {
            _backend = State(initialValue: nil)
            _initError = State(initialValue: Self.describe(error))
        }
    }

    var body: some View {
        if let backend {
            ChatView(backend: backend)
        } else {
            ErrorView(message: initError ?? "Bilinmeyen hata", onRetry: retry)
        }
    }

    private func retry() {
        do {
            backend = try AnthropicBackend()
            initError = nil
        } catch {
            backend = nil
            initError = Self.describe(error)
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Backend başlatılamadı")
                .font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Tekrar dene", action: onRetry)
                .keyboardShortcut(.return)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
