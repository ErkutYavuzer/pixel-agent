import Foundation
import PixelRemote

/// Birden çok transport'u **paralel** çalıştıran composite. `FallbackTransport`
/// sequential ("primary fail → fallback") iken `MergeTransport` simultane:
/// hepsi `connect()` edilir, her birinin inbound stream'i tek bir merged
/// stream'de birleşir; `send(_:)` tüm child'lara broadcast olur.
///
/// Mac kullanımı (LAN advertise + relay her ikisi de iPhone bekler):
/// ```swift
/// MergeTransport(transports: [
///     LANServerTransport(configuration: .init(publicKeyBase64: pk)),
///     RelayTransport(relayURL: url, pairingCode: code, role: .mac),
/// ])
/// ```
///
/// Bir transport `connect()`'te throws ise diğerleri devam eder; tümü
/// başarısız olursa `MergeError.allTransportsFailed` fırlar.
public actor MergeTransport: RemoteTransport {
    public enum MergeError: Error, LocalizedError {
        case allTransportsFailed
        case noActiveTransports

        public var errorDescription: String? {
            switch self {
            case .allTransportsFailed: return "Tüm transport'lar başlatılamadı."
            case .noActiveTransports: return "Aktif transport yok; önce connect()."
            }
        }
    }

    private let transports: [any RemoteTransport]
    private var liveTransports: [any RemoteTransport] = []
    private var consumerTasks: [Task<Void, Never>] = []
    private var continuation: AsyncThrowingStream<RemoteEnvelope, any Error>.Continuation?
    private var isDisconnecting = false

    public init(transports: [any RemoteTransport]) {
        self.transports = transports
    }

    public func connect() async throws -> AsyncThrowingStream<RemoteEnvelope, any Error> {
        let merged = AsyncThrowingStream<RemoteEnvelope, any Error> { cont in
            self.continuation = cont
            cont.onTermination = { [weak self] _ in
                Task { await self?.disconnect() }
            }
        }

        for transport in transports {
            do {
                let stream = try await transport.connect()
                liveTransports.append(transport)
                let sourceLabel = "\(type(of: transport))"
                let task: Task<Void, Never> = Task { [weak self] in
                    guard let self else { return }
                    await self.consume(stream: stream, sourceLabel: sourceLabel)
                }
                consumerTasks.append(task)
            } catch {
                FileHandle.standardError.write(
                    Data("[MergeTransport] \(type(of: transport)) connect failed: \(error.localizedDescription)\n".utf8)
                )
            }
        }

        guard !liveTransports.isEmpty else {
            continuation?.finish()
            continuation = nil
            throw MergeError.allTransportsFailed
        }
        return merged
    }

    public func send(_ envelope: RemoteEnvelope) async throws {
        guard !liveTransports.isEmpty else {
            throw MergeError.noActiveTransports
        }
        // Broadcast — bir transport'un hatası diğerlerini etkilemesin.
        // En az birine gönderildiyse "success" kabul et.
        var deliveredCount = 0
        var lastError: Error?
        for transport in liveTransports {
            do {
                try await transport.send(envelope)
                deliveredCount += 1
            } catch {
                lastError = error
            }
        }
        if deliveredCount == 0, let error = lastError {
            throw error
        }
    }

    public func disconnect() async {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        for task in consumerTasks { task.cancel() }
        consumerTasks.removeAll()
        let toDisconnect = liveTransports
        liveTransports.removeAll()
        for transport in toDisconnect {
            await transport.disconnect()
        }
        continuation?.finish()
        continuation = nil
        isDisconnecting = false
    }

    /// Bağlı transport sayısı — debug/observer için.
    public var liveTransportCount: Int { liveTransports.count }

    // MARK: - Private

    private func consume(
        stream: AsyncThrowingStream<RemoteEnvelope, any Error>,
        sourceLabel: String
    ) async {
        do {
            for try await env in stream {
                continuation?.yield(env)
            }
        } catch {
            // Tek child stream başarısız → merge stream'i FİNISH ETMEZ.
            // Diğer transport'lar hâlâ envelope üretebilir.
            FileHandle.standardError.write(
                Data("[MergeTransport] \(sourceLabel) stream ended with error: \(error.localizedDescription)\n".utf8)
            )
        }
    }
}
