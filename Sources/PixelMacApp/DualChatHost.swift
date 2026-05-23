import PixelBackends
import PixelCore
import PixelMemory
import PixelSubagent
import SwiftUI

/// İki backend'i yan yana, ortak composer ile. Her sütun kendi ConversationStore
/// dosyasına yazar (conversation-<kind>.jsonl). iOS forward burada YOK — sadece
/// Mac içinde paralel sohbet.
///
/// Subagent panel ve dispatch butonu sol backend'i (`leftKind`) kullanır — kullanıcı
/// kararı: dual mode'da Subagent için tek default backend yeterli.
struct DualChatHost: View {
    let leftBackend: any ChatBackend
    let rightBackend: any ChatBackend
    let leftKind: CLIKind
    let rightKind: CLIKind
    let leftTitle: String
    let rightTitle: String
    let planMode: Bool

    @StateObject private var leftVM: ChatViewModel
    @StateObject private var rightVM: ChatViewModel
    @ObservedObject var subagentManager: SubagentManager
    @State private var draft: String = ""

    init(
        leftBackend: any ChatBackend,
        rightBackend: any ChatBackend,
        leftKind: CLIKind,
        rightKind: CLIKind,
        leftTitle: String,
        rightTitle: String,
        leftStoreFileName: String,
        rightStoreFileName: String,
        subagentManager: SubagentManager,
        planMode: Bool = false
    ) {
        self.leftBackend = leftBackend
        self.rightBackend = rightBackend
        self.leftKind = leftKind
        self.rightKind = rightKind
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
        self.planMode = planMode
        self.subagentManager = subagentManager

        let leftStore = Self.makeStore(fileName: leftStoreFileName)
        let rightStore = Self.makeStore(fileName: rightStoreFileName)

        _leftVM = StateObject(
            wrappedValue: ChatViewModel(
                backend: leftBackend,
                conversationStore: leftStore
            )
        )
        _rightVM = StateObject(
            wrappedValue: ChatViewModel(
                backend: rightBackend,
                conversationStore: rightStore
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ChatColumn(viewModel: leftVM, title: leftTitle, backendKind: leftKind)
                Divider()
                ChatColumn(viewModel: rightVM, title: rightTitle, backendKind: rightKind)
            }

            if !subagentManager.sessions.isEmpty {
                Divider()
                SubagentPanelView(manager: subagentManager)
            }

            Divider()

            ChatComposer(
                draft: $draft,
                isStreaming: leftVM.isStreaming || rightVM.isStreaming,
                planMode: planMode,
                onSend: sendBoth,
                onCancel: cancelBoth,
                onDispatchSubagent: dispatchSubagent,
                subagentDisabled: subagentManager.isCapReached
            )
        }
        .onAppear {
            leftVM.planMode = planMode
            rightVM.planMode = planMode
        }
        .onChange(of: planMode) { _, newValue in
            leftVM.planMode = newValue
            rightVM.planMode = newValue
        }
    }

    private func sendBoth() {
        let text = draft
        draft = ""
        leftVM.send(text: text)
        rightVM.send(text: text)
    }

    private func cancelBoth() {
        leftVM.cancelStream()
        rightVM.cancelStream()
    }

    private func dispatchSubagent() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let result = subagentManager.dispatch(prompt: text, backend: leftKind, budget: .default)
        if case .success = result {
            draft = ""
        }
    }

    private static func makeStore(fileName: String) -> ConversationStore {
        do {
            return try ConversationStore(fileName: fileName)
        } catch {
            // Çok nadir; düşersek geçici bir lokasyona yaz
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("pixel-agent-fallback-\(UUID().uuidString)")
            return (try? ConversationStore(directory: tmpDir, fileName: fileName))!
        }
    }
}
