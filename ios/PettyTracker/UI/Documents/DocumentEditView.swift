import SwiftUI

struct DocumentEditView: View {
    let documentId: Int64?
    let onSaved: (Int64) -> Void
    @Environment(TrackerStore.self) private var store

    var body: some View {
        DocumentEditForm(
            original: documentId.flatMap(store.document),
            attachments: documentId.map { store.attachments(.document, $0) } ?? [],
            onSaved: onSaved
        )
    }
}

private struct DocumentForm: Equatable {
    var title = ""
    var issuer = ""
    var reference = ""
    var issuedOn: Day?
    var expiresOn: Day?
    var notes = ""

    init(_ document: Document?) {
        guard let document else { return }
        title = document.title
        issuer = document.issuer
        reference = document.reference
        issuedOn = document.issuedOn
        expiresOn = document.expiresOn
        notes = document.notes
    }
}

private struct DocumentEditForm: View {
    let original: Document?
    let onSaved: (Int64) -> Void
    private let initial: DocumentForm
    @State private var form: DocumentForm
    @State private var attachments: AttachmentDraft
    @State private var showErrors = false
    @State private var confirmDiscard = false
    @State private var errorMessage: String?
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(original: Document?, attachments: [Attachment], onSaved: @escaping (Int64) -> Void) {
        self.original = original
        self.onSaved = onSaved
        initial = DocumentForm(original)
        _form = State(initialValue: initial)
        _attachments = State(initialValue: AttachmentDraft(existing: attachments))
    }

    private var hasChanges: Bool { form != initial || attachments.hasChanges }

    var body: some View {
        NavigationStack {
            TrackerForm {
                Section(overline: "Details") {
                    FormTextField("Name", text: $form.title, prompt: "Required")
                        .textInputAutocapitalization(.words)
                    if showErrors && form.title.trimmingCharacters(in: .whitespaces).isEmpty {
                        FieldError(text: String(localized: "Required"))
                    }
                    FormTextField("Issued by", text: $form.issuer)
                    FormTextField("Number", text: $form.reference)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    OptionalDateRow(title: String(localized: "Issue date"), selection: $form.issuedOn)
                    OptionalDateRow(title: String(localized: "Expiry date"), selection: $form.expiresOn)
                } header: {
                    Overline("Dates")
                } footer: {
                    if let issued = form.issuedOn, let expires = form.expiresOn, expires < issued {
                        Text("This is before the issue date").foregroundStyle(Color.trackerSoon)
                    }
                }
                Section(overline: "Notes") {
                    NotesField(text: $form.notes)
                }
                AttachmentEditorSection(title: "Scans and files", draft: $attachments)
            }
            .navigationTitle(original == nil ? "New document" : "Edit document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditToolbar(hasChanges: hasChanges, confirmDiscard: $confirmDiscard, onDiscard: discard, onSave: save)
            }
            .interactiveDismissDisabled(hasChanges)
            .errorAlert($errorMessage)
        }
    }

    private func discard() {
        attachments.discard(store: store.attachmentStore)
        dismiss()
    }

    private func save() {
        showErrors = true
        let title = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var document = original ?? Document(title: title)
        document.title = title
        document.issuer = form.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        document.reference = form.reference.trimmingCharacters(in: .whitespacesAndNewlines)
        document.issuedOn = form.issuedOn
        document.expiresOn = form.expiresOn
        document.notes = form.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let id = try store.saveDocument(document, added: attachments.added, removed: attachments.removed)
            dismiss()
            Haptics.success()
            onSaved(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
