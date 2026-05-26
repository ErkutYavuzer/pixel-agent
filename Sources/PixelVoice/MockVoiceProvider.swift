import Foundation

/// **Sprint 42 (v0.2.69):** Test için programmable VoiceProvider.
///
/// `enqueue(_:)` ile scripted event'ler. `start()` çağrısından sonra
/// stream'e yields. `speak(_:)` no-op (string'i bir buffer'a kaydeder).
/// Permission her zaman authorized.
///
/// Production'da KULLANILMAZ — sadece XCTest harness'i için.
public actor MockVoiceProvider: VoiceProvider {
    public nonisolated let providerName: String = "Mock"

    private var continuation: AsyncStream<TranscriptEvent>.Continuation?
    private var pendingEvents: [TranscriptEvent] = []
    private var spokenTexts: [String] = []
    private var isStarted: Bool = false

    public init() {}

    public nonisolated var transcriptEvents: AsyncStream<TranscriptEvent> {
        AsyncStream { continuation in
            Task { await self.setContinuation(continuation) }
        }
    }

    private func setContinuation(_ cont: AsyncStream<TranscriptEvent>.Continuation) {
        self.continuation = cont
        // Pending event'leri flush et
        for event in pendingEvents {
            cont.yield(event)
        }
        pendingEvents.removeAll()
    }

    public func start() async throws {
        isStarted = true
    }

    public func stop() async {
        isStarted = false
        continuation?.finish()
        continuation = nil
    }

    public func speak(_ text: String) async {
        spokenTexts.append(text)
    }

    public func cancelSpeech() async {
        // No-op for mock
    }

    public func isAuthorized() async -> Bool {
        true
    }

    // MARK: - Test API

    /// **Sprint 42:** Test'lerden scripted event yield. Continuation
    /// hazırsa hemen, değilse pending listede.
    public func enqueue(_ event: TranscriptEvent) {
        if let continuation {
            continuation.yield(event)
        } else {
            pendingEvents.append(event)
        }
    }

    /// **Sprint 42:** Test'lerden `speak()` çağrılan metinleri okur.
    public func snapshotSpokenTexts() -> [String] {
        spokenTexts
    }

    public func snapshotIsStarted() -> Bool {
        isStarted
    }

    /// **Sprint 42:** Stream'i programatik sonlandır.
    public func finishStream() {
        continuation?.finish()
        continuation = nil
    }
}
