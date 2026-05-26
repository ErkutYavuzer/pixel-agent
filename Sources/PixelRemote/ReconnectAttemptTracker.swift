import Foundation

/// **Sprint 35 (v0.2.62):** iOS reconnect loop'unda "stale pairing" tespitini
/// sürdüren saf değer tipi. Mac restart'ı sırasında Mac signing key veya
/// pairing code değişirse, iOS saved pairing artık geçerli değildir —
/// `establishConnection` sessizce timeout verir veya `EnvelopeSigner.verify`
/// her envelope'ı reject eder. Önceden bu durum sonsuz reconnect loop'una
/// neden oluyordu; kullanıcı banner'ı görür ama "QR'ı yenile" prompt'u olmadığı
/// için manuel olarak Settings → Eşleştirmeyi Unut yoluna inerdi.
///
/// Bu tracker iki bağımsız sayaç tutar:
/// - **connectFailureCount**: `transport.connect()` veya stream döngüsü
///   exception attığında artırılır. Threshold (default 5) aşılırsa pairing
///   stale sayılır — exponential backoff ile ~30 saniyelik denemenin sonu.
/// - **verifyFailureCount**: imzalı envelope `EnvelopeSigner.verify` reject
///   ettiğinde veya bağlantı sonrası "ready timeout" (8s) doluğunda artırılır.
///   Threshold (default 3) aşılırsa Mac public key değişmiş demektir.
///
/// İki sayaç ayrı tutulur çünkü "connect fail" relay/network problemi de
/// olabilir (transient); "verify fail" ise key mismatch — daha kesin bir
/// stale göstergesi. UI her ikisinin OR'unu gösterir ama gelecekte verify-
/// only path daha agresif (örn anında banner) için ayrı tutulur.
///
/// `isPairingStaleSuspected` getter herhangi bir threshold aşıldığında `true`.
/// Başarılı connect veya verify-passed envelope geldiğinde `recordSuccess()`
/// ile sayaçlar sıfırlanır.
public struct ReconnectAttemptTracker: Sendable, Equatable {
    /// **Connect fail threshold default.** Exponential backoff 2s → 4s → 8s →
    /// 16s → 30s sequence'inde 5. fail ~30 saniye toplam reconnect süresi
    /// demektir; gerçek network kopukluğu (WiFi geçişi, modem reset) bu
    /// sürenin altında kendini düzeltir, üzeri ise stale pairing göstergesi.
    public static let defaultConnectFailureThreshold: Int = 5

    /// **Verify fail threshold default.** Mac public key değişmişse her
    /// envelope reject olur — 3 ardışık reject çok güvenilir bir sinyal,
    /// transient race veya parse hatası değil.
    public static let defaultVerifyFailureThreshold: Int = 3

    /// **Ready timeout default (saniye).** Connect başarılı olduktan sonra
    /// ilk verify-passed envelope için bekleme süresi. Mac normalde hemen
    /// hostStatus + assistantChunk push'lar; 8s sessizlik ya signing key
    /// mismatch ya da Mac side handler kopuk demek.
    public static let defaultReadyTimeoutSeconds: TimeInterval = 8

    public var connectFailureCount: Int
    public var verifyFailureCount: Int

    public let connectFailureThreshold: Int
    public let verifyFailureThreshold: Int

    public init(
        connectFailureThreshold: Int = Self.defaultConnectFailureThreshold,
        verifyFailureThreshold: Int = Self.defaultVerifyFailureThreshold,
        connectFailureCount: Int = 0,
        verifyFailureCount: Int = 0
    ) {
        self.connectFailureThreshold = max(1, connectFailureThreshold)
        self.verifyFailureThreshold = max(1, verifyFailureThreshold)
        self.connectFailureCount = max(0, connectFailureCount)
        self.verifyFailureCount = max(0, verifyFailureCount)
    }

    /// `true` ise UI prominent banner + "QR'ı Yeniden Tara" sunmalıdır.
    /// Connect VEYA verify threshold'larından biri aşıldığında.
    public var isPairingStaleSuspected: Bool {
        connectFailureCount >= connectFailureThreshold ||
        verifyFailureCount >= verifyFailureThreshold
    }

    /// `transport.connect()` veya receive stream exception attığında çağrılır.
    /// Counter overflow-safe (Int.max sonrası threshold seviyesinde clamp).
    public mutating func recordConnectFailure() {
        if connectFailureCount < Int.max {
            connectFailureCount &+= 1
        }
        // Defensive: negative wrap (gerçekçi değil ama belt & suspenders)
        if connectFailureCount < 0 {
            connectFailureCount = connectFailureThreshold
        }
    }

    /// `EnvelopeSigner.verify` reject ettiğinde veya ready timeout doluğunda
    /// çağrılır. Counter overflow-safe.
    public mutating func recordVerifyFailure() {
        if verifyFailureCount < Int.max {
            verifyFailureCount &+= 1
        }
        if verifyFailureCount < 0 {
            verifyFailureCount = verifyFailureThreshold
        }
    }

    /// Connect başarılı olduğunda veya verify-passed envelope alındığında
    /// çağrılır. Her iki counter sıfırlanır → `isPairingStaleSuspected` false.
    public mutating func recordSuccess() {
        connectFailureCount = 0
        verifyFailureCount = 0
    }
}
