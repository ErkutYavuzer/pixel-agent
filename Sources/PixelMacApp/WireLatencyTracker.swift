import Foundation

/// **Sprint 22 (v0.2.47):** Continuous screenshot stream için wire-level
/// round-trip latency state. Sprint 21'in `AdaptiveRateController`'ı
/// `lastSendLatencyMs`'i kullanır; o değer şu ana kadar **local** (capture +
/// JPEG encode + transport handoff). Wire latency için Mac her frame'e
/// `frameID` iliştirir, iOS aynı ID ile `screenshotFrameAck` döner. Aradaki
/// fark gerçek ağ round-trip'i.
///
/// State Sprint 22 öncesinin saf helper paterniyle yapıldı: `WireLatencyState`
/// struct caller'ın tuttuğu in/out durum; `WireLatencyTracker` enum üstündeki
/// `inout` operations test edilebilir, side-effect dışında saf math.
///
/// **Eski iOS sürümleri:** Mac yeni frameID iletse de eski iOS bunu görmez
/// (sadece base64Image okur, ACK göndermez). Mac sonuç olarak hiç ACK
/// almaz → `lastAckAt` nil → `effectiveLatencyMs` her zaman `localMs`'e
/// düşer. Davranış Sprint 21 ile aynı, **breaking change yok**.
public struct WireLatencyState: Sendable, Equatable {
    /// Gönderilen ama henüz ACK'lenmemiş frame'lerin ID → sentAt eşlemesi.
    /// Tipik stream rate'inde (1Hz) en fazla birkaç element olur; prune
    /// loop'u stale entry'leri temizler.
    public var pending: [String: Date]
    /// Son alınan ACK'in hesapladığı wire latency (ms). nil → henüz ACK
    /// gelmedi (eski iOS veya yeni handshake).
    public var lastWireLatencyMs: Int?
    /// Son ACK'in alındığı an. `effectiveLatencyMs` freshness window
    /// kontrolü için kullanır; ölü stream durumunda local fallback'e düşer.
    public var lastAckAt: Date?

    public init(
        pending: [String: Date] = [:],
        lastWireLatencyMs: Int? = nil,
        lastAckAt: Date? = nil
    ) {
        self.pending = pending
        self.lastWireLatencyMs = lastWireLatencyMs
        self.lastAckAt = lastAckAt
    }
}

public enum WireLatencyTracker {
    /// Bir frame gönderildiğinde caller tarafından çağrılır. `sentAt`
    /// referans noktası: ACK geldiğinde aradaki delta wire-level latency'dir.
    /// Aynı frameID iki kez `record` çağrılırsa son sentAt galip (overwrite).
    public static func record(
        state: inout WireLatencyState,
        frameID: String,
        at sentAt: Date
    ) {
        state.pending[frameID] = sentAt
    }

    /// ACK geldiğinde caller tarafından çağrılır. Eşleşme bulunursa:
    /// - `pending`'den siler (tek-shot ACK)
    /// - `lastWireLatencyMs` + `lastAckAt` günceller
    /// - latency (ms) döner
    ///
    /// Eşleşme yoksa (geç gelmiş, yanlış stream, prune sonrası): nil döner,
    /// state değişmez. Caller no-op kabul edebilir.
    @discardableResult
    public static func consumeAck(
        state: inout WireLatencyState,
        frameID: String,
        receivedAt: Date
    ) -> Int? {
        guard let sentAt = state.pending.removeValue(forKey: frameID) else {
            return nil
        }
        let latencySeconds = receivedAt.timeIntervalSince(sentAt)
        // Saat sapması / negatif latency defensif: en kötü 0'a clamp.
        let latencyMs = max(0, Int(latencySeconds * 1000))
        state.lastWireLatencyMs = latencyMs
        state.lastAckAt = receivedAt
        return latencyMs
    }

    /// `cutoff` tarihinden eski pending entry'leri siler. Caller stream
    /// loop'unda periyodik çağırır (ör. tick başı, son 30 sn'den eski
    /// entry'leri at). Map'in sınırsız büyümesini engeller.
    public static func prune(
        state: inout WireLatencyState,
        olderThan cutoff: Date
    ) {
        state.pending = state.pending.filter { _, sentAt in
            sentAt > cutoff
        }
    }

    /// Adaptive controller'a verilecek "effective" latency:
    /// - Eğer son ACK `freshnessSeconds` içindeyse → `lastWireLatencyMs`
    /// - Aksi halde (ACK hiç gelmedi veya çok eski) → `localMs` fallback
    ///
    /// Bu strateji yeni iOS bağlantılarında wire ölçümünü tercih eder ama
    /// stream başlangıcında (henüz ACK yok) veya eski iOS'larda local
    /// latency'ye sorunsuz düşer. Adaptive controller bu konuda agnostiktir
    /// — sadece "latency ms" parametresi alır.
    public static func effectiveLatencyMs(
        state: WireLatencyState,
        localMs: Int,
        now: Date,
        freshnessSeconds: TimeInterval = 5
    ) -> Int {
        guard let lastAckAt = state.lastAckAt,
              let wire = state.lastWireLatencyMs,
              now.timeIntervalSince(lastAckAt) <= freshnessSeconds
        else {
            return localMs
        }
        return wire
    }
}
