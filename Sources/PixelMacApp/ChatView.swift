import Foundation
import PixelCore
import PixelMemory
import SwiftUI

/// Tek-sütun chat (single mode). ChatHost dual mode'da ChatColumn'ları
/// doğrudan kullanır + tek ChatComposer paylaşır.
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @Binding var incomingRemoteText: String?

    init(
        backend: any ChatBackend,
        conversationStore: ConversationStore,
        incomingRemoteText: Binding<String?>,
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
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatColumn(viewModel: viewModel)

            Divider()

            ChatComposer(
                draft: $viewModel.draft,
                isStreaming: viewModel.isStreaming,
                onSend: {
                    let text = viewModel.draft
                    viewModel.draft = ""
                    viewModel.send(text: text)
                },
                onCancel: viewModel.cancelStream
            )
        }
        .onChange(of: incomingRemoteText) { _, newValue in
            guard let text = newValue, !text.isEmpty, !viewModel.isStreaming else { return }
            viewModel.send(text: text)
            incomingRemoteText = nil
        }
    }
}
