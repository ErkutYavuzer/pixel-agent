import PixelRemote
import SwiftUI

/// **Sprint 10 (v0.2.35):** iOS'tan bir arşivin başlığını + tag listesini
/// düzenleme sheet'i. Save basınca rename ve/veya setTags envelope(ları)
/// Mac'e dispatch edilir; Mac otomatik `archiveListResponse` döner,
/// list güncel görünür, sheet kapanır.
struct EditArchiveSheet: View {
    @EnvironmentObject var session: RemoteSession
    @Environment(\.dismiss) private var dismiss

    let entry: ArchiveEntryPayload

    /// Sheet açıldığında entry değerleriyle doldurulur.
    @State private var titleDraft: String = ""
    @State private var tagDrafts: [String] = []
    @State private var newTagInput: String = ""
    @State private var isSaving: Bool = false
    @State private var lastError: String?

    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Başlık") {
                    TextField("özel başlık (boş = otomatik snippet)", text: $titleDraft)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                }

                Section("Etiketler") {
                    if tagDrafts.isEmpty {
                        Text("Etiket yok")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tagDrafts, id: \.self) { tag in
                            HStack {
                                Text("#\(tag)")
                                    .font(.subheadline)
                                Spacer()
                                Button(role: .destructive) {
                                    tagDrafts.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    HStack {
                        TextField("yeni etiket", text: $newTagInput)
                            .submitLabel(.done)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                            .onSubmit(addCurrentTag)
                        Button("Ekle", action: addCurrentTag)
                            .disabled(normalizedNewTag == nil)
                    }
                }

                if let lastError {
                    Section {
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Kaydet", action: save)
                            .disabled(!hasChanges || !session.isConnected)
                    }
                }
            }
            .onAppear {
                titleDraft = entry.customTitle ?? ""
                tagDrafts = entry.tags ?? []
            }
        }
    }

    // MARK: - Helpers

    private var normalizedNewTag: String? {
        let trimmed = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let capped = trimmed.count <= 30 ? trimmed : String(trimmed.prefix(30))
        return tagDrafts.contains(capped) ? nil : capped
    }

    private func addCurrentTag() {
        guard let normalized = normalizedNewTag else { return }
        tagDrafts.append(normalized)
        tagDrafts.sort()
        newTagInput = ""
    }

    private var originalTitle: String { entry.customTitle ?? "" }
    private var originalTags: [String] { entry.tags ?? [] }

    private var hasTitleChange: Bool {
        titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            != originalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasTagsChange: Bool {
        tagDrafts != originalTags
    }

    private var hasChanges: Bool {
        hasTitleChange || hasTagsChange
    }

    private func save() {
        isSaving = true
        lastError = nil
        Task {
            // Rename: trim sonrası boş ise nil gönder (sıfırla).
            if hasTitleChange {
                let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                await session.renameArchive(
                    id: entry.id,
                    newTitle: trimmed.isEmpty ? nil : trimmed
                )
            }
            // Tags: boş array veya nil → kaldır.
            if hasTagsChange {
                await session.setArchiveTags(
                    id: entry.id,
                    tags: tagDrafts.isEmpty ? nil : tagDrafts
                )
            }
            // Mac otomatik archiveListResponse döner; biraz bekleyip kapat
            // (round-trip ~50-200ms tipik). 300ms feedback hissi için yeterli.
            try? await Task.sleep(nanoseconds: 300_000_000)
            isSaving = false
            dismiss()
        }
    }
}
