import XCTest

@testable import PixelComputerUse

/// Façade-level smoke tests. AX'a gerçek erişim CI'da yok (frontmost app yok,
/// izin yok) — `.bypass` policy ile permission check geçer ama sonraki AX
/// çağrıları frontmost app yokluğunda boş array döner. Bu beklenen davranış.
final class PixelComputerUseFacadeTests: XCTestCase {

    func testInitBypassPolicy() async {
        let computer = PixelComputerUse(policy: .bypass)
        _ = computer  // sadece init crash etmemeli
    }

    func testVersionIsSet() {
        XCTAssertFalse(PixelComputerUse.version.isEmpty)
    }

    /// Bypass policy ile query çağrısı; frontmost app yoksa boş array döner.
    /// `.live` policy'de izin yoksa accessibilityNotAuthorized fırlatır.
    func testQueryWithBypassPolicyDoesNotThrowOnPermission() async {
        let computer = PixelComputerUse(policy: .bypass)
        let query = UIQuery(role: .button, title: "NonexistentBtn_12345", timeout: 0.5)
        do {
            let result = try await computer.query(query)
            // Boş array veya CI environment'a göre içerik. Sadece crash olmamalı.
            _ = result
        } catch let error as ComputerUseError {
            switch error {
            case .timedOut, .unsupported:
                // Geçerli sonuçlar.
                break
            default:
                XCTFail("Beklenmeyen ComputerUseError: \(error)")
            }
        } catch {
            XCTFail("Beklenmeyen hata: \(error)")
        }
    }
}
