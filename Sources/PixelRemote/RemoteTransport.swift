import Foundation

/// Mac ↔ iOS arası envelope iletişimini yapan transport soyutlaması.
///
/// Concrete implementasyonlar:
/// - `RelayTransport` (PixelRemote): Cloudflare Worker üzerinden WebSocket.
/// - `LANServerTransport` (PixelLAN, Mac): Bonjour + NWListener TCP server.
/// - `LANClientTransport` (PixelLAN, iOS): NWBrowser + NWConnection.
/// - `FallbackTransport` (PixelLAN): primary fail olursa fallback'e geçer.
///
/// `RemoteHost` ve iOS `RemoteSession` herhangi bir `RemoteTransport` kabul eder;
/// böylece LAN-only / relay-only / fallback mantığı caller'da kalır.
public protocol RemoteTransport: Sendable {
    /// Bağlantıyı başlat ve gelen envelope stream'ini döndür.
    /// Stream finish edince transport disconnect olmuş kabul edilir.
    func connect() async throws -> AsyncThrowingStream<RemoteEnvelope, any Error>

    /// Aktif bağlantı üzerinden envelope gönder. Bağlı değilse throws.
    func send(_ envelope: RemoteEnvelope) async throws

    /// Bağlantıyı temiz kapat.
    func disconnect() async
}
