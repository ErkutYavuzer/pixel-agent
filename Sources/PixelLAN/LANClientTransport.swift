import Foundation
import PixelRemote

/// iOS / Mac istemcisi: Bonjour browse + ilk bulunan host'a bağlan.
/// `RemoteTransport` interface'i için `connect()` discovery + connection'ı birleştirir.
public actor LANClientTransport: RemoteTransport {
    private let client: LANClient
    private let discoveryTimeout: TimeInterval

    public init(discoveryTimeout: TimeInterval = 2.0) {
        self.client = LANClient()
        self.discoveryTimeout = discoveryTimeout
    }

    public init(client: LANClient, discoveryTimeout: TimeInterval = 2.0) {
        self.client = client
        self.discoveryTimeout = discoveryTimeout
    }

    public func connect() async throws -> AsyncThrowingStream<RemoteEnvelope, any Error> {
        let host = try await discoverFirstHost()
        return try await client.connect(to: host)
    }

    public func send(_ envelope: RemoteEnvelope) async throws {
        try await client.send(envelope)
    }

    public func disconnect() async {
        await client.disconnect()
        await client.stopBrowsing()
    }

    // MARK: - Discovery

    private func discoverFirstHost() async throws -> LANClient.DiscoveredHost {
        let browseStream = await client.browse()
        let timeout = discoveryTimeout

        return try await withThrowingTaskGroup(of: LANClient.DiscoveredHost?.self) { group in
            // Browse consumer
            group.addTask {
                for await hosts in browseStream {
                    if let first = hosts.first { return first }
                }
                return nil
            }
            // Timeout
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                return nil
            }

            let outcome = try await group.next() ?? nil
            group.cancelAll()
            await client.stopBrowsing()

            guard let host = outcome else {
                throw LANClient.ClientError.connectionFailed(
                    "Bonjour discovery timeout (\(timeout)s)"
                )
            }
            return host
        }
    }
}
