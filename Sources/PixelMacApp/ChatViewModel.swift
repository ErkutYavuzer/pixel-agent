import AppKit
import Foundation
import PixelCore
import PixelMascot
import PixelMemory
import PixelTools

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var draft: String = ""
    @Published var isStreaming: Bool = false
    @Published var streamError: String?
    @Published var mascotState: MascotState = .idle
    /// Plan Mode: backend'e `ChatOptions(planMode: true)` ile gönderilir.
    /// Claude için `--permission-mode plan` flag'ine dönüşür (read-only tool allowlist).
    /// Codex/Gemini'de no-op (CLI'lar native desteklemiyor).
    @Published var planMode: Bool = false

    let backend: any ChatBackend
    let conversationStore: ConversationStore
    var onAssistantChunk: ((String, String) -> Void)?
    var onAssistantComplete: ((String, String) -> Void)?

    private var streamTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var didRestore: Bool = false

    /// Backend stdout'a yanıt vermediği halde kaç saniye bekleyeceğimiz.
    /// Süre dolarsa stream cancel + UI'da hata mesajı.
    var streamTimeoutSeconds: TimeInterval = 60

    init(
        backend: any ChatBackend,
        conversationStore: ConversationStore,
        onAssistantChunk: ((String, String) -> Void)? = nil,
        onAssistantComplete: ((String, String) -> Void)? = nil
    ) {
        self.backend = backend
        self.conversationStore = conversationStore
        self.onAssistantChunk = onAssistantChunk
        self.onAssistantComplete = onAssistantComplete
    }

    func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true
        do {
            let restored = try await conversationStore.loadAll(limit: 200)
            messages = restored
        } catch {
            streamError = "Mesaj geçmişi yüklenemedi: \(error.localizedDescription)"
        }
    }

    func newConversation() {
        let store = conversationStore
        messages.removeAll()
        streamError = nil
        mascotState = .idle
        DockBadge.clear()
        Task { try? await store.newConversation() }
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMsg = Message(role: .user, text: trimmed)
        messages.append(userMsg)

        let assistantMsg = Message(role: .assistant, text: "")
        messages.append(assistantMsg)
        let assistantID = assistantMsg.id

        isStreaming = true
        streamError = nil
        mascotState = .thinking
        DockBadge.clear()

        let snapshot = Array(messages.dropLast())
        let backend = self.backend
        let store = self.conversationStore
        let options = ChatOptions(planMode: planMode)

        Task { try? await store.append(userMsg) }

        streamTask = Task {
            do {
                var firstChunkSeen = false
                let stream = backend.send(messages: snapshot, system: nil, options: options)
                for try await delta in stream {
                    if Task.isCancelled { break }
                    switch delta {
                    case .textChunk(let chunk):
                        await MainActor.run {
                            if !firstChunkSeen {
                                firstChunkSeen = true
                                self.mascotState = .speaking
                            }
                            self.updateAssistantText(id: assistantID, appending: chunk)
                            self.onAssistantChunk?(chunk, assistantID.uuidString)
                        }
                    case .done:
                        break
                    }
                }
                await MainActor.run { self.finishStream(success: true, assistantID: assistantID) }
            } catch {
                await MainActor.run {
                    self.streamError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.finishStream(success: false, assistantID: assistantID)
                }
            }
        }

        startTimeoutWatchdog()
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        isStreaming = false
        mascotState = .idle
    }

    /// A7: hata banner'ından "Kapat" — error mesajını gizler, mesaj listesini
    /// olduğu gibi bırakır.
    func clearError() {
        streamError = nil
    }

    /// A7: hata banner'ından "Tekrar dene" — son [user, emptyAssistant] çiftini
    /// listeden çıkartır ve user metnini yeniden gönderir. Streaming aktifken
    /// veya retry adayı yoksa no-op.
    func retryLastSend() {
        guard !isStreaming else { return }
        guard let userText = RetryHelper.candidateRetryText(messages: messages) else { return }
        messages.removeLast(2)
        streamError = nil
        send(text: userText)
    }

    private func startTimeoutWatchdog() {
        watchdogTask?.cancel()
        let seconds = streamTimeoutSeconds
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self else { return }
            await MainActor.run {
                guard self.isStreaming else { return }
                self.streamError = "Backend \(Int(seconds)) saniyede yanıt vermedi. CLI auth/quota kontrol et."
                self.streamTask?.cancel()
                self.streamTask = nil
                self.isStreaming = false
                self.mascotState = .error
                SoundEffect.play(SoundEffect.errorOccurred)
                DockBadge.set("!")
            }
        }
    }

    var statusText: String {
        switch mascotState {
        case .idle: return messages.isEmpty ? "Hazır" : "Hazır • \(messages.count) mesaj"
        case .thinking: return "Düşünüyor..."
        case .speaking: return "Yazıyor..."
        case .error: return "Hata"
        }
    }

    private func finishStream(success: Bool, assistantID: UUID) {
        isStreaming = false
        mascotState = success ? .idle : .error
        watchdogTask?.cancel()
        watchdogTask = nil

        if success {
            if let assistant = messages.first(where: { $0.id == assistantID }), !assistant.text.isEmpty {
                let store = conversationStore
                let text = assistant.text
                Task { try? await store.append(assistant) }
                onAssistantComplete?(text, assistantID.uuidString)
            }

            if NSApp.isActive {
                SoundEffect.play(SoundEffect.messageReceived)
            } else {
                DockBadge.set("1")
                Task { await SystemNotifications.post(title: "pixel", body: "Yeni yanıt hazır") }
            }
        } else {
            SoundEffect.play(SoundEffect.errorOccurred)
            DockBadge.set("!")
        }
    }

    private func updateAssistantText(id: UUID, appending chunk: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += chunk
    }
}
