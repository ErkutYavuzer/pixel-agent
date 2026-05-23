import XCTest

@testable import PixelComputerUse

final class PermissionsTests: XCTestCase {

    /// `hasAccessibility()` / `hasScreenRecording()` CI veya local dev'de
    /// kullanıcı durumuna bağlı (true veya false). API yüzeyi crash etmemeli.
    func testStatusAPIReturnsStruct() {
        let status = ComputerUsePermissions.status()
        _ = status.accessibility
        _ = status.screenRecording
        _ = status.allGranted
    }

    func testStatusCodableRoundtrip() throws {
        let status = ComputerUsePermissions.Status(accessibility: true, screenRecording: false)
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(ComputerUsePermissions.Status.self, from: data)
        XCTAssertEqual(decoded, status)
        XCTAssertFalse(decoded.allGranted)
    }

    func testAllGrantedTrueWhenBothTrue() {
        let status = ComputerUsePermissions.Status(accessibility: true, screenRecording: true)
        XCTAssertTrue(status.allGranted)
    }

    func testAllGrantedFalseWhenEitherFalse() {
        XCTAssertFalse(ComputerUsePermissions.Status(accessibility: false, screenRecording: true).allGranted)
        XCTAssertFalse(ComputerUsePermissions.Status(accessibility: true, screenRecording: false).allGranted)
        XCTAssertFalse(ComputerUsePermissions.Status(accessibility: false, screenRecording: false).allGranted)
    }

    /// `preflight()` izinler eksikse hata fırlatır. CI'da çoğunlukla izin yok.
    /// Test: çağrı crash etmesin; throws stati `ComputerUseError` ailesinden olsun.
    func testPreflightAPIDoesNotCrash() {
        do {
            try ComputerUsePermissions.preflight()
            // İzinler verilmişse hata fırlatmadan döner — OK.
        } catch is ComputerUseError {
            // İzin yok — beklenen.
        } catch {
            XCTFail("Beklenmeyen hata tipi: \(error)")
        }
    }
}
