import Foundation
import PixelBackends
import PixelCore
import PixelMemory
import PixelSubagent
import SwiftUI

/// Tek-sütun chat (single mode). ChatHost dual mode'da ChatColumn'ları
/// doğrudan kullanır + tek ChatComposer paylaşır.
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @ObservedObject var subagentManager: SubagentManager
    @Binding var incomingRemoteText: String?
    let backendKind: CLIKind
    let planMode: Bool

    init(
        backend: any ChatBackend,
        backendKind: CLIKind,
        conversationStore: ConversationStore,
        subagentManager: SubagentManager,
        incomingRemoteText: Binding<String?>,
        planMode: Bool = false,
        onAssistantChunk: ((String, String) -> Void)? = nil,
        onAssistantComplete: ((String, String) -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                backend: backend,
                conversationStore: conversationStore,
                onAssistantChunk: onAssistantChunk,
                onAssistantComplete: onAssistantComplete
            )
        )
        self.subagentManager = subagentManager
        _incomingRemoteText = incomingRemoteText
        self.backendKind = backendKind
        self.planMode = planMode
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatColumn(viewModel: viewModel, backendKind: backendKind)

            if !subagentManager.sessions.isEmpty {
                Divider()
                SubagentPanelView(manager: subagentManager)
            }

            Divider()

            ChatComposer(
                draft: $viewModel.draft,
                isStreaming: viewModel.isStreaming,
                planMode: viewModel.planMode,
                onSend: {
                    let text = viewModel.draft
                    viewModel.draft = ""
                    viewModel.send(text: text)
                },
                onCancel: viewModel.cancelStream,
                onDispatchSubagent: dispatchSubagent,
                subagentDisabled: subagentManager.isCapReached
            )
        }
        .onAppear { viewModel.planMode = planMode }
        .onChange(of: planMode) { _, newValue in
            viewModel.planMode = newValue
        }
        .onChange(of: incomingRemoteText) { _, newValue in
            guard let text = newValue, !text.isEmpty, !viewModel.isStreaming else { return }
            viewModel.send(text: text)
            incomingRemoteText = nil
        }
    }

    private func dispatchSubagent() {
        let text = viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let result = subagentManager.dispatch(prompt: text, backend: backendKind, budget: .default)
        if case .success = result {
            viewModel.draft = ""
        }
    }
}
