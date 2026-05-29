import Foundation
import PixelComputerUse
import PixelMemory

/// **Sprint 52 (v0.2.81) — F1 Faz 1B.** Computer-use makro kaydedici.
///
/// `ControlSocketServer`'ın `onUIActionRecorded` hook'u, agent'ın başarılı
/// `ui_click`/`ui_type` çağrılarını (semantik `MacroStep` olarak) buraya iletir;
/// kayıt aktifse `draftSteps`'e eklenir. `stop()` kaydı `MacroStore`'a persiste
/// eder.
///
/// `static let shared` — app composition-root instance (controlServer/
/// voiceProvider paterni); hook, `.commands` menüsü ve Settings aynı instance'ı
/// görür. Test için `init(store:)` ile DI (geçici dizinli MacroStore).
@MainActor
final class MacroRecorder: ObservableObject {
    static let shared = MacroRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var draftSteps: [MacroStep] = []
    @Published var draftTitle: String = ""

    private let store: MacroStore?

    init(store: MacroStore? = nil) {
        self.store = store ?? (try? MacroStore())
    }

    /// Kayda başla. Aktif kayıt varsa onu sıfırlar (üzerine yazar).
    func start(title: String = "") {
        isRecording = true
        draftTitle = title
        draftSteps = []
    }

    /// Bridge hook'undan (MainActor'a hop ederek) çağrılır. Kayıt aktif
    /// değilse no-op — replay'in kendi aksiyonları (bridge'den geçmez) ve
    /// kayıt-dışı kullanım kaydedilmez.
    func record(_ step: MacroStep) {
        guard isRecording else { return }
        draftSteps.append(step)
    }

    /// Kaydı bitir + persiste et. Boş kayıt veya store yoksa nil (kayıt atılır).
    @discardableResult
    func stop() async -> MacroRecording? {
        guard isRecording else { return nil }
        isRecording = false
        let steps = draftSteps
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        draftSteps = []
        guard !steps.isEmpty, let store else { return nil }
        let recording = MacroRecording(
            title: trimmed.isEmpty ? Self.defaultTitle() : trimmed,
            steps: steps
        )
        return try? await store.save(recording)
    }

    /// Kaydı kaydetmeden iptal et.
    func cancel() {
        isRecording = false
        draftSteps = []
        draftTitle = ""
    }

    static func defaultTitle(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM HH:mm"
        return "Makro \(f.string(from: now))"
    }
}
