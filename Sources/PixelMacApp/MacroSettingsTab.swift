import PixelComputerUse
import PixelMemory
import SwiftUI

/// **Sprint 52 (v0.2.81) — F1 Faz 1B.** Makro kayıt + listeleme UI'si.
/// Replay ("Oynat") Faz 1C'de (v0.2.82) gelir.
struct MacroSettingsTab: View {
    @ObservedObject private var recorder = MacroRecorder.shared
    @State private var macros: [MacroRecording] = []
    @State private var loadError: String?
    @State private var isLoading: Bool = true
    @State private var replayingID: UUID?
    @State private var replayMessage: String?
    @State private var replayTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                if recorder.isRecording {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill").foregroundStyle(.red)
                        Text("Kaydediliyor — \(recorder.draftSteps.count) adım")
                            .font(.callout)
                        Spacer()
                        Button("Durdur ve Kaydet") { Task { await stopAndReload() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(recorder.draftSteps.isEmpty)
                        Button("İptal", role: .destructive) { recorder.cancel() }
                            .buttonStyle(.borderless)
                    }
                    ForEach(Array(recorder.draftSteps.enumerated()), id: \.offset) { idx, step in
                        Text("\(idx + 1). \(step.summary)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        TextField("Makro adı (opsiyonel)", text: $recorder.draftTitle)
                        Button {
                            recorder.start(title: recorder.draftTitle)
                        } label: {
                            Label("Kayda Başla", systemImage: "record.circle")
                        }
                    }
                    Text("Kayda başladıktan sonra agent'ın yaptığı her tıklama (ui_click) ve yazma (ui_type) adımı semantik olarak (AX query + opaqueID) kaydedilir. Replay v0.2.82'de gelecek.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } header: {
                Text("Kayıt")
            }

            Section {
                if isLoading {
                    HStack { ProgressView().controlSize(.small); Text("Yükleniyor…").foregroundStyle(.secondary) }
                } else if let loadError {
                    Text("Yüklenemedi: \(loadError)").foregroundStyle(.red).font(.caption)
                } else if macros.isEmpty {
                    Text("Henüz kayıtlı makro yok.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    if let replayMessage {
                        Text(replayMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(macros) { macroRow($0) }
                }
            } header: {
                HStack {
                    Text("Makrolar (\(macros.count))")
                    Spacer()
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                        .controlSize(.small).help("Listeyi yenile")
                }
            } footer: {
                Text("Semantik AX makroları (koordinat değil) — pencere taşınsa bile replay'de element yeniden çözülür. `macros.jsonl` append-only.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
        .task { await load() }
    }

    private func macroRow(_ macro: MacroRecording) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(macro.steps.enumerated()), id: \.offset) { idx, step in
                    Text("\(idx + 1). \(step.summary)").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(macro.title).font(.callout.bold())
                    Text("\(macro.stepCount) adım").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if replayingID == macro.id {
                    ProgressView().controlSize(.small)
                    Button("Durdur") { cancelReplay() }
                        .buttonStyle(.borderless)
                } else {
                    Button { replay(macro) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.borderless)
                        .help("Bu makroyu oynat (ekranda gerçek tıklamalar)")
                        .disabled(replayingID != nil)
                }
                Button(role: .destructive) {
                    Task { await delete(macro.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Bu makroyu sil")
                .disabled(replayingID != nil)
            }
        }
        .padding(.vertical, 2)
    }

    private func replay(_ macro: MacroRecording) {
        replayingID = macro.id
        replayMessage = nil
        replayTask = Task {
            let replayer = MacroReplayer()
            let result: String
            do {
                let report = try await replayer.replay(macro.steps)
                result = "✓ \"\(macro.title)\": \(report.executed)/\(report.total) adım çalıştı" +
                    (report.skipped > 0 ? " (\(report.skipped) atlandı)" : "")
            } catch {
                result = "⚠️ \"\(macro.title)\" replay durdu: \(error)"
            }
            await MainActor.run {
                replayMessage = result
                replayingID = nil
                replayTask = nil
            }
        }
    }

    private func cancelReplay() {
        replayTask?.cancel()
        replayTask = nil
        replayingID = nil
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let store = try MacroStore()
            macros = try await store.loadActive()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func stopAndReload() async {
        _ = await recorder.stop()
        await load()
    }

    @MainActor
    private func delete(_ id: UUID) async {
        do {
            let store = try MacroStore()
            try await store.delete(id: id)
            await load()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
