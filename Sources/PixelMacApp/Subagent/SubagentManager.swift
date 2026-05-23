import Foundation
import PixelBackends
import PixelCore
import PixelSubagent

/// UI'a bağlı, paralel subagent havuzu yöneticisi.
///
/// `@MainActor final class` (actor değil), çünkü `@Published var sessions` SwiftUI
/// binding'i için MainActor isolation gerekiyor. Cap atomicity MainActor reentrancy
/// yokluğu ile zaten garanti — `dispatch` synchronous bir slice'ta count check + append
/// yapar, araya başka MainActor work giremez.
///
/// Hem UI dispatch'i (composer butonu) hem MCP bridge dispatch'i (ControlSocketServer)
/// buraya gelir; her ikisi de aynı `sessions` listesine yazar — birleşik panel.
@MainActor
final class SubagentManager: ObservableObject {
    @Published private(set) var sessions: [SubagentSession] = []

    let maxConcurrent: Int

    private let backendResolver: @MainActor (CLIKind) -> (any ChatBackend)?

    /// C1: Bir subagent terminal status'a (completed/budgetExceeded/cancelled/
    /// failed) ulaştığında çağrılır. Aktif ChatView/DualChatHost burayı set
    /// edip sonucu ana chat'e bir `.system` mesajı olarak akıtır. Tek
    /// callback — single mode'da ChatView, dual mode'da DualChatHost set
    /// eder; ChatHost aynı anda yalnızca birini render ettiği için yarış yok.
    var onSessionCompleted: (@MainActor (SubagentSession) -> Void)?

    /// C10: Dispatch denenip cap'e takıldığında her seferinde yeni `Date()`
    /// set edilir. ChatHost `.onChange(of:)` ile dinleyip transient banner
    /// gösterir. nil değer "henüz cap-reach yaşanmadı" demek.
    @Published private(set) var lastCapReachedAt: Date?

    /// Aktif çalışan subagent task'leri — cancel için referans.
    private var runners: [SubagentID: Task<Void, Never>] = [:]

    /// `dispatchAndWait` callerlarının beklediği continuation map'i. `finalize` çalıştığında
    /// id varsa resume eder; yoksa edge-case race olmaz çünkü ikisi de MainActor'da serialize.
    private var continuations: [SubagentID: CheckedContinuation<SubagentResult, Never>] = [:]

    init(
        maxConcurrent: Int = 3,
        backendResolver: @escaping @MainActor (CLIKind) -> (any ChatBackend)?
    ) {
        precondition(maxConcurrent > 0, "maxConcurrent > 0 olmalı")
        self.maxConcurrent = maxConcurrent
        self.backendResolver = backendResolver
    }

    // MARK: - Public API

    /// UI tarafından çağrılır. Cap dolu veya backend yoksa hata; aksi halde session
    /// hemen eklenir ve background task başlatılır. Result'a beklemek istersen
    /// `dispatchAndWait` kullan.
    @discardableResult
    func dispatch(
        prompt: String,
        backend kind: CLIKind,
        budget: Budget = .default
    ) -> Result<SubagentID, DispatchError> {
        guard activeCount < maxConcurrent else {
            // C10: UI / MCP bridge dinlesin ve transient banner göstersin.
            lastCapReachedAt = Date()
            return .failure(.capReached(maxConcurrent: maxConcurrent))
        }
        guard let backend = backendResolver(kind) else {
            return .failure(.backendUnavailable(kind))
        }

        let id = SubagentID()
        let session = SubagentSession(
            id: id,
            prompt: prompt,
            backendKind: kind,
            budget: budget,
            status: .pending,
            startedAt: Date()
        )
        sessions.append(session)

        let runner = SubagentRunner(backend: backend, budget: budget, id: id)
        runners[id] = Task { [weak self] in
            await MainActor.run { self?.updateStatus(id: id, to: .running) }

            // Streaming — her chunk MainActor'da session.partialOutput'a append
            // edilir; terminal event session'ı finalize eder.
            var didFinalize = false
            for await event in runner.runStreaming(prompt: prompt) {
                switch event {
                case .chunk(let chunk):
                    await MainActor.run { self?.appendChunk(id: id, chunk: chunk) }
                case .finished(let result):
                    didFinalize = true
                    await MainActor.run { self?.finalize(id: id, result: result) }
                }
            }

            // `cancel(_:)` outer Task'i iptal edince AsyncStream consumer'ı kooperatif
            // sonlanır — `.finished` event'i ulaşmadan döngü çıkabilir. Finalize
            // çağrılmazsa `dispatchAndWait` continuation leak olur. Defensive:
            // synthetic `.cancelled` ile finalize et (partial output session'dan okunur).
            if !didFinalize {
                let partial = await MainActor.run {
                    self?.sessions.first(where: { $0.id == id })?.partialOutput ?? ""
                }
                await MainActor.run {
                    self?.finalize(
                        id: id,
                        result: .cancelled(partialOutput: partial, durationSeconds: 0)
                    )
                }
            }
        }

        return .success(id)
    }

