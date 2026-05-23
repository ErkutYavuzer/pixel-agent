import XCTest

@testable import PixelMacApp

final class RemoteConfigToastTests: XCTestCase {

    // MARK: - No-change cases

    func testNoChangeReturnsNil() {
        let result = RemoteConfigToastBuilder.buildMessage(
            oldBackend: "claude", oldModel: "opus", oldPlanMode: false,
            newBackend: "claude", newModel: "opus", newPlanMode: false
        )
        XCTAssertNil(result)
    }

    func testEmptyNewModelIsIgnored() {
        // iOS bazen sadece backend gönderir, model alanı boş kalır — bunu
        // "model değişti" gibi yorumlama.
        let result = RemoteConfigToastBuilder.buildMessage(
            oldBackend: "claude", oldModel: "opus", oldPlanMode: false,
            newBackend: "claude", newModel: "", newPlanMode: false
        )
        XCTAssertNil(result)
    }

    // MARK: - Single change

    func testBackendChangeProducesDisplayNameMessage() {
        let result = RemoteConfigToastBuilder.buildMessage(
            oldBackend: "claude", oldModel: "opus", oldPlanMode: false,
            newBackend: "codex", newModel: "opus", newPlanMode: false
        )
        // CLIKind.codex.displayName == "Codex"
        XCTAssertEqual(result, "📱 Telefon: Codex'e geçildi")
    }

    func testModelChangeOnlyProducesModelMessage() {
        let result = RemoteConfigToastBuilder.buildMessage(
            oldBackend: "claude", oldModel: "opus", oldPlanMode: false,
            newBackend: "claude", newModel: "sonnet", newPlanMode: false
        )
        XCTAssertEqual(result, "📱 Telefon: model: sonnet")
    }

    func testPlanModeOn() {
        let result = RemoteConfigToastBuilder.buildMessage(
            oldBackend: "claude", oldModel: "opus", oldPlanMode: false,
            newBackend: "claude", newModel: "opus", newPlanMode: true
        )
        XCTAssertEqual(result, "📱 Telefon: plan modu açıldı")
    }

    func testPlanModeOff() {
        let result = RemoteConfigToastBuilder.buildMessage(
            oldBackend: "claude", oldModel: "opus", oldPlanMode: true,
            newBackend: "claude", newModel: "opus", newPlanMode: false
        )
        XCTAssertEqual(result, "📱 Telefon: plan modu kapatıldı")
    }

    // MARK: - Combined changes

    func testBackendAndPlanModeChangeCombinedOrder() {
        // Sıralama: backend → model → plan; ayraç " · ".
        let result = RemoteConfigToastBuilder.buildMessage(
            oldBackend: "claude", oldModel: "opus", oldPlanMode: false,
            newBackend: "codex", newModel: "opus", newPlanMode: true
        )
        XCTAssertEqual(result, "📱 Telefon: Codex'e geçildi · plan modu açıldı")
    }

    func testAllThreeFieldsChange() {
        let result = RemoteConfigToastBuilder.buildMessage(
            oldBackend: "claude", oldModel: "opus", oldPlanMode: false,
            newBackend: "gemini", newModel: "gemini-2.5-flash", newPlanMode: true
        )
        XCTAssertEqual(
            result,
            "📱 Telefon: Gemini'e geçildi · model: gemini-2.5-flash · plan modu açıldı"
        )
    }

    // MARK: - Unknown backend

    func testUnknownBackendFallsBackToCapitalized() {
        // Forward-compat: yeni bir CLIKind eklenirse mevcut Mac build'i raw'ı
        // capitalize edip gösterir, crash etmez.
        let result = RemoteConfigToastBuilder.buildMessage(
            oldBackend: "claude", oldModel: "opus", oldPlanMode: false,
            newBackend: "qwen", newModel: "opus", newPlanMode: false
        )
        XCTAssertEqual(result, "📱 Telefon: Qwen'e geçildi")
    }

    // MARK: - RemoteConfigToast Identifiable

    func testEachToastHasUniqueID() {
        let a = RemoteConfigToast(message: "x")
        let b = RemoteConfigToast(message: "x")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a, b)
    }

    func testToastEqualityRequiresSameIDAndMessage() {
        let id = UUID()
        let a = RemoteConfigToast(message: "x", id: id)
        let b = RemoteConfigToast(message: "x", id: id)
        XCTAssertEqual(a, b)
    }
}
