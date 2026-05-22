import Foundation
import PixelCore
import PixelMemory
import SwiftUI

/// Tek-sütun chat (single mode). ChatHost dual mode'da ChatColumn'ları
/// doğrudan kullanır + tek ChatComposer paylaşır.
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @Binding var incomingRemoteText: String?
    let planMode: Bool

    init(
        backend: any ChatBackend,
        conversationStore: ConversationStore,
        incomingRemoteText: Binding<String?>,
        planMode: Bool = false,
        onAssistantComplete: ((String) -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                backend: backend,
                conversationStore: conversationStore,
                onAssistantComplete: onAssistantComplete
            )
        )
        _incomingRemoteText = incomingRemoteText
        self.planMode = planMode
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatColumn(viewModel: viewModel)

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
                onCancel: viewModel.cancelStream
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
}
