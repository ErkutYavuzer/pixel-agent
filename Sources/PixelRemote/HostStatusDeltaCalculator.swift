import Foundation
import PixelCore

/// **Sprint 19 (v0.2.44):** İki `HostStatusContent` snapshot'ı karşılaştırıp
/// sadece değişen field'ları içeren `HostStatusDeltaContent` üretir. Saf
/// helper — actor/view bağımsız, test edilebilir.
///
/// **Kullanım:** Mac periyodik push döngüsünde:
/// ```swift
/// let new = HostStatusContent(...)
/// if let delta = HostStatusDeltaCalculator.delta(from: lastSnapshot, to: new) {
///     await remoteHost.sendHostStatusDelta(delta)
///     lastSnapshot = new
/// }
/// ```
///
/// `from: nil` ise ilk push — tüm field'lar yeni snapshot'tan kopyalanır
/// (full bootstrap delta). Sonraki çağrılarda sadece fark.
public enum HostStatusDeltaCalculator {

    /// Eski ve yeni snapshot'ı karşılaştır. Hiç fark yoksa nil (push skip).
    /// `from: nil` ise tüm field'lar dolu döner (ilk frame).
    public static func delta(
        from old: HostStatusContent?,
        to new: HostStatusContent
    ) -> HostStatusDeltaContent? {
        guard let old else {
            // İlk frame — tüm field'lar dolu döner. iOS state'i boş, full
            // bootstrap.
            return HostStatusDeltaContent(
                selectedBackend: new.selectedBackend,
                selectedModel: new.selectedModel,
                planMode: new.planMode,
                availableBackends: new.availableBackends,
                availableModels: new.availableModels,
                activeSubagents: new.activeSubagents,
                systemMetrics: new.systemMetrics,
                screenshotWireLatencyMs: new.screenshotWireLatencyMs
            )
        }

        let backend = old.selectedBackend == new.selectedBackend ? nil : new.selectedBackend
        let model = old.selectedModel == new.selectedModel ? nil : new.selectedModel
        let plan = old.planMode == new.planMode ? nil : new.planMode
        let backends = old.availableBackends == new.availableBackends ? nil : new.availableBackends
        let models = old.availableModels == new.availableModels ? nil : new.availableModels
        let subagents = old.activeSubagents == new.activeSubagents ? nil : new.activeSubagents
        let metrics = old.systemMetrics == new.systemMetrics ? nil : new.systemMetrics
        // Sprint 23 (v0.2.48): wire latency badge. Delta'da nil = "değişmedi";
        // önceki ölçüm korunur. Stream durduğunda Mac değeri nil'leyemez
        // (delta nil "unchanged"); iOS UI gate'i isStreamingScreenshots'a
        // bağlı, dolayısıyla stale değer görünmez.
        let wireLatency = old.screenshotWireLatencyMs == new.screenshotWireLatencyMs
            ? nil
            : new.screenshotWireLatencyMs

        let delta = HostStatusDeltaContent(
            selectedBackend: backend,
            selectedModel: model,
            planMode: plan,
            availableBackends: backends,
            availableModels: models,
            activeSubagents: subagents,
            systemMetrics: metrics,
            screenshotWireLatencyMs: wireLatency
        )
        return delta.isEmpty ? nil : delta
    }
}
