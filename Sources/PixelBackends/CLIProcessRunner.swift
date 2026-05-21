import Foundation

public struct CLIProcessRunner: Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]?
    public let workingDirectory: URL?

    public init(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    public func runStreamingLines(stdin: String? = nil) -> AsyncThrowingStream<String, any Error> {
        let executablePath = self.executablePath
        let arguments = self.arguments
        let environment = self.environment
        let workingDirectory = self.workingDirectory

        return AsyncThrowingStream { continuation in
            let runTask = Task {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                if let environment {
                    process.environment = environment
                }
                if let workingDirectory {
                    process.currentDirectoryURL = workingDirectory
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                if stdin != nil {
                    process.standardInput = Pipe()
                }

                do {
                    try process.run()
                } catch {
                    continuation.finish(
                        throwing: BackendError.processFailed(error.localizedDescription)
                    )
                    return
                }

                if let stdin, let stdinPipe = process.standardInput as? Pipe {
                    if let data = stdin.data(using: .utf8) {
                        try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
                    }
                    try? stdinPipe.fileHandleForWriting.close()
                }

                do {
                    for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                        if Task.isCancelled {
                            process.terminate()
                            break
                        }
                        continuation.yield(line)
                    }
                } catch {
                    if process.isRunning { process.terminate() }
                    continuation.finish(throwing: error)
                    return
                }

                process.waitUntilExit()
                let exitCode = process.terminationStatus

                if exitCode != 0 {
                    let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.finish(
                        throwing: BackendError.exitNonZero(status: exitCode, stderr: stderrString)
                    )
                } else {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in runTask.cancel() }
        }
    }
}
