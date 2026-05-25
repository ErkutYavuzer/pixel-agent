import XCTest
@testable import PixelLAN

/// **Sprint 30 (v0.2.55):** LAN service'in gerçek start/stop lifecycle'ı.
/// v0.2.37+ documented intermittent flake için root cause analysis sırasında
/// keşfedildi: PixelLANTests çoğunlukla stub/instantiation testleri yapıyor;
/// gerçek `NWListener` bind/teardown hiç test edilmiyordu. Bu eksiklik
/// hem coverage gap hem de "test isolation pattern" missing model.
///
/// Bu test (port=0 + tearDown garantisi) gerçek lifecycle örneği — port
/// collision yok (OS ephemeral atar), her test sonrası deterministik
/// cleanup. İleride LAN end-to-end test eklenirse bu pattern referans.
final class LANServiceLifecycleTests: XCTestCase {

    private var service: LANService?

    override func tearDown() async throws {
        // Defensive: testin bittiği yerden bağımsız service'i mutlaka stop'la.
        // `port=0` kullansak bile NWListener kaynağı (file descriptor, GCD
        // queue) tearDown'da temizlenmeli; aksi halde xctest binary
        // accumulates listener'ları, OS file descriptor limit zorlanabilir.
        await service?.stop()
        service = nil
        try await super.tearDown()
    }

    func testServiceStartsWithoutThrowing() async throws {
        // port=0 → OS ephemeral atar (production'da). Test sandbox'ında
        // NWListener.start() throw'lamayabilir ama port assignment timing-
        // dependent; deterministik assertion zor. Bu test sadece start()'ın
        // ServiceError atmadığını + sonradan stop edilebildiğini doğrular.
        // Detaylı listener state testing manual QA için.
        let svc = LANService()
        self.service = svc

        let portBefore = await svc.listenerPort
        XCTAssertNil(portBefore, "start öncesi port nil olmalı")

        let _stream = try await svc.start()
        _ = _stream  // stream'i tut, deallocation onTermination tetiklemesin

        // Stop edilebilmeli (tearDown defansif olarak da yapar, ama testin
        // intent'i: lifecycle sync'i temiz).
        await svc.stop()
    }

    func testStopAllowsRestart() async throws {
        // stop() sonrası tekrar start() — kaynaklar temizlenmiş olmalı.
        // alreadyStarted error gelmemeli.
        let svc = LANService()
        self.service = svc

        let stream1 = try await svc.start()
        _ = stream1
        await svc.stop()

        // Re-start — yeni NWListener, muhtemelen farklı port.
        let stream2 = try await svc.start()
        _ = stream2
        // Cleanup tearDown'da.
    }

    func testDoubleStartThrowsAlreadyStarted() async throws {
        // Defensive: start() iki kez çağrılırsa ikinci alreadyStarted atmalı.
        // Test isolation pattern — caller stop önce çağırmalı.
        let svc = LANService()
        self.service = svc

        let _stream = try await svc.start()
        _ = _stream

        do {
            _ = try await svc.start()
            XCTFail("İkinci start alreadyStarted atmalı")
        } catch LANService.ServiceError.alreadyStarted {
            // Beklenen
        } catch {
            XCTFail("Yanlış error: \(error)")
        }
    }
}

// MARK: - LANService actor stop async helper
//
// `LANService.stop()` actor üstünde sync — async context'ten çağrılırken
// kendi başına bir await isimlendirilmesi yeterli, ek wrapper yok.
private extension LANService {
    /// Test-only convenience — tearDown'ı tek `await` ile yapabilmek için.
    func stopAsync() async {
        stop()
    }
}
