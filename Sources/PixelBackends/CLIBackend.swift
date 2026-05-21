import Foundation
import PixelCore

public struct CLIBackend: ChatBackend {
    public let kind: CLIKind
    public let modelID: String
    public let executablePath: String

    public init(kind: CLIKind, executablePath: String, modelID: String? = nil) {
        self.kind = kind
        self.executablePath = executablePath
        self.modelID = modelID ?? "\(kind.rawValue)-cli"
    }

    public init(kind: CLIKind, detector: CLIDetector = CLIDetector()) throws {
        guard let path = detector.locate(kind) else {
            throw BackendError.cliNotFound(name: kind.executableName)
        }
        self.init(kind: kind, executablePath: path)
    }

    public func send(
        messages: [Message],
        system: String?
    ) -> AsyncThrowingStream<StreamDelta, any Error> {
        let prompt = Self.composedPrompt(messages: messages, system: system)
        let runner = CLIProcessRunner(
            executablePath: executablePath,
            arguments: Self.arguments(for: kind, prompt: prompt)
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var emittedAny = false
                    for try await line in runner.runStreamingLines() {
                        if Task.isCancelled { break }
                        continuation.yield(.textChunk(emittedAny ? "\n\(line)" : line))
                        emittedAny = true
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func arguments(for kind: CLIKind, prompt: String) -> [String] {
        switch kind {
        case .claude, .codex, .gemini:
            return ["-p", prompt]
        }
    }

    private static func composedPrompt(messages: [Message], system: String?) -> String {
        var parts: [String] = []
        if let system, !system.isEmpty {
            parts.append("System: \(system)")
        }
        for msg in messages {
            let label: String
            switch msg.role {
            case .system: label = "System"
            case .user: label = "User"
            case .assistant: label = "Assistant"
            }
            parts.append("\(label): \(msg.text)")
        }
        return parts.joined(separator: "\n\n")
    }
}
