import XCTest

@testable import PixelCore

final class ToolArbiterTests: XCTestCase {

    func testAcquireFreeResourceReturnsImmediately() async {
        let arbiter = ToolArbiter()
        await arbiter.acquire([.pointer])
        let locked = await arbiter.currentlyLocked()
        XCTAssertTrue(locked.contains(.pointer))
        await arbiter.release([.pointer])
        let after = await arbiter.currentlyLocked()
        XCTAssertFalse(after.contains(.pointer))
    }

    func testReleaseEmptyIsNoop() async {
        let arbiter = ToolArbiter()
        await arbiter.release([.pointer])
        let locked = await arbiter.currentlyLocked()
        XCTAssertTrue(locked.isEmpty)
    }

    func testDoubleAcquireSecondCallerBlocksUntilRelease() async {
        let arbiter = ToolArbiter()
        await arbiter.acquire([.pointer])

        let secondAcquired = expectation(description: "ikinci acquire tamamland\u{131}")
        Task {
            await arbiter.acquire([.pointer])
            secondAcquired.fulfill()
            await arbiter.release([.pointer])
        }

        // İlk release'i geciktir — ikinci task waiter olmalı
        try? await Task.sleep(nanoseconds: 50_000_000)
        let waiters = await arbiter.waiterCount()
        XCTAssertEqual(waiters, 1, "İkinci task waiter olmalı")

        await arbiter.release([.pointer])
        await fulfillment(of: [secondAcquired], timeout: 1.0)
    }

    func testDifferentResourcesCanBeAcquiredInParallel() async {
        let arbiter = ToolArbiter()
        await arbiter.acquire([.pointer])
        await arbiter.acquire([.clipboard])  // farklı kaynak — beklemesin
        let locked = await arbiter.currentlyLocked()
        XCTAssertTrue(locked.contains(.pointer))
        XCTAssertTrue(locked.contains(.clipboard))
    }

    func testWithHelperReleasesOnSuccess() async {
        let arbiter = ToolArbiter()
        let result = await arbiter.with([.pointer]) {
            "ok"
        }
        XCTAssertEqual(result, "ok")
        let locked = await arbiter.currentlyLocked()
        XCTAssertFalse(locked.contains(.pointer))
    }

    func testWithHelperReleasesOnThrow() async {
        let arbiter = ToolArbiter()
        struct Boom: Error {}
        do {
            _ = try await arbiter.with([.pointer]) {
                throw Boom()
            }
            XCTFail("Throw beklendi")
        } catch is Boom {
            // beklenen
        } catch {
            XCTFail("Beklenmeyen hata: \(error)")
        }
        let locked = await arbiter.currentlyLocked()
        XCTAssertFalse(locked.contains(.pointer), "Throw sonras\u{131} pointer release edilmeli")
    }

    func testMultiResourceAcquireAtomic() async {
        let arbiter = ToolArbiter()
        await arbiter.acquire([.pointer, .clipboard])
        let locked = await arbiter.currentlyLocked()
        XCTAssertTrue(locked.contains(.pointer))
        XCTAssertTrue(locked.contains(.clipboard))
        await arbiter.release([.pointer, .clipboard])
    }

    func testMultiResourcePartialOverlapBlocks() async {
        let arbiter = ToolArbiter()
        await arbiter.acquire([.pointer, .clipboard])

        let secondAcquired = expectation(description: "k\u{131}smen çak\u{131}\u{15f}an acquire bekledi")
        Task {
            // .clipboard tutuluyor — bu beklemeli
            await arbiter.acquire([.clipboard, .mic])
            secondAcquired.fulfill()
            await arbiter.release([.clipboard, .mic])
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        let waiters = await arbiter.waiterCount()
        XCTAssertEqual(waiters, 1)

        await arbiter.release([.pointer, .clipboard])
        await fulfillment(of: [secondAcquired], timeout: 1.0)
    }

    func testFileWriteDifferentPathsParallel() async {
        let arbiter = ToolArbiter()
        await arbiter.acquire([.fileWrite(path: "/a.txt")])
        await arbiter.acquire([.fileWrite(path: "/b.txt")])  // farkl\u{131} path — beklemesin
        let waiters = await arbiter.waiterCount()
        XCTAssertEqual(waiters, 0)
    }

    func testFileWriteSamePathSerializes() async {
        let arbiter = ToolArbiter()
        await arbiter.acquire([.fileWrite(path: "/a.txt")])

        let secondAcquired = expectation(description: "ayn\u{131} path acquire bekledi")
        Task {
            await arbiter.acquire([.fileWrite(path: "/a.txt")])
            secondAcquired.fulfill()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        let waiters = await arbiter.waiterCount()
        XCTAssertEqual(waiters, 1)

        await arbiter.release([.fileWrite(path: "/a.txt")])
        await fulfillment(of: [secondAcquired], timeout: 1.0)
    }

    func testWaitersAreServedInFIFOOrder() async {
        // Sendable-safe collector — Swift 6 strict concurrency için Task closure
        // capture'ı actor üzerinden geçer.
        actor OrderCollector {
            var values: [Int] = []
            func append(_ n: Int) { values.append(n) }
            func snapshot() -> [Int] { values }
        }

        let arbiter = ToolArbiter()
        let collector = OrderCollector()
        await arbiter.acquire([.pointer])

        let done = expectation(description: "her iki waiter da tamamland\u{131}")
        done.expectedFulfillmentCount = 2

        Task {
            await arbiter.acquire([.pointer])
            await collector.append(1)
            await arbiter.release([.pointer])
            done.fulfill()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        Task {
            await arbiter.acquire([.pointer])
            await collector.append(2)
            await arbiter.release([.pointer])
            done.fulfill()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        await arbiter.release([.pointer])
        await fulfillment(of: [done], timeout: 2.0)

        let order = await collector.snapshot()
        XCTAssertEqual(order, [1, 2])
    }

    // MARK: - Resource Comparable

    func testResourceSortOrder() {
        XCTAssertLessThan(ToolArbiter.Resource.pointer, .screen)
        XCTAssertLessThan(ToolArbiter.Resource.screen, .clipboard)
        XCTAssertLessThan(ToolArbiter.Resource.clipboard, .mic)
        XCTAssertLessThan(ToolArbiter.Resource.mic, .speaker)
        XCTAssertLessThan(ToolArbiter.Resource.speaker, .fileWrite(path: "/a"))
    }

    func testFileWritePathComparable() {
        XCTAssertLessThan(
            ToolArbiter.Resource.fileWrite(path: "/a.txt"),
            ToolArbiter.Resource.fileWrite(path: "/b.txt")
        )
    }
}
