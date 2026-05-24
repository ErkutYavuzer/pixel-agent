import AppKit
import Foundation
import PixelComputerUse
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
    /// C2/C3: Ephemeral screenshot attachment'ları. Message id → ScreenshotAttachment.
    /// JSONL store'a yazılmaz (büyük binary data) — app restart'ta kaybolur.
    /// MessageRow render sırasında dict'i sorgular; varsa inline image render.
    @Published var screenshotAttachments: [UUID: ScreenshotAttachment] = [:]

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
            // **Sprint 4 (C2/C3 follow-up):** Restart sonrası screenshot
            // attachment'larını disk'ten hidrate et. `.system` + placeholder
            // prefix sentinel'i ile filtre — boşuna dosya lookup'ı yok.
            for msg in restored where shouldHydrateScreenshot(message: msg) {
                guard let pngData = try? ScreenshotStore.load(for: msg.id) else {
                    continue
                }
                guard let image = NSImage(data: pngData),
                      let rep = image.representations.first else {
                    continue
                }
                let pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                // **Sprint 6 (SoM marks sidecar):** marks JSON sidecar varsa
                // decode et — `ui_screenshot(elements:)` overlay'leri restart
                // sonrası geri gelir. Sidecar yok / decode başarısız → boş array
                // (user-initiated capture'larda zaten olmayan durum).
                let marks: [SoMMark]
                if let sidecarData = try? ScreenshotStore.loadSidecar(for: msg.id),
                   let decoded = try? JSONDecoder().decode([SoMMark].self, from: sidecarData) {
                    marks = decoded
                } else {
                    marks = []
                }
                let attachment = ScreenshotAttachment(
                    pngData: pngData,
                    pixelSize: pixelSize,
                    marks: marks,
                    capturedAt: msg.createdAt
                )
                screenshotAttachments[msg.id] = attachment
            }
        } catch {
            streamError = "Mesaj geçmişi yüklenemedi: \(error.localizedDescription)"
        }
    }

    /// **Sprint 4:** `.system` mesajının screenshot placeholder olup olmadığını
    /// belirler. captureScreenshotIntoChat'in ürettiği text format'iyla
    /// senkron.
    private func shouldHydrateScreenshot(message: Message) -> Bool {
        message.role == .system && message.text.hasPrefix("[ekran görüntüsü")
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

    /// C1: Subagent terminal status'a ulaştığında ana chat'e formatlı bir
    /// `.system` mesajı düşer ve conversationStore'a persist edilir. Mesaj
    /// rolünü `.system` seçtik çünkü subagent çıktısı asıl assistant'ın
    /// konuşması değil — uygulamanın yan-akış sonucunu duyurmasıdır.
    func appendSubagentResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let msg = Message(role: .system, text: trimmed)
        messages.append(msg)
        let store = conversationStore
        Task { try? await store.append(msg) }
    }

    /// C2/C3: Aktif display'in ekran görüntüsünü alır, chat akışına `.system`
    /// mesajı + ephemeral attachment olarak ekler. **Sprint 4:** PNG bytes'ı
    /// `ScreenshotStore.save` ile diske persist eder — app restart'ından
    /// sonra `restoreIfNeeded` hidrate eder. **C11:** Composer boşsa LLM'e
    /// "bu ekranda ne görüyorsun" sorusunu prefill eder.
    func captureScreenshotIntoChat() {
        Task {
            do {
                let result = try await ScreenshotCapture.capture(target: .activeDisplay)
                let placeholder = "[ekran görüntüsü · \(result.pixelWidth)×\(result.pixelHeight) px]"
                let msg = Message(role: .system, text: placeholder)
                let attachment = ScreenshotAttachment(
                    pngData: result.pngData,
                    pixelSize: CGSize(width: result.pixelWidth, height: result.pixelHeight),
                    marks: result.marks,
                    capturedAt: result.capturedAt
                )
                messages.append(msg)
                screenshotAttachments[msg.id] = attachment
                let store = conversationStore
                Task { try? await store.append(msg) }
                // **Sprint 4 (C2/C3 follow-up):** PNG bytes'ı diske yaz.
                // Hata best-effort yutar — placeholder text JSONL'de var,
                // sonraki restart'ta sadece görsel kaybolur (mesaj kalır).
                try? ScreenshotStore.save(pngData: result.pngData, for: msg.id)
                // **Sprint 6 (SoM marks sidecar):** marks varsa JSON sidecar
                // dosyasına yaz — restart sonrası numbered overlay'ler de hidrate
                // olur. Marks boşsa dosya yazma (gereksiz IO).
                if !result.marks.isEmpty,
                   let marksData = try? JSONEncoder().encode(result.marks) {
                    try? ScreenshotStore.saveSidecar(jsonData: marksData, for: msg.id)
                }
                // **Sprint 4 (C11 "screenshot → soruna sor"):** Composer boşsa
                // varsayılan soruyu prefill et — kullanıcı eklemeyi tetikleyici
                // bir cümleye bakar, düzenleyip Enter'a basabilir. Composer
                // doluysa kullanıcının taslağına dokunmuyoruz.
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft = Self.defaultScreenshotPrompt
                }
            } catch {
                streamError = "Ekran görüntüsü alınamadı: \(error.localizedDescription)"
            }
        }
    }

    /// **Sprint 4 (C11):** Screenshot sonrası composer'a düşürülen varsayılan
    /// metin. Statik — testten erişim için public.
    static let defaultScreenshotPrompt = "Bu ekran görüntüsünde ne görüyorsun?"

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

/// C2/C3: Ephemeral screenshot bilgisi. PNG bytes + boyut + marks + capture
/// zamanı. ConversationStore'a yazılmaz — chat aktif olduğu sürece RAM'de.
struct ScreenshotAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let pngData: Data
    let pixelSize: CGSize
    let marks: [SoMMark]
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        pngData: Data,
        pixelSize: CGSize,
        marks: [SoMMark] = [],
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.pngData = pngData
        self.pixelSize = pixelSize
        self.marks = marks
        self.capturedAt = capturedAt
    }
}