    /// MCP bridge tarafından çağrılır. `dispatch` + result'a kadar bekler.
    /// Cap dolu / backend yok hatası UI ile aynı — caller bunu kullanıcıya iletir.
    func dispatchAndWait(
        prompt: String,
        backend kind: CLIKind,
        budget: Budget = .default
    ) async -> Result<SubagentResult, DispatchError> {
        switch dispatch(prompt: prompt, backend: kind, budget: budget) {
        case .failure(let error):
            return .failure(error)
        case .success(let id):
            let result = await withCheckedContinuation {
                (continuation: CheckedContinuation<SubagentResult, Never>) in
                // Edge-case: çok hızlı bir mock backend `dispatch`'in başlattığı Task
                // ilk `await MainActor.run` çağrısında suspend olur — biz buraya
                // dönerken hâlâ MainActor'dayız. Yine de defensive: result çoktan
                // finalize edilmişse direkt resume.
                if let session = sessions.first(where: { $0.id == id }),
                   let existing = session.result {
                    continuation.resume(returning: existing)
                } else {
                    continuations[id] = continuation
                }
            }
            return .success(result)
        }
    }

    /// Çalışan subagent'i cooperative cancel eder. `SubagentRunner` Task.isCancelled
    /// kontrol ettiği noktada `.cancelled` döner, `finalize` status'u günceller.
    func cancel(_ id: SubagentID) {
        runners[id]?.cancel()
    }

    /// Terminal status'taki session'ı listeden siler. Çalışan session'lar dismiss
    /// edilemez; önce cancel çağırılmalı.
    func dismiss(_ id: SubagentID) {
        guard let session = sessions.first(where: { $0.id == id }),
              session.status.isTerminal else { return }
        sessions.removeAll { $0.id == id }
        runners.removeValue(forKey: id)
    }

    /// Şu an pending+running olan session sayısı.
    var activeCount: Int {
        sessions.lazy.filter { !$0.status.isTerminal }.count
    }

    /// Havuzun dolu olup olmadığı — composer butonu disable durumuna bağlı.
    var isCapReached: Bool {
        activeCount >= maxConcurrent
    }

    // MARK: - Internal mutations

    private func updateStatus(id: SubagentID, to status: SubagentStatus) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].status = status
    }

    private func appendChunk(id: SubagentID, chunk: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].partialOutput += chunk
    }

    private func finalize(id: SubagentID, result: SubagentResult) {
        var finalizedSession: SubagentSession?
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].status = Self.status(from: result)
            sessions[idx].finishedAt = Date()
            sessions[idx].result = result
            finalizedSession = sessions[idx]
        }
        runners.removeValue(forKey: id)
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: result)
        }
        // C1: ChatView'a sonucu ilet — kayıtlı listener varsa ana chat'e
        // bir mesaj olarak akar. Listener yoksa (henüz wire-up olmamış)
        // panel yine de kartı gösterir, kaybedilen bir şey yok.
        if let session = finalizedSession {
            onSessionCompleted?(session)
        }
    }

    private static func status(from result: SubagentResult) -> SubagentStatus {
        switch result {
        case .completed: return .completed
        case .budgetExceeded(let reason, _, _): return .budgetExceeded(reason)
        case .cancelled: return .cancelled
        case .failed(let error, _, _): return .failed(error: error)
        }
    }
}

// MARK: - Errors

enum DispatchError: Error, LocalizedError, Equatable {
    /// Maksimum paralel subagent sayısına ulaşıldı.
    case capReached(maxConcurrent: Int)

    /// Talep edilen backend için CLI bulunamadı (PATH'te yok veya RootView'da
    /// resolve edilmemiş).
    case backendUnavailable(CLIKind)

    var errorDescription: String? {
        switch self {
        case .capReached(let max):
            return "Subagent havuzu dolu (\(max)/\(max) aktif). Bir tanesi bitince tekrar deneyin."
        case .backendUnavailable(let kind):
            return "\(kind.displayName) CLI bulunamadı veya yüklü değil."
        }
    }
}
