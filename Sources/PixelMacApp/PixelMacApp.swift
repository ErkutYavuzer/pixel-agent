import PixelBackends
import PixelCore
import PixelMemory
import PixelTools
import SwiftUI

@main
struct PixelMacApp: App {
    var body: some Scene {
        WindowGroup("pixel-agent") {
            RootView()
                .frame(minWidth: 520, minHeight: 400)
        }
    }
}

struct RootView: View {
    @State private var backends: [CLIKind: CLIBackend]
    @State private var conversationStore: ConversationStore?
    @State private var initErrorMessage: String?

    init() {
        _backends = State(initialValue: Self.resolveBackends())
        do {
            let store = try ConversationStore()
            _conversationStore = State(initialValue: store)
            _initErrorMessage = State(initialValue: nil)
        } catch {
            _conversationStore = State(initialValue: nil)
            _initErrorMessage = State(initialValue: "Mesaj deposu açılamadı: \(error.localizedDescription)")
        }
    }

    var body: some View {
        Group {
            if let errorMessage = initErrorMessage {
                ErrorView(message: errorMessage, onRetry: retryStore)
            } else if backends.isEmpty {
                ErrorView(
                    message: BackendError.noBackendAvailable.errorDescription ?? "",
                    onRetry: rescan
                )
            } else if let store = conversationStore {
                ChatHost(backends: backends, conversationStore: store)
            } else {
                ErrorView(message: "Bilinmeyen başlatma hatası", onRetry: retryStore)
            }
        }
        .task {
            _ = await SystemNotifications.requestAuthorization()
        }
    }

    private func rescan() {
        backends = Self.resolveBackends()
    }

    private func retryStore() {
        do {
            conversationStore = try ConversationStore()
            initErrorMessage = nil
        } catch {
            conversationStore = nil
            initErrorMessage = "Mesaj deposu açılamadı: \(error.localizedDescription)"
        }
    }

    private static func resolveBackends() -> [CLIKind: CLIBackend] {
        var resolved: [CLIKind: CLIBackend] = [:]
        let detector = CLIDetector()
        for (kind, path) in detector.available() {
            resolved[kind] = CLIBackend(kind: kind, executablePath: path)
        }
        return resolved
    }
}

struct ChatHost: View {
    let backends: [CLIKind: CLIBackend]
    let conversationStore: ConversationStore
    @State private var selectedKind: CLIKind

    init(backends: [CLIKind: CLIBackend], conversationStore: ConversationStore) {
        self.backends = backends
        self.conversationStore = conversationStore
        let initial = CLIKind.allCases.first(where: { backends[$0] != nil }) ?? .gemini
        _selectedKind = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Backend", selection: $selectedKind) {
                    ForEach(CLIKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()

                Text(modelText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            if let backend = backends[selectedKind] {
                ChatView(backend: backend, conversationStore: conversationStore)
            } else {
                MissingBackendView(kind: selectedKind)
            }
        }
    }

    private var modelText: String {
        backends[selectedKind]?.modelID ?? "—"
    }
}

struct MissingBackendView: View {
    let kind: CLIKind

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("\(kind.displayName) CLI yüklü değil")
                .font(.headline)
            Text("\(kind.executableName) PATH'te veya bilinen yollarda bulunamadı.\nYükleyip uygulamayı yeniden başlatın.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Text("Başlatılamadı")
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
