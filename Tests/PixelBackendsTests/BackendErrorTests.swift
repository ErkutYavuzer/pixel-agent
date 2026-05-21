import XCTest

@testable import PixelBackends

final class BackendErrorTests: XCTestCase {
    func testCLINotFoundDescription() {
        let error = BackendError.cliNotFound(name: "codex")
        XCTAssertEqual(
            error.errorDescription,
            "codex CLI bulunamadı (PATH'te veya bilinen yollarda yok)."
        )
    }

    func testExitNonZeroWithStderr() {
        let error = BackendError.exitNonZero(status: 1, stderr: "bad input")
        XCTAssertEqual(error.errorDescription, "CLI çıkış kodu 1: bad input")
    }

    func testExitNonZeroWithEmptyStderr() {
        let error = BackendError.exitNonZero(status: 2, stderr: "")
        XCTAssertEqual(error.errorDescription, "CLI çıkış kodu 2")
    }

    func testNoBackendAvailableDescription() {
        let error = BackendError.noBackendAvailable
        XCTAssertEqual(
            error.errorDescription,
            "Hiçbir CLI yüklü değil. En az birini yükleyin: claude, codex veya gemini."
        )
    }

    func testProcessFailedDescription() {
        let error = BackendError.processFailed("permission denied")
        XCTAssertEqual(error.errorDescription, "Süreç başlatılamadı: permission denied")
    }
}
