import Foundation
import PixelMascot
import PixelVoice

/// **Sprint 42 (v0.2.69):** Voice session orchestrator — `VoiceProvider`
/// stream'ini ChatViewModel'a köprü.
///
/// Lifecycle:
/// 1. `startCapture()` — provider.start(); transcriptEvents'i drain;
///    `.interim` → `viewModel.draft = text` (live preview); `.final` →
///    `viewModel.send(text:)` (otomatik gönder — voice modunda confirm-first
///    UX'i bozar; v0.2.70+ aday: "Final segment edit + Enter" opt-in).
/// 2. Agent cevap streaming — `onAssistantChunk` callback'iyle text birikir;
///    final `onAssistantComplete`'te `provider.speak(text)`.
/// 3. `stopCapture()` — provider.stop(); session bitti.
///
/// **Sprint 50 (v0.2.79):** Mascot wiring — capture açıkken/kullanıcı
/// konuşurken `.listening` (dikkatli dinleme hali); segment `.final` olunca
/// `send()` devralır (`.thinking`); interrupt'ta tekrar `.listening`. Eşleme
/// `VoiceMascotResolver` saf helper'ında (test edilebilir). `nil` dönüş
/// "mascot'a dokunma" → text-turn akışı sahipliği korur.
///
/// `@MainActor ObservableObject` — SwiftUI binding için. ChatView mic
/// FAB butonu state'i bu objeden okur.
@MainActor
final class VoiceSession: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var liveTranscript: String = ""

    private let provider: any VoiceProvider
    private var streamTask: Task<Void, Never>?
    private weak var viewModel: ChatViewModel?

    init(provider: any VoiceProvider, viewModel: ChatViewModel? = nil) {
        self.provider = provider
        self.viewModel = viewModel
    }

    func attach(to viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    /// **Sprint 42:** Capture başlat. Mikrofon iconu tap'inde çağrılır.
    /// Hata olursa `lastError` set + `isActive` false.
    func startCapture() {
        guard !isActive else { return }
        lastError = nil
        liveTranscript = ""

        streamTask?.cancel()
        let stream = provider.transcriptEvents
        let providerRef = provider
        streamTask = Task { [weak self] in
            do {
                try await providerRef.start()
                await MainActor.run {
                    self?.isActive = true
                    self?.applyMascot(.captureStarted)
                }
                for await event in stream {
                    if Task.isCancelled { break }
                    await self?.handle(event: event)
                }
            } catch {
                await MainActor.run {
                    self?.lastError = error.localizedDescription
                    self?.isActive = false
                }
            }
        }
    }

    /// **Sprint 42:** Capture durdur. Mic button toggle veya provider hatası.
    func stopCapture() {
        streamTask?.cancel()
        streamTask = nil
        Task { [provider] in
            await provider.stop()
        }
        isActive = false
        liveTranscript = ""
        applyMascot(.captureStopped)
    }

    /// **Sprint 42:** Agent cevabını seslendirmek için ChatHost'tan çağrılır
    /// (onAssistantComplete callback).
    func speakAssistantReply(_ text: String) {
        Task { [provider] in
            await provider.speak(text)
        }
    }

    /// **Sprint 42:** Speech ortasında durdurmak için (örn kullanıcı yeni
    /// soru sormaya başladı). Sprint 43 OpenAI Realtime'da server-side VAD
    /// otomatik handle eder; Apple'da manuel.
    func interruptSpeech() {
        applyMascot(.interrupted)
        Task { [provider] in
            await provider.cancelSpeech()
        }
    }

    // MARK: - Private

    private func handle(event: TranscriptEvent) async {
        switch event {
        case .interim(let text):
            liveTranscript = text
            applyMascot(.transcriptInterim)
            // Composer canlı preview — kullanıcı görsün
            viewModel?.injectDraft(text)
        case .final(let text):
            liveTranscript = ""
            // Mascot'a dokunma (.transcriptFinal → nil): send() .thinking set eder
            // Otomatik gönder — voice akışı doğal
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                viewModel?.send(text: text)
            }
        case .error(let message):
            lastError = message
            isActive = false
            applyMascot(.failed)
        }
    }

    /// **Sprint 50 (v0.2.79):** Voice olayını `VoiceMascotResolver` ile mascot
    /// state'ine eşler ve (nil değilse) viewModel'a uygular.
    private func applyMascot(_ event: VoiceMascotResolver.Event) {
        guard let state = VoiceMascotResolver.mascotState(for: event) else { return }
        viewModel?.mascotState = state
    }
}
