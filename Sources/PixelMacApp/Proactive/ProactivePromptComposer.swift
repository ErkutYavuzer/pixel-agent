import Foundation

/// **Sprint 40 (v0.2.67):** Proaktif trigger → ChatView draft prompt composer.
///
/// Kullanıcı macOS notification'a tıkladığında `NotificationActionDispatcher`
/// trigger context'ini decode eder ve bu composer ile draft text üretir.
/// Draft kullanıcının composer field'ına otomatik yazılır; kullanıcı düzenleyip
/// göndermeyi seçer (auto-send YOK — confirm-first UX).
///
/// **First-person user voice:** Prompt'lar kullanıcının ağzından (örn "Ben"
/// değil "Ben az önce X yaptım..."). Agent'ın ne yapacağını söyleyen değil,
/// kullanıcının ne sorabileceğini öneren içerik. Bu Sprint 36 PlaybookLearner
/// system prompt'tan farklı — burada user message draft.
///
/// **v2 referans** (`AppDelegate+Lifecycle.swift:181-203`): v2 trigger sonrası
/// arka planda LLM oneShot çağırıyordu; v3 farklı paradigma — kullanıcı kontrolünde
/// pre-fill + manuel send.
public enum ProactivePromptComposer {
    /// **Sprint 40:** Trigger → draft text. View'dan ayrı saf helper.
    /// Test edilebilir (per-trigger Turkish copy assertion'ları).
    public static func prompt(for trigger: ProactiveTrigger) -> String {
        switch trigger {
        case .idle(let minutes):
            return "Son \(minutes) dakikadır masaya dönmedim. Ne yapmam gerektiğini hatırlatır mısın?"

        case .appChanged(let name, _):
            return "\(name) uygulamasına geçtim. Bu uygulamayla ilgili bir konuda yardımcı olabilir misin?"

        case .windowDwell(let app, let title, let minutes, _):
            if title.isEmpty {
                return "\(minutes) dakikadır \(app) uygulamasında çalışıyorum. Bir noktada tıkandım sanırım; ne yapmam gerektiğini önerir misin?"
            }
            return "\(minutes) dakikadır \(app) — \(title) penceresindeyim. Bir noktada tıkandım sanırım; gözden geçirip yardımcı olur musun?"

        case .typedPause(let app, _):
            return "\(app)'te yazıyordum ama tıkandım. Şu ana kadar yazdığım metni okuyup geri bildirim verir misin? (Composer'da yapıştırabilirim.)"

        case .upcomingEvent(let title, let minutesUntil, let location):
            let locationPart = location.flatMap { loc in
                loc.isEmpty ? nil : " (\(loc))"
            } ?? ""
            return "\(minutesUntil) dakika sonra \"\(title)\" toplantım başlıyor\(locationPart). Toplantıya hazırlanmak için ne tavsiye edersin?"
        }
    }
}
