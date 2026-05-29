import Foundation

/// **Sprint 52 (v0.2.81) — F1 Faz 1C.** Kaydedilmiş bir makroyu (sıralı
/// `MacroStep`) yeniden oynatır.
///
/// **Semantik replay (koordinat değil):** `.click` adımında önce `opaqueID`
/// AX ile yeniden çözülür (`clickResolved`), başarısızsa `query` fallback —
/// böylece pencere taşınsa/boyut değişse bile çalışır. Element hiç bulunamazsa
/// `NotFoundPolicy` (retry/skip/abort) uygulanır.
///
/// **Runaway safety:** `MacroReplayPlan.validate` (maxSteps) + `maxDurationSeconds`
/// wallclock + her adımda `Task.checkCancellation()` (UI "Durdur" → Task cancel).
/// **Plan Mode guard:** destructive adım + `allowDestructive == false` → bloklanır.
///
/// Saf karar mantığı [[MacroReplayPlan]]'de (test edilebilir); bu actor ince
/// executor.
public actor MacroReplayer {
    private let computer: PixelComputerUse

    public init(computer: PixelComputerUse = PixelComputerUse()) {
        self.computer = computer
    }

    /// `[MacroStep]` alır (MacroRecording PixelMemory'de — bu modül ona bağımlı
    /// değil; caller `recording.steps` geçer).
    @discardableResult
    public func replay(
        _ recordedSteps: [MacroStep],
        options: MacroReplayOptions = .default,
        onProgress: (@Sendable (MacroProgress) -> Void)? = nil
    ) async throws -> MacroReplayReport {
        // 1. Doğrulama (saf) — boş / runaway cap.
        let steps: [MacroStep]
        switch MacroReplayPlan.validate(recordedSteps, maxSteps: options.maxSteps) {
        case .success(let s): steps = s
        case .failure(let error): throw error
        }
        // 2. Plan Mode guard (saf).
        if MacroReplayPlan.isBlockedByPlanMode(steps, allowDestructive: options.allowDestructive) {
            throw MacroReplayError.planModeBlocked
        }
        // 3. Execute.
        let deadline = Date().addingTimeInterval(options.maxDurationSeconds)
        var executed = 0
        var skipped = 0
        for (index, step) in steps.enumerated() {
            try Task.checkCancellation()
            guard Date() < deadline else { throw MacroReplayError.timedOut }
            onProgress?(MacroProgress(stepIndex: index, total: steps.count, step: step))
            let outcome = try await execute(step, index: index, options: options)
            switch outcome {
            case .executed: executed += 1
            case .skipped: skipped += 1
            }
            if options.interStepDelayMs > 0 {
                try await Task.sleep(for: .milliseconds(options.interStepDelayMs))
            }
        }
        return MacroReplayReport(executed: executed, skipped: skipped, total: steps.count)
    }

    private enum StepOutcome { case executed, skipped }

    private func execute(_ step: MacroStep, index: Int, options: MacroReplayOptions) async throws -> StepOutcome {
        switch step {
        case .wait(let ms):
            if ms > 0 { try await Task.sleep(for: .milliseconds(ms)) }
            return .executed
        case .screenshot(let target):
            _ = try? await computer.screenshot(of: target)  // best-effort, yan-etkisiz
            return .executed
        case .type(let text, let into):
            try await computer.type(text, into: into)  // into resolve fail → throws (abort)
            return .executed
        case .click(let query, let opaqueID, let count, let modifiers):
            return try await executeClick(query: query, opaqueID: opaqueID, count: count, modifiers: modifiers, index: index, options: options)
        }
    }

    private func executeClick(
        query: UIQuery?, opaqueID: String?, count: Int, modifiers: ModifierFlags,
        index: Int, options: MacroReplayOptions
    ) async throws -> StepOutcome {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            // 1. opaqueID re-resolve (en kararlı handle).
            if let oid = opaqueID,
               let resolved = try? await computer.clickResolved(opaqueID: oid, count: count, modifiers: modifiers),
               resolved != nil {
                return .executed
            }
            // 2. query fallback.
            if let q = query, (try? await computer.click(q, count: count, modifiers: modifiers)) != nil {
                return .executed
            }
            // 3. bulunamadı → politika.
            switch MacroReplayPlan.decideOnNotFound(policy: options.notFoundPolicy, attempt: attempt) {
            case .retry(let afterMs):
                attempt += 1
                if afterMs > 0 { try await Task.sleep(for: .milliseconds(afterMs)) }
                continue
            case .skip:
                return .skipped
            case .abort:
                throw MacroReplayError.elementNotFound(stepIndex: index)
            }
        }
    }
}

/// **Sprint 52:** Replay ilerleme bildirimi (UI progress).
public struct MacroProgress: Sendable, Equatable {
    public let stepIndex: Int
    public let total: Int
    public let step: MacroStep
    public init(stepIndex: Int, total: Int, step: MacroStep) {
        self.stepIndex = stepIndex
        self.total = total
        self.step = step
    }
}

/// **Sprint 52:** Replay sonucu.
public struct MacroReplayReport: Sendable, Equatable {
    public let executed: Int
    public let skipped: Int
    public let total: Int
    public init(executed: Int, skipped: Int, total: Int) {
        self.executed = executed
        self.skipped = skipped
        self.total = total
    }
}
