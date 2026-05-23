import Foundation

/// Paylaşılan fiziksel kaynakları serialize eden actor (ADR-0005 implementasyonu).
///
/// **Tehdit modeli:** Paralel subagent'lar veya dual-agent peer'lar aynı kaynağa
/// (ekran/klavye/clipboard) aynı anda erişebilir. ToolArbiter FIFO sırayla
/// erişim verir; deadlock-free için canonical sort.
///
/// **Kullanım:**
/// ```swift
/// try await ToolArbiter.shared.with([.pointer]) {
///     try await PointerControl.click(at: point)
/// }
/// ```
///
/// `with(_:body:)` exception-safe — body throw etse veya cancel olsa bile
/// kaynak release edilir.
///
/// **MVP single-agent:** acquire her zaman anında döner — overhead sıfıra
/// yakın. Sadece paralel subagent veya dual-agent yarışı olduğunda waiter
/// queue dolar.
public actor ToolArbiter {

    /// Process-global instance. Singleton istisnası (ADR-0009) — gerçek fiziksel
    /// kaynak mutex; ADR-0005 ve ADR-0026 bu istisnayı kabul eder.
    public static let shared = ToolArbiter()

    /// Paylaşılan kaynak türleri. Canonical sıralama için `Comparable`.
    public enum Resource: Hashable, Sendable, Comparable {
        /// Mouse + klavye input (CGEvent inject).
        case pointer
        /// Ekran capture (ScreenCaptureKit) — read-only ama bazı senaryolarda
        /// session başına tek capture izin verilebilir.
        case screen
        /// macOS pano (NSPasteboard).
        case clipboard
        /// Mikrofon (AVAudioEngine input).
        case mic
        /// Hoparlör (AVSpeechSynthesizer veya NSSound).
        case speaker
        /// Belirli bir path'e yazma — iki farklı dosya paralel olabilir.
        case fileWrite(path: String)

        /// Sort order — deadlock-free multi-acquire için.
        private var order: Int {
            switch self {
            case .pointer: return 0
            case .screen: return 1
            case .clipboard: return 2
            case .mic: return 3
            case .speaker: return 4
            case .fileWrite: return 5
            }
        }

        public static func < (lhs: Resource, rhs: Resource) -> Bool {
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            // Aynı tip — fileWrite path'leri karşılaştır
            switch (lhs, rhs) {
            case (.fileWrite(let l), .fileWrite(let r)):
                return l < r
            default:
                return false
            }
        }
    }

    // MARK: - State

    private var locked: Set<Resource> = []
    private var waiters: [Waiter] = []

    private struct Waiter {
        let id: UUID
        let resources: Set<Resource>
        let continuation: CheckedContinuation<Void, Never>
    }

    public init() {}

    // MARK: - Acquire / Release

    /// `resources`'lerin tümü serbest olana kadar bekler, sonra hepsini kilitler.
    /// FIFO — ilk gelen waiter ilk uyandırılır.
    public func acquire(_ resources: [Resource]) async {
        let set = Set(resources)
        if locked.isDisjoint(with: set) {
            locked.formUnion(set)
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waiter = Waiter(id: UUID(), resources: set, continuation: continuation)
            waiters.append(waiter)
        }
    }

    /// `resources`'leri serbest bırakır. Bekleyen waiter'ları FIFO sırayla
    /// kontrol eder, çıkarıp uyandırır.
    public func release(_ resources: [Resource]) {
        let set = Set(resources)
        locked.subtract(set)
        wakeNextWaiterIfPossible()
    }

    /// Helper — acquire + body + release exception-safe.
    public func with<T: Sendable>(
        _ resources: [Resource],
        body: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire(resources)
        defer { release(resources) }
        return try await body()
    }

    // MARK: - Inspection (test/observability)

    /// Şu an kilitli kaynaklar.
    public func currentlyLocked() -> Set<Resource> {
        locked
    }

    /// Bekleyen waiter sayısı.
    public func waiterCount() -> Int {
        waiters.count
    }

    // MARK: - Internal

    private func wakeNextWaiterIfPossible() {
        // FIFO — ilk waiter'dan başla
        var i = 0
        while i < waiters.count {
            let waiter = waiters[i]
            if locked.isDisjoint(with: waiter.resources) {
                locked.formUnion(waiter.resources)
                waiters.remove(at: i)
                waiter.continuation.resume()
                // Bir uyandırmadan sonra başka waiter da uyandırılabilir
                // (uyandırılan farklı resources kümeleri varsa).
                // Loop devam, indexi sıfırlama gerekmez — sonraki waiter
                // muhtemelen başka bir kaynak için bekliyor.
            } else {
                i += 1
            }
        }
    }
}
