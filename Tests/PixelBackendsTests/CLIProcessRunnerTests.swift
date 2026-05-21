import XCTest

@testable import PixelBackends

final class CLIProcessRunnerTests: XCTestCase {
    func testEchoStreamsSingleLine() async throws {
        let runner = CLIProcessRunner(
            executablePath: "/bin/echo",
            arguments: ["hello world"]
        )
        var collected: [String] = []
        for try await line in runner.runStreamingLines() {
            collected.append(line)
        }
        XCTAssertEqual(collected, ["hello world"])
    }

    func testPrintfStreamsMultipleLines() async throws {
        let runner = CLIProcessRunner(
            executablePath: "/usr/bin/printf",
            arguments: ["line1\nline2\nline3\n"]
        )
        var collected: [String] = []
        for try await line in runner.runStreamingLines() {
            collected.append(line)
        }
        XCTAssertEqual(collected, ["line1", "line2", "line3"])
    }

    func testNonZeroExitThrows() async {
        let runner = CLIProcessRunner(
            executablePath: "/bin/sh",
            arguments: ["-c", "exit 7"]
        )
        do {
            for try await _ in runner.runStreamingLines() {}
            XCTFail("Expected BackendError.exitNonZero")
        } catch let error as BackendError {
            if case .exitNonZero(let status, _) = error {
                XCTAssertEqual(status, 7)
            } else {
                XCTFail("Expected exitNonZero, got \(error)")
            }
        } catch {
            XCTFail("Expected BackendError, got \(error)")
        }
    }

    func testNonexistentExecutableThrows() async {
        let runner = CLIProcessRunner(
            executablePath: "/nonexistent/path/binary",
            arguments: []
        )
        do {
            for try await _ in runner.runStreamingLines() {}
            XCTFail("Expected BackendError.processFailed")
        } catch let error as BackendError {
            if case .processFailed = error {
                // expected
            } else {
                XCTFail("Expected processFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected BackendError, got \(error)")
        }
    }

    func testStdinPassedToProcess() async throws {
        let runner = CLIProcessRunner(
            executablePath: "/bin/cat",
            arguments: []
        )
        var collected: [String] = []
        for try await line in runner.runStreamingLines(stdin: "merhaba\ndünya\n") {
            collected.append(line)
        }
        XCTAssertEqual(collected, ["merhaba", "dünya"])
    }
}
