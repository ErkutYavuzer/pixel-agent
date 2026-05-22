import Foundation
import PixelRemote

/// İki transport'u sırayla deneyen composite. `connect()` önce `primary`'i
/// dener; throws ise `fallback`'e geçer. Bağlandığı transport `active` olarak
/// tutulur; sonraki `send` / `disconnect` çağrıları yalnız ona yönlenir.
///
/// Tipik kullanım: `FallbackTransport(primary: lan, fallback: relay)` —
/// iOS'ta LAN browse timeout'ta olursa relay devreye girer.
public actor FallbackTransport: RemoteTransport {
    public enum Selection: Sendable, Equatable {
        case none
        case primary
        case fallback
    }

    private let primary: any RemoteTransport
    private let fallback: any RemoteTransport
    private var active: (any RemoteTransport)?
    private var selection: Selection = .none

    public init(primary: any RemoteTransport, fallback: any RemoteTransport) {
        self.primary = primary
        self.fallback = fallback
    }

    /// Hangi transport seçildi? `none` connect öncesi / disconnect sonrası.
    public var currentSelection: Selection { selection }

    public func connect() async throws -> AsyncThrowingStream<RemoteEnvelope, any Error> {
        do {
            let stream = try await primary.connect()
            active = primary
            selection = .primary
            return stream
        } catch {
            // Primary başarısız oldu → fallback dene. Primary'nin partial state'ini temizle.
            await primary.disconnect()
            let stream = try await fallback.connect()
            active = fallback
            selection = .fallback
            return stream
        }
    }

    public func send(_ envelope: RemoteEnvelope) async throws {
        guard let active else {
            throw FallbackError.notConnected
        }
        try await active.send(envelope)
    }

    public func disconnect() async {
        await active?.disconnect()
        active = nil
        selection = .none
    }

    public enum FallbackError: Error, LocalizedError {
        case notConnected

        public var errorDescription: String? {
            switch self {
            case .notConnected: return "Fallback transport bağlı değil; önce connect()."
            }
        }
    }
}
