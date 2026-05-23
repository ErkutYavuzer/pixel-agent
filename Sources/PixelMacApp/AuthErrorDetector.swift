import AppKit
import Foundation
import PixelBackends

/// Stream hata mesajını CLI auth/credential hatası olup olmadığına göre
/// sınıflandırır (C9). Demo-readiness kriteri: "CLI auth hatası durumunda
/// actionable retry/login butonu çıkıyor."
///
/// Saf yardımcı — keyword tabanlı (CLI'lar düz exit stderr metni döndürdüğü
/// için tipik hata cümleleri ortak); SwiftUI'a bağımlı değil.
enum AuthErrorDetector {
    /// `message`'da auth/credential işareti varsa true. Türkçe ve İngilizce
    /// terimler dahil — backend timeout watchdog metnimiz Türkçe ("auth/quota
    /// kontrol et"), CLI'ların kendi stderr'i ise İngilizce.
    static func isAuthError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        for keyword in authKeywords {
            if lowered.contains(keyword) {
                return true
            }
        }
        return false
    }

    static let authKeywords: [String] = [
        "auth",
        "login",
        "api key",
        "credential",
        "401",
        "unauthorized",
        "not authenticated",
        "invalid token",
        "expired token",
        "session expired",
        "sign in",
        "oturum",
        "giriş yap",
        "yetki",
    ]
}

/// `<cli> login` komutunu Terminal.app içinde başlatır. CLI'ların login
/// akışları tarayıcı açıp callback bekler veya interaktif prompt sorar —
/// subprocess olarak headless çalıştırmak yerine kullanıcının normal
/// Terminal'inde göstermek daha sağlıklı.
enum LoginLauncher {
    /// Belirtilen CLI için login komut adı. Codex/Claude için `login`,
    /// Gemini için `auth login` (CLI'sı subcommand fark eder).
    static func loginCommand(for kind: CLIKind) -> String {
        switch kind {
        case .claude: return "claude login"
        case .codex: return "codex login"
        case .gemini: return "gemini auth login"
        }
    }

    /// "Giriş yap" butonu için kullanıcıya gösterilen kısa label.
    static func buttonLabel(for kind: CLIKind) -> String {
        "\(kind.displayName)'a Giriş Yap"
    }

    /// Terminal.app'i öne getirir ve verilen komutu yeni bir sekme/penceredе
    /// çalıştırır. Komut salt-okunur literal (`AppleScript` quote escape için
    /// yalnızca `\` ve `"` kaçırılır). Hata olursa stderr'e bir satır basılır;
    /// UI'da kullanıcı zaten "Tekrar dene" ile yumuşak fallback'e sahip.
    static func launch(for kind: CLIKind) {
        let command = loginCommand(for: kind)
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            FileHandle.standardError.write(Data(
                "[pixel-agent] LoginLauncher: AppleScript oluşturulamadı.\n".utf8
            ))
            return
        }

        var error: NSDictionary?
        _ = appleScript.executeAndReturnError(&error)
        if let error {
            FileHandle.standardError.write(Data(
                "[pixel-agent] LoginLauncher hata: \(error)\n".utf8
            ))
        }
    }
}
