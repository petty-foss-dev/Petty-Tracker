import SwiftUI

struct DocumentDetailView: View {
    let documentId: Int64
    @Environment(KeepStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editor: Editor?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var openedAttachment: OpenedAttachment?

    var body: some View {
        if let document = store.document(documentId) {
            content(document)
        } else {
            ContentUnavailableView("Document not found", systemImage: RecordKind.document.symbol)
        }
    }

    private func content(_ document: Document) -> some View {
        let today = store.today
        let status = deadlineStatus(document.expiresOn, today: today, leadDays: store.settings.documentLeadDays)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        StatusBadge(text: badgeText(status), status: status)
                        Spacer()
                        if let expires = document.expiresOn {
                            Text(Formats.date(expires)).foregroundStyle(.secondary)
                        }
                    }
                    if let expires = document.expiresOn {
                        Text(Formats.deadline(.document, days: today.days(until: expires)))
                            .font(.title3.weight(.semibold))
                    }
                }
                .padding(.vertical, 4)
            }
            if !document.issuer.isEmpty || !document.reference.isEmpty || document.issuedOn != nil || document.expiresOn != nil {
                Section("Details") {
                    DetailField("Issued by", document.issuer)
                    DetailField("Document number", document.reference, monospaced: true)
                    DetailField("Issue date", document.issuedOn.map(Formats.date) ?? "")
                    DetailField("Expiry date", document.expiresOn.map(Formats.date) ?? "")
                }
            }
            if !document.notes.isEmpty {
                Section("Notes") {
                    Text(document.notes).textSelection(.enabled)
                }
            }
            Section("Scans and files") {
                AttachmentGallery(
                    attachments: store.attachments(.document, documentId),
                    emptyText: "No scans or files. Edit the document to add them.",
                    opened: $openedAttachment,
                    errorMessage: $errorMessage
                )
            }
            Section {
                Button("Delete document", role: .destructive) { confirmDelete = true }
            }
        }
        .keepListStyle()
        .attachmentPresenter($openedAttachment)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editor = .document(documentId) }
        }
        .editorSheet($editor)
        .confirmationDialog("Delete \(document.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do {
                    try store.deleteDocument(documentId)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("The document and its scans will be removed from this device.")
        }
        .errorAlert($errorMessage)
    }

    private func badgeText(_ status: DeadlineStatus) -> String {
        switch status {
        case .none: String(localized: "No expiry date")
        case .ok: String(localized: "Valid")
        case .soon: String(localized: "Expiring soon")
        case .today: String(localized: "Expires today")
        case .past: String(localized: "Expired")
        }
    }
}
