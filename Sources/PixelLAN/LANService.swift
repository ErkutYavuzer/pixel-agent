import Foundation
import Network
import PixelRemote

/// Mac tarafı LAN sunucusu: NWListener + Bonjour advertise + newline-delimited
/// envelope kabul/yayım. Her bağlantı `AsyncThrowingStream<RemoteEnvelope>` üzerinden
/// kullanıcıya iletilir.
///
/// Kullanım:
/// ```swift
/// let service = LANService(publicKeyBase64: hostPubKey)
/// for try await connection in await service.start(port: 0) {
///     Task {
///         for try await envelope in connection.incoming {
///             // process
///         }
///     }
/// }
/// ```
public actor LANService {
    public struct Configuration: Sendable {
        public var serviceName: String?
        public var port: UInt16
        public var publicKeyBase64: String?
        public var protocolVersionTXT: String?

        public init(
            serviceName: String? = nil,
            port: UInt16 = LANServiceType.defaultPort,
            publicKeyBase64: String? = nil,
            protocolVersionTXT: String? = nil
        ) {
            self.serviceName = serviceName
            self.port = port
            self.publicKeyBase64 = publicKeyBase64
            self.protocolVersionTXT = protocolVersionTXT
        }
    }

    public enum ServiceError: Error, LocalizedError {
        case alreadyStarted
        case listenerFailed(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyStarted: return "LANService zaten çalışıyor."
            case .listenerFailed(let s): return "NWListener başarısız: \(s)"
            }
        }
    }

    private var listener: NWListener?
    private let configuration: Configuration
    private let queue = DispatchQueue(label: "dev.erkutyavuzer.pixel-agent.lan-service", qos: .userInitiated)

    private var connectionContinuation: AsyncThrowingStream<LANServerConnection, Error>.Continuation?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Listener'ı başlatır ve Bonjour'a kayıt yapar. Dönüş: yeni gelen client
    /// bağlantılarının stream'i.
    public func start() async throws -> AsyncThrowingStream<LANServerConnection, Error> {
        guard listener == nil else { throw ServiceError.alreadyStarted }

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        do {
            let port = configuration.port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: configuration.port) ?? .any
            let newListener = try NWListener(using: params, on: port)
            // Bonjour advertise — name yoksa cihaz adı kullanılır.
            // Faz 1'de TXT record (pk + protokol versiyonu) yok; Faz 2'de eklenecek
            // (NWTXTRecord init macOS sürümü ile değişkenlik gösteriyor; basit tutuyoruz).
            newListener.service = NWListener.Service(
                name: configuration.serviceName,
                type: LANServiceType.bonjour,
                domain: LANServiceType.domain
            )

            let stream = AsyncThrowingStream<LANServerConnection, Error> { continuation in
                self.connectionContinuation = continuation
                continuation.onTermination = { [weak self] _ in
                    Task { await self?.stop() }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task { await self.acceptIncoming(connection: connection) }
            }

            newListener.stateUpdateHandler = { [weak self] state in
                if case .failed(let err) = state {
                    Task { await self?.fail(error: err) }
                }
            }

            newListener.start(queue: queue)
            self.listener = newListener
            return stream
        } catch {
            throw ServiceError.listenerFailed(error.localizedDescription)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        connectionContinuation?.finish()
        connectionContinuation = nil
    }

    public var listenerPort: UInt16? {
        listener?.port?.rawValue
    }

    // MARK: - Helpers

    private func acceptIncoming(connection: NWConnection) {
        let wrapped = LANServerConnection(connection: connection, queue: queue)
        connection.start(queue: queue)
        connectionContinuation?.yield(wrapped)
    }

    private func fail(error: Error) {
        connectionContinuation?.finish(throwing: error)
        connectionContinuation = nil
        listener = nil
    }

    // TXT record şu an pasif — Faz 2'de NWTXTRecord init'i platform/Swift sürümü
    // değişkenliğini doğru handle ederek tekrar açılacak.
}

/// Server tarafında accept edilen bir client bağlantısı.
/// Inbound stream + outbound `send(_:)` API'si.
public final class LANServerConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var leftoverBuffer = Data()

    public let incoming: AsyncThrowingStream<RemoteEnvelope, Error>
    private let incomingContinuation: AsyncThrowingStream<RemoteEnvelope, Error>.Continuation

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
        var captured: AsyncThrowingStream<RemoteEnvelope, Error>.Continuation!
        self.incoming = AsyncThrowingStream { continuation in
            captured = continuation
            continuation.onTermination = { _ in
                connection.cancel()
            }
        }
        self.incomingContinuation = captured
        receiveLoop()
    }

    public func send(_ envelope: RemoteEnvelope) async throws {
        let data = try LANFraming.encode(envelope)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    public func disconnect() {
        incomingContinuation.finish()
        connection.cancel()
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.incomingContinuation.finish(throwing: error)
                return
            }
            if let data, !data.isEmpty {
                self.leftoverBuffer.append(data)
                do {
                    let (envelopes, leftover) = try LANFraming.decode(buffer: self.leftoverBuffer)
                    self.leftoverBuffer = leftover
                    for env in envelopes {
                        self.incomingContinuation.yield(env)
                    }
                } catch {
                    self.incomingContinuation.finish(throwing: error)
                    return
                }
            }
            if isComplete {
                self.incomingContinuation.finish()
                return
            }
            self.receiveLoop()
        }
    }
}
