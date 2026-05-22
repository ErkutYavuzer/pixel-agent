import Foundation
import PixelRemote

/// Mac tarafı LAN sunucusunu `RemoteTransport` interface'ine adapte eder.
/// Birden çok client bağlanırsa inbound stream'leri birleştirir, outbound
/// envelope'u tüm bağlı client'lara broadcast eder.
public actor LANServerTransport: RemoteTransport {
    private let service: LANService
    private var connections: [LANServerConnection] = []
    private var continuation: AsyncThrowingStream<RemoteEnvelope, any Error>.Continuation?
    private var consumerTask: Task<Void, Never>?

    public init(configuration: LANService.Configuration = .init()) {
        self.service = LANService(configuration: configuration)
    }

    public init(service: LANService) {
        self.service = service
    }

    public func connect() async throws -> AsyncThrowingStream<RemoteEnvelope, any Error> {
        let connectionStream = try await service.start()

        let envelopeStream = AsyncThrowingStream<RemoteEnvelope, any Error> { cont in
            self.continuation = cont
            cont.onTermination = { [weak self] _ in
                Task { await self?.disconnect() }
            }
        }

        consumerTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await conn in connectionStream {
                    await self.attach(connection: conn)
                }
            } catch {
                await self.finish(error: error)
            }
        }

        return envelopeStream
    }

    public func send(_ envelope: RemoteEnvelope) async throws {
        // Broadcast — bağlı tüm client'lara.
        // Bir client'a yazarken hata olursa diğerlerini etkilemesin; log + devam.
        for conn in connections {
            do {
                try await conn.send(envelope)
            } catch {
                // Faz 2: stderr log; ileride observer pattern.
                FileHandle.standardError.write(
                    Data("[LANServerTransport] send failed: \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }

    public func disconnect() async {
        consumerTask?.cancel()
        consumerTask = nil
        for conn in connections { conn.disconnect() }
        connections.removeAll()
        await service.stop()
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Internal

    private func attach(connection: LANServerConnection) {
        connections.append(connection)
        let cont = continuation
        Task { [weak self] in
            do {
                for try await env in connection.incoming {
                    cont?.yield(env)
                }
            } catch {
                cont?.yield(with: .failure(error))
            }
            await self?.detach(connection: connection)
        }
    }

    private func detach(connection: LANServerConnection) {
        connections.removeAll { $0 === connection }
    }

    private func finish(error: Error) {
        continuation?.finish(throwing: error)
        continuation = nil
    }
}
