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

    let backend: any ChatBackend
    let conversationStore: ConversationStore
    var onAssistantComplete: ((String) -> Void)?

    private var streamTask: Task<Void, Never>?
    private var didRestore: Bool = false

    init(
        backend: any ChatBackend,
        conversationStore: ConversationStore,
        onAssistantComplete: ((String) -> Void)? = nil
    ) {
        self.backend = backend
        self.conversationStore = conversationStore
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

        Task { try? await store.append(userMsg) }

        streamTask = Task {
            do {
                var firstChunkSeen = false
                let stream = backend.send(messages: snapshot, system: nil)
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
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        mascotState = .idle
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

        if success {
            if let assistant = messages.first(where: { $0.id == assistantID }), !assistant.text.isEmpty {
                let store = conversationStore
                let text = assistant.text
                Task { try? await store.append(assistant) }
                onAssistantComplete?(text)
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
