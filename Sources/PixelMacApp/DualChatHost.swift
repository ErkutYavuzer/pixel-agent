import PixelBackends
import PixelCore
import PixelMemory
import SwiftUI

/// İki backend'i yan yana, ortak composer ile. Her sütun kendi ConversationStore
/// dosyasına yazar (conversation-<kind>.jsonl). iOS forward burada YOK — sadece
/// Mac içinde paralel sohbet.
struct DualChatHost: View {
    let leftBackend: any ChatBackend
    let rightBackend: any ChatBackend
    let leftTitle: String
    let rightTitle: String
    let planMode: Bool

    @StateObject private var leftVM: ChatViewModel
    @StateObject private var rightVM: ChatViewModel
    @State private var draft: String = ""

    init(
        leftBackend: any ChatBackend,
        rightBackend: any ChatBackend,
        leftTitle: String,
        rightTitle: String,
        leftStoreFileName: String,
        rightStoreFileName: String,
        planMode: Bool = false
    ) {
        self.leftBackend = leftBackend
        self.rightBackend = rightBackend
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
        self.planMode = planMode

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
                ChatColumn(viewModel: leftVM, title: leftTitle)
                Divider()
                ChatColumn(viewModel: rightVM, title: rightTitle)
            }

            Divider()

            ChatComposer(
                draft: $draft,
                isStreaming: leftVM.isStreaming || rightVM.isStreaming,
                planMode: planMode,
                onSend: sendBoth,
                onCancel: cancelBoth
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
