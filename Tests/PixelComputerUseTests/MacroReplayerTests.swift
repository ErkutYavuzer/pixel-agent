import XCTest

@testable import PixelComputerUse

/// Sadece **execution öncesi** guard path'leri (validate + plan-mode) — bunlar
/// AX'a dokunmadan döner, hermetic. Gerçek step execution (re-resolve/click)
/// AX gerektirir → entegrasyon/manuel test.
final class MacroReplayerTests: XCTestCase {
    private func makeReplayer() -> MacroReplayer {
        MacroReplayer(computer: PixelComputerUse(policy: .bypass))
    }

    private let click = MacroStep.click(query: nil, opaqueID: "x", count: 1, modifiers: [])
    private let wait = MacroStep.wait(milliseconds: 1)

    func testEmptyRecordingThrows() async {
        do {
            _ = try await makeReplayer().replay([])
            XCTFail("boş kayıt hata vermeli")
        } catch let error as MacroReplayError {
            XCTAssertEqual(error, .emptyRecording)
        } catch {
            XCTFail("beklenmeyen hata: \(error)")
        }
    }

    func testTooManyStepsThrows() async {
        let steps = Array(repeating: wait, count: 5)
        do {
            _ = try await makeReplayer().replay(steps, options: MacroReplayOptions(maxSteps: 3))
            XCTFail("cap aşımı hata vermeli")
        } catch let error as MacroReplayError {
            XCTAssertEqual(error, .tooManySteps(count: 5, max: 3))
        } catch {
            XCTFail("beklenmeyen hata: \(error)")
        }
    }

    func testPlanModeBlockedThrows() async {
        let opts = MacroReplayOptions(allowDestructive: false)
        do {
            _ = try await makeReplayer().replay([click], options: opts)
            XCTFail("destructive + !allow bloklanmalı")
        } catch let error as MacroReplayError {
            XCTAssertEqual(error, .planModeBlocked)
        } catch {
            XCTFail("beklenmeyen hata: \(error)")
        }
    }
}
