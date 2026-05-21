import Foundation
import PixelCore

public struct AnthropicBackend: ChatBackend {
    public let modelID: String
    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession
    private let maxTokens: Int

    public init(
        apiKey: String? = nil,
        modelID: String = "claude-sonnet-4-6",
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        session: URLSession = .shared,
        maxTokens: Int = 4096
    ) throws {
        let resolvedKey = apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        guard !resolvedKey.isEmpty else {
            throw AnthropicError.missingAPIKey
        }
        self.apiKey = resolvedKey
        self.modelID = modelID
        self.endpoint = endpoint
        self.session = session
        self.maxTokens = maxTokens
    }

    public func send(
        messages: [Message],
        system: String?
    ) -> AsyncThrowingStream<StreamDelta, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(messages: messages, system: system)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AnthropicError.nonHTTPResponse
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var bodyData = Data()
                        for try await byte in bytes {
                            bodyData.append(byte)
                            if bodyData.count > 4096 { break }
                        }
                        let body = String(data: bodyData, encoding: .utf8) ?? "<binary>"
                        throw AnthropicError.httpError(status: http.statusCode, body: body)
                    }
                    for try await line in bytes.lines {
                        if let delta = SSEParser.parseDataLine(line) {
                            continuation.yield(delta)
                            if case .done = delta {
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildRequest(messages: [Message], system: String?) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let apiMessages: [[String: Any]] = messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.text] }

        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": maxTokens,
            "messages": apiMessages,
            "stream": true,
        ]
        if let system, !system.isEmpty {
            body["system"] = system
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
