import XCTest
import PixelRemote
@testable import PixelLAN

/// Test-only stub: controllable connect/send + yieldable inbound.
private actor StubTransport: RemoteTransport {
    enum Behavior {
        case succeed
        case failConnect
        case failSend
    }

    let behavior: Behavior
    var connectCount = 0
    var sendCount = 0
    var disconnectCount = 0
    private var continuation: AsyncThrowingStream<RemoteEnvelope, any Error>.Continuation?

    init(behavior: Behavior = .succeed) {
        self.behavior = behavior
    }

    func connect() async throws -> AsyncThrowingStream<RemoteEnvelope, any Error> {
        connectCount += 1
        if behavior == .failConnect {
            throw NSError(domain: "Stub", code: 1, userInfo: [NSLocalizedDescriptionKey: "stub connect fail"])
        }
        return AsyncThrowingStream { cont in
            self.continuation = cont
        }
    }

    func send(_ envelope: RemoteEnvelope) async throws {
        sendCount += 1
        if behavior == .failSend {
            throw NSError(domain: "Stub", code: 2, userInfo: [NSLocalizedDescriptionKey: "stub send fail"])
        }
    }

    func disconnect() async {
        disconnectCount += 1
        continuation?.finish()
    }

    /// Test-only: dışarıdan envelope yay.
    func yieldFromStub(_ envelope: RemoteEnvelope) {
        continuation?.yield(envelope)
    }

    func counts() -> (connect: Int, send: Int, disconnect: Int) {
        (connectCount, sendCount, disconnectCount)
    }
}

final class MergeTransportTests: XCTestCase {
    func testConnectStartsAllChildren() async throws {
        let a = StubTransport()
        let b = StubTransport()
        let merge = MergeTransport(transports: [a, b])

        _ = try await merge.connect()
        let live = await merge.liveTransportCount
        XCTAssertEqual(live, 2)

        let aCounts = await a.counts()
        let bCounts = await b.counts()
        XCTAssertEqual(aCounts.connect, 1)
        XCTAssertEqual(bCounts.connect, 1)
    }

    func testPartialConnectFailureKeepsRemainingActive() async throws {
        let good = StubTransport(behavior: .succeed)
        let bad = StubTransport(behavior: .failConnect)
        let merge = MergeTransport(transports: [bad, good])

        _ = try await merge.connect()
        let live = await merge.liveTransportCount
        XCTAssertEqual(live, 1)  // bad atlandı, good aktif
    }

    func testAllConnectFailuresThrows() async {
        let bad1 = StubTransport(behavior: .failConnect)
        let bad2 = StubTransport(behavior: .failConnect)
        let merge = MergeTransport(transports: [bad1, bad2])

        do {
            _ = try await merge.connect()
            XCTFail("Should throw allTransportsFailed")
        } catch let error as MergeTransport.MergeError {
            XCTAssertEqual(error, .allTransportsFailed)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testSendBroadcastsToAllLiveTransports() async throws {
        let a = StubTransport()
        let b = StubTransport()
        let merge = MergeTransport(transports: [a, b])

        _ = try await merge.connect()
        try await merge.send(RemoteEnvelope.ping())

        let aCounts = await a.counts()
        let bCounts = await b.counts()
        XCTAssertEqual(aCounts.send, 1)
        XCTAssertEqual(bCounts.send, 1)
    }

    func testSendSucceedsIfAtLeastOneTransportSucceeds() async throws {
        let good = StubTransport(behavior: .succeed)
        let bad = StubTransport(behavior: .failSend)
        let merge = MergeTransport(transports: [good, bad])

        _ = try await merge.connect()
        // En az biri başarılıysa send throw'lamaz.
        try await merge.send(RemoteEnvelope.ping())

        let goodCounts = await good.counts()
        let badCounts = await bad.counts()
        XCTAssertEqual(goodCounts.send, 1)
        XCTAssertEqual(badCounts.send, 1)
    }

    func testSendThrowsIfAllTransportsFail() async throws {
        let bad1 = StubTransport(behavior: .failSend)
        let bad2 = StubTransport(behavior: .failSend)
        let merge = MergeTransport(transports: [bad1, bad2])

        _ = try await merge.connect()
        do {
            try await merge.send(RemoteEnvelope.ping())
            XCTFail("Should throw when all sends fail")
        } catch {
            // Beklenen
        }
    }

    func testSendBeforeConnectThrows() async {
        let a = StubTransport()
        let merge = MergeTransport(transports: [a])

        do {
            try await merge.send(RemoteEnvelope.ping())
            XCTFail("Should throw noActiveTransports")
        } catch let error as MergeTransport.MergeError {
            XCTAssertEqual(error, .noActiveTransports)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testDisconnectCascadesToAllChildren() async throws {
        let a = StubTransport()
        let b = StubTransport()
        let merge = MergeTransport(transports: [a, b])

        _ = try await merge.connect()
        await merge.disconnect()

        let aCounts = await a.counts()
        let bCounts = await b.counts()
        XCTAssertEqual(aCounts.disconnect, 1)
        XCTAssertEqual(bCounts.disconnect, 1)

        let live = await merge.liveTransportCount
        XCTAssertEqual(live, 0)
    }

    func testMergedStreamReceivesFromAllSources() async throws {
        let a = StubTransport()
        let b = StubTransport()
        let merge = MergeTransport(transports: [a, b])

        let stream = try await merge.connect()

        // Her stub'dan farklı envelope yay
        await a.yieldFromStub(RemoteEnvelope.userMessage(text: "from-a"))
        await b.yieldFromStub(RemoteEnvelope.userMessage(text: "from-b"))

        let collector = Collector()
        let collectTask = Task<Void, Never> { [stream] in
            var count = 0
            do {
                for try await env in stream {
                    if let text = env.payload?.text {
                        await collector.append(text)
                        count += 1
                        if count == 2 { break }
                    }
                }
            } catch {
                // stream throw → toplama biter, test assertion'ı zaten ne topladıysa onu doğrular
            }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        collectTask.cancel()
        _ = await collectTask.value

        let collected = await collector.values()
        XCTAssertEqual(Set(collected), Set(["from-a", "from-b"]))
    }
}

private actor Collector {
    private var items: [String] = []
    func append(_ s: String) { items.append(s) }
    func values() -> [String] { items }
}
