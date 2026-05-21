import AppKit
import Foundation
import PixelCore
import PixelMascot
import PixelTools
import SwiftUI

struct ChatView: View {
    let backend: any ChatBackend

    @State private var messages: [Message] = []
    @State private var draft: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamError: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var mascotState: MascotState = .idle

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                MascotView(state: mascotState, size: 32)
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.last?.text) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let streamError {
                Text(streamError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Mesaj yaz...", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send() }
                    .disabled(isStreaming)

                if isStreaming {
                    Button("Durdur", action: cancelStream)
                        .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Button("Gönder", action: send)
                        .keyboardShortcut(.return)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
        }
    }

    private var statusText: String {
        switch mascotState {
        case .idle: return "Hazır"
        case .thinking: return "Düşünüyor..."
        case .speaking: return "Yazıyor..."
        case .error: return "Hata"
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let userMsg = Message(role: .user, text: text)
        messages.append(userMsg)
        draft = ""

        let assistantMsg = Message(role: .assistant, text: "")
        messages.append(assistantMsg)
        let assistantID = assistantMsg.id

        isStreaming = true
        streamError = nil
        mascotState = .thinking
        DockBadge.clear()

        let snapshot = Array(messages.dropLast())
        let backend = self.backend

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
                                mascotState = .speaking
                            }
                            updateAssistantText(id: assistantID, appending: chunk)
                        }
                    case .done:
                        break
                    }
                }
                await MainActor.run { finishStream(success: true) }
            } catch {
                await MainActor.run {
                    streamError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    finishStream(success: false)
                }
            }
        }
    }

    private func finishStream(success: Bool) {
        isStreaming = false
        mascotState = success ? .idle : .error

        if success {
            if NSApp.isActive {
                SoundEffect.play(SoundEffect.messageReceived)
            } else {
                DockBadge.set("1")
                Task {
                    await SystemNotifications.post(
                        title: "pixel",
                        body: "Yeni yanıt hazır"
                    )
                }
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

    private func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        mascotState = .idle
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(badge)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor, in: .capsule)

            Text(message.text.isEmpty ? "…" : message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var badge: String {
        switch message.role {
        case .user: return "SİZ"
        case .assistant: return "PIXEL"
        case .system: return "SYS"
        }
    }

    private var badgeColor: Color {
        switch message.role {
        case .user: return .blue
        case .assistant: return .purple
        case .system: return .gray
        }
    }
}
