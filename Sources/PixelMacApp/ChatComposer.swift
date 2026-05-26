import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatComposer: View {
    @Binding var draft: String
    let isStreaming: Bool
    var planMode: Bool = false
    let onSend: () -> Void
    let onCancel: () -> Void

    /// Opsiyonel: arka plan subagent dispatch'i için callback. `nil` ise buton render
    /// edilmez (geriye uyumluluk).
    var onDispatchSubagent: (() -> Void)? = nil

    /// `true` ise subagent butonu disabled — havuz dolu olduğunda kullanılır.
    var subagentDisabled: Bool = false

    /// **Sprint 42 (v0.2.69):** Voice toggle callback. nil → mic button
    /// render edilmez (geriye uyumluluk, test'ler).
    var onToggleVoice: (() -> Void)? = nil

    /// **Sprint 42:** Voice session aktif mi — mic ikonu state.
    var isVoiceActive: Bool = false

    /// A8: TextField fokusta mı? `@FocusState` SwiftUI'ın native fokus
    /// takibi — animate ile birlikte halo'yu yumuşatır.
    @FocusState private var isComposerFocused: Bool

    /// **Sprint 5:** Drag-drop drop targeted state — `.onDrop` `isTargeted`
    /// binding'i. Halo yeşile döner, kullanıcı dosyayı bırakabileceğini bilir.
    @State private var isDropTargeted: Bool = false

    /// **Sprint 32 (v0.2.58):** Her send sonrası increment edilen counter —
    /// `.id()` modifier'i değişince SwiftUI TextField'ı tamamen yeniden
    /// inşa eder; NSTextField internal buffer'ı resetlenir. macOS
    /// `TextField(axis: .vertical)` binding sync bug için bilinen en
    /// garantili workaround. Defocus-refocus tek başına yetmedi.
    @State private var sendCounter: Int = 0

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var placeholder: String {
        planMode ? "Plan modu — sadece okuma/araştırma" : "Mesaj yaz..."
    }

    /// Saf helper sonucu — overlay stroke rengini + kalınlığını verir.
    private var haloStyle: ComposerHaloStyle {
        ComposerHaloStyle.resolve(
            planMode: planMode,
            isFocused: isComposerFocused,
            isStreaming: isStreaming,
            isDropTargeted: isDropTargeted
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .focused($isComposerFocused)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSend { performSend() } }
                // **v0.2.20:** Shift+Enter → newline (multi-line composer). Plain
                // Enter zaten `.onSubmit` ile submit ediyor; bu handler sadece
                // shift basılıyken devreye girer ve newline append eder. SwiftUI
                // TextField cursor pozisyonuna API yok — pratik yaklaşım: draft
                // sonuna `\n` ekle (çoğu Shift+Enter mesajın sonunda kullanılır).
                .onKeyPress(.return, phases: [.down]) { press in
                    if press.modifiers.contains(.shift) {
                        draft += "\n"
                        return .handled
                    }
                    return .ignored
                }
                .disabled(isStreaming)
                .overlay {
                    if haloStyle.isVisible {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(haloStyle.strokeColor, lineWidth: haloStyle.lineWidth)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: haloStyle)
                // **Sprint 5:** Drag-drop — file URL(s) bırakıldığında her biri
                // için FileDropFormatter.snippet çağırıp draft sonuna append.
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }
                // **Sprint 32 (v0.2.58):** sendCounter değişince TextField
                // tamamen rebuild olur — NSTextField internal buffer reset.
                // macOS axis-vertical TextField binding sync bug workaround'u.
                .id("composer-\(sendCounter)")

            if isStreaming {
                Button("Durdur", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
            } else {
                // Sprint 42 (v0.2.69): Voice toggle mic button. Aktif iken
                // kırmızı tint, ikonu mic.fill; aksi takdirde mic.circle.
                if let toggleVoice = onToggleVoice {
                    Button(action: { performHaptic(); toggleVoice() }) {
                        Image(systemName: isVoiceActive ? "mic.fill" : "mic.circle")
                            .foregroundStyle(isVoiceActive ? .red : .primary)
                    }
                    .buttonStyle(.borderless)
                    .help(isVoiceActive
                          ? "Konuşmayı durdur (mikrofonu kapat)"
                          : "Konuşma modunu başlat (Apple Speech)")
                }
                if let dispatch = onDispatchSubagent {
                    Button(action: { performHaptic(); dispatch() }) {
                        Image(systemName: "person.2.wave.2")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canSend || subagentDisabled)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .help(subagentDisabled
                          ? "Subagent havuzu dolu (3/3 aktif)"
                          : "Arka plan subagent başlat (⌘⇧Return)")
                }
                Button("Gönder", action: performSend)
                    .keyboardShortcut(.return)
                    .disabled(!canSend)
            }
        }
        .padding()
    }

    /// A8: send tetiklemeden önce hafif `.alignment` haptic — kullanıcı
    /// trackpad'inde "yolladım" hissi alır. Onsubmit ve Gönder butonu
    /// her ikisi de buradan geçer.
    ///
    /// **Sprint 32 (v0.2.57-58):** `TextField(axis: .vertical)` macOS'ta
    /// bilinen bir SwiftUI bug var — focus active iken parent'in
    /// `draft = ""` yazması NSTextField internal buffer'a yansımıyor;
    /// kullanıcının her mesaj sonrası eski metni elle silmesi gerekiyordu.
    ///
    /// **v0.2.57 ilk denedim:** Defocus → onSend → refocus. Yetmedi —
    /// bazı SwiftUI sürümlerinde defocus async tamamlanıyor + binding
    /// commit cycle'ı henüz değişmemiş NSTextField buffer'a yazıyor.
    ///
    /// **v0.2.58 garantili çözüm:** `sendCounter` increment + TextField
    /// `.id()` modifier'i — SwiftUI tamamen yeniden inşa eder, NSTextField
    /// instance'ı silinir, yeni boş binding'le yeni instance yaratılır.
    /// Focus rebuild sonrasında manuel restore.
    private func performSend() {
        guard canSend else { return }
        performHaptic()
        let wasFocused = isComposerFocused
        onSend()
        // Critical: parent draft = "" set ettikten sonra .id() değişimi
        // TextField'i baştan inşa et — eski NSTextField buffer'ı yok.
        sendCounter &+= 1
        if wasFocused {
            // Rebuild sonrası focus restore — kullanıcı klavyeden devam.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isComposerFocused = true
            }
        }
    }

    private func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// **Sprint 5:** `.onDrop` callback. Her provider'dan file URL'i yükle,
    /// FileDropFormatter.snippet'e ver, draft sonuna append. Async — drop
    /// callback'i true döner (kabul edildi), gerçek append main actor'da.
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let resolvedURL: URL?
                if let url = item as? URL {
                    resolvedURL = url
                } else if let data = item as? Data {
                    resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    resolvedURL = nil
                }
                guard let url = resolvedURL,
                      let snippet = FileDropFormatter.snippet(forFileURL: url) else { return }
                Task { @MainActor in
                    if !draft.isEmpty, !draft.hasSuffix("\n") {
                        draft += "\n"
                    }
                    draft += snippet
                    if !draft.hasSuffix("\n") {
                        draft += "\n"
                    }
                }
            }
        }
    }
}
