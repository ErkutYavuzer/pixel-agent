import XCTest
import PixelBackends

@testable import PixelMacApp

final class AuthErrorDetectorTests: XCTestCase {

    // MARK: - isAuthError

    func testEnglishCLIAuthMessagesDetected() {
        XCTAssertTrue(AuthErrorDetector.isAuthError("Error: 401 Unauthorized"))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Please sign in to continue"))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Invalid API key provided."))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Authentication required"))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Run `claude login` to authenticate"))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Session expired"))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Invalid token"))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Expired credential"))
    }

    func testTurkishMessagesDetected() {
        // Bizim 60s timeout watchdog'umuz Türkçe "auth/quota kontrol et" der —
        // bunu da yakalamalıyız (test'lerde "auth" substring zaten yakalar).
        XCTAssertTrue(AuthErrorDetector.isAuthError(
            "Backend 60 saniyede yanıt vermedi. CLI auth/quota kontrol et."
        ))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Oturum süreniz doldu"))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Lütfen giriş yapın"))
        XCTAssertTrue(AuthErrorDetector.isAuthError("Yetki hatası"))
    }

    func testNonAuthMessagesNotDetected() {
        XCTAssertFalse(AuthErrorDetector.isAuthError("Network connection failed"))
        XCTAssertFalse(AuthErrorDetector.isAuthError("Process exited with code 1"))
        XCTAssertFalse(AuthErrorDetector.isAuthError("File not found"))
        XCTAssertFalse(AuthErrorDetector.isAuthError(""))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(AuthErrorDetector.isAuthError("UNAUTHORIZED"))
        XCTAssertTrue(AuthErrorDetector.isAuthError("UnAuthOriZed"))
    }

    // MARK: - LoginLauncher.loginCommand

    func testLoginCommandPerBackend() {
        XCTAssertEqual(LoginLauncher.loginCommand(for: .claude), "claude login")
        XCTAssertEqual(LoginLauncher.loginCommand(for: .codex), "codex login")
        // Gemini CLI subcommand farklı.
        XCTAssertEqual(LoginLauncher.loginCommand(for: .gemini), "gemini auth login")
    }

    func testButtonLabelPerBackend() {
        XCTAssertEqual(LoginLauncher.buttonLabel(for: .claude), "Claude'a Giriş Yap")
        XCTAssertEqual(LoginLauncher.buttonLabel(for: .codex), "Codex'a Giriş Yap")
        XCTAssertEqual(LoginLauncher.buttonLabel(for: .gemini), "Gemini'a Giriş Yap")
    }

    // MARK: - Keyword roster

    func testAuthKeywordsAreLowercased() {
        for keyword in AuthErrorDetector.authKeywords {
            XCTAssertEqual(keyword, keyword.lowercased(),
                           "Keyword '\(keyword)' lowercased değil — case-insensitive match bozulur")
        }
    }

    func testAuthKeywordsCoverDemoScenario() {
        // Demo senaryosunun açıkça bahsettiği "Authentication exparit olursa…"
        // akışı tetiklenmeli.
        XCTAssertTrue(AuthErrorDetector.isAuthError("Authentication expired"))
    }
}
