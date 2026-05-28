import PixelMascot

/// **Sprint 50 (v0.2.79):** Sesli mod olaylarını mascot state'ine eşleyen saf
/// yardımcı. `VoiceSession` bu eşlemeyi uygular.
///
/// `nil` dönüş "mascot'a dokunma" anlamına gelir — text-turn akışı
/// (`ChatViewModel` `.thinking`/`.speaking`/`.idle`) o anki sahipliği korur.
/// Böylece kullanıcı konuşurken `.listening`, segment bitince `send()` devralıp
/// `.thinking`'e geçer; çakışma olmaz.
///
/// Saf + View'dan ayrık → hermetic test (VoiceMascotResolverTests).
enum VoiceMascotResolver {
    /// Mascot'u etkileyen voice olayları.
    enum Event {
        /// Mikrofon açıldı — dinlemeye başla.
        case captureStarted
        /// Kullanıcı konuşuyor (interim transcript) — dinlemeyi sürdür.
        case transcriptInterim
        /// Segment tamamlandı — `send()` devralır (mascot'a dokunma).
        case transcriptFinal
        /// Kullanıcı agent'ın konuşmasını kesti — tekrar dinlemeye dön.
        case interrupted
        /// Mikrofon kapandı — nötr.
        case captureStopped
        /// Voice hatası — nötr.
        case failed
    }

    /// Olayın ima ettiği mascot state, veya `nil` (mevcut state korunur).
    static func mascotState(for event: Event) -> MascotState? {
        switch event {
        case .captureStarted, .transcriptInterim, .interrupted:
            return .listening
        case .transcriptFinal:
            return nil  // handoff: ChatViewModel.send() .thinking set eder
        case .captureStopped, .failed:
            return .idle
        }
    }
}
