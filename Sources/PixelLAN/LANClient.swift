import Foundation
import Network
import PixelRemote

/// iOS / Mac istemci tarafı: NWBrowser ile Bonjour'da `_pixel-agent._tcp`
/// servislerini bul, seçileni `NWConnection` ile bağla, envelope gönder/al.
public actor LANClient {
    public struct DiscoveredHost: Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
        public let endpoint: NWEndpoint
        /// Bonjour TXT record'undan okunan Mac public key (varsa).
        public let publicKeyBase64: String?
        /// TXT record'daki protokol versiyonu (varsa).
        public let protocolVersionTXT: String?

        public init(name: String, endpoint: NWEndpoint, publicKeyBase64: String?, protocolVersionTXT: String?) {
            self.id = name
            self.name = name
            self.endpoint = endpoint
            self.publicKeyBase64 = publicKeyBase64
            self.protocolVersionTXT = protocolVersionTXT
        }

        public static func == (a: DiscoveredHost, b: DiscoveredHost) -> Bool {
            a.id == b.id
        }
    }

    public enum ClientError: Error, LocalizedError {
        case notConnected
        case connectionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notConnected: return "LAN bağlantısı kurulmadı."
            case .connectionFailed(let s): return "Bağlantı kurulamadı: \(s)"
            }
        }
    }

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var leftoverBuffer = Data()
    private let queue = DispatchQueue(label: "dev.erkutyavuzer.pixel-agent.lan-client", qos: .userInitiated)

    private var browseContinuation: AsyncStream<[DiscoveredHost]>.Continuation?
    private var inboundContinuation: AsyncThrowingStream<RemoteEnvelope, Error>.Continuation?

    public init() {}

    /// Bonjour browse başlatır; bulunan host setini stream üzerinden yayar.
    /// Stream her değişiklikte tam liste verir (incremental delta değil).
    public func browse() -> AsyncStream<[DiscoveredHost]> {
        let stream = AsyncStream<[DiscoveredHost]> { continuation in
            self.browseContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.stopBrowsing() }
            }
        }

        let params = NWParameters()
        params.includePeerToPeer = true
        let newBrowser = NWBrowser(
            for: .bonjourWithTXTRecord(type: LANServiceType.bonjour, domain: LANServiceType.domain),
            using: params
        )

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let hosts = Self.extractHosts(from: results)
            Task { await self.yieldHosts(hosts) }
        }

        newBrowser.start(queue: queue)
        self.browser = newBrowser
        return stream
    }

    public func stopBrowsing() {
        browser?.cancel()
        browser = nil
        browseContinuation?.finish()
        browseContinuation = nil
    }

    /// Belirli host'a bağlan; inbound envelope stream'i döner.
    public func connect(to host: DiscoveredHost) async throws -> AsyncThrowingStream<RemoteEnvelope, Error> {
        if let existing = connection { existing.cancel() }
        leftoverBuffer = .init()

        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let conn = NWConnection(to: host.endpoint, using: params)
        self.connection = conn

        // İlk bağlantı kurulana kadar bekle
        try await waitUntilReady(connection: conn)

        let stream = AsyncThrowingStream<RemoteEnvelope, Error> { continuation in
            self.inboundContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.disconnect() }
            }
        }
        receiveLoop(connection: conn)
        return stream
    }

    public func send(_ envelope: RemoteEnvelope) async throws {
        guard let conn = connection else { throw ClientError.notConnected }
        let data = try LANFraming.encode(envelope)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        inboundContinuation?.finish()
        inboundContinuation = nil
    }

    // MARK: - Helpers

    private func yieldHosts(_ hosts: [DiscoveredHost]) {
        browseContinuation?.yield(hosts)
    }

    private static func extractHosts(from results: Set<NWBrowser.Result>) -> [DiscoveredHost] {
        results.compactMap { result -> DiscoveredHost? in
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }
            let (pk, ver) = txtMetadata(of: result.metadata)
            return DiscoveredHost(
                name: name,
                endpoint: result.endpoint,
                publicKeyBase64: pk,
                protocolVersionTXT: ver
            )
        }.sorted { $0.name < $1.name }
    }

    private static func txtMetadata(of metadata: NWBrowser.Result.Metadata) -> (pk: String?, ver: String?) {
        if case .bonjour(let txt) = metadata {
            return (
                txt[LANServiceType.TXTKey.publicKey],
                txt[LANServiceType.TXTKey.protocolVersion]
            )
        }
        return (nil, nil)
    }

    private func waitUntilReady(connection: NWConnection) async throws {
        // Sendable closure içinde mutable var capture edilemez; lock-protected ref kullan.
        let resumed = ResumedFlag()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.markIfFirst() { cont.resume() }
                case .failed(let err):
                    if resumed.markIfFirst() {
                        cont.resume(throwing: ClientError.connectionFailed(err.localizedDescription))
                    }
                case .cancelled:
                    if resumed.markIfFirst() {
                        cont.resume(throwing: ClientError.connectionFailed("cancelled"))
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    /// Tek-atımlık "first-wins" bayrak — Sendable closure içinde mutable var capture
    /// edilemediği için (Swift 6) lock-korumalı sınıf kullanırız.
    private final class ResumedFlag: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func markIfFirst() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    private func receiveLoop(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { await self.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let error {
            inboundContinuation?.finish(throwing: error)
            return
        }
        if let data, !data.isEmpty {
            leftoverBuffer.append(data)
            do {
                let (envelopes, leftover) = try LANFraming.decode(buffer: leftoverBuffer)
                leftoverBuffer = leftover
                for env in envelopes {
                    inboundContinuation?.yield(env)
                }
            } catch {
                inboundContinuation?.finish(throwing: error)
                return
            }
        }
        if isComplete {
            inboundContinuation?.finish()
            return
        }
        if let conn = connection { receiveLoop(connection: conn) }
    }
}
