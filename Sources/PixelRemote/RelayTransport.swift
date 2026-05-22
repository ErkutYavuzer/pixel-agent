import Foundation

/// `RelayClient`'ı `RemoteTransport` interface'ine adapte eder. Davranış birebir aynı;
/// sadece yapılandırma (relayURL + pairingCode + role) construction time'da bağlanır.
public actor RelayTransport: RemoteTransport {
    private let client: RelayClient
    private let relayURL: URL
    private let pairingCode: String
    private let role: RelayRole

    public init(
        relayURL: URL,
        pairingCode: String,
        role: RelayRole,
        client: RelayClient = RelayClient()
    ) {
        self.relayURL = relayURL
        self.pairingCode = pairingCode
        self.role = role
        self.client = client
    }

    public func connect() async throws -> AsyncThrowingStream<RemoteEnvelope, any Error> {
        try await client.connect(
            relayURL: relayURL,
            pairingCode: pairingCode,
            role: role
        )
    }

    public func send(_ envelope: RemoteEnvelope) async throws {
        try await client.send(envelope)
    }

    public func disconnect() async {
        await client.disconnect()
    }
}
