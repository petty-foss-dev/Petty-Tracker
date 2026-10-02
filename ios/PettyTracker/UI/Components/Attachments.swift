import PhotosUI
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Pending attachment changes for an edit form. Newly added files are already copied into the
/// store and are deleted again if the edit is discarded.
struct AttachmentDraft {
    var existing: [Attachment] = []
    var added: [Attachment] = []
    var removed: [Attachment] = []

    var visible: [Attachment] { existing + added }
    var hasChanges: Bool { !added.isEmpty || !removed.isEmpty }

    mutating func remove(_ attachment: Attachment, store: AttachmentStore) {
        if let index = added.firstIndex(where: { $0.fileName == attachment.fileName }) {
            added.remove(at: index)
            store.delete([attachment.fileName])
        } else if let index = existing.firstIndex(where: { $0.fileName == attachment.fileName }) {
            removed.append(existing.remove(at: index))
        }
    }

    func discard(store: AttachmentStore) {
        store.delete(added.map(\.fileName))
    }
}

extension AttachmentLabel {
    var title: String {
        switch self {
        case .item: String(localized: "Item photos")
        case .part: String(localized: "Parts")
        case .instructions: String(localized: "Instructions")
        case .productPage: String(localized: "Product page copies")
        case .warranty: String(localized: "Warranty")
        case .other: String(localized: "Other files")
        }
    }

    /// The menu wording for adding a file with this label.
    var addTitle: String {
        switch self {
        case .item: String(localized: "Photo of the item")
        case .part: String(localized: "Part")
        case .instructions: String(localized: "Instructions or manual")
        case .productPage: String(localized: "Copy of the product page")
        case .warranty: String(localized: "Warranty card or terms")
        case .other: String(localized: "Other file")
        }
    }

    var symbol: String {
        switch self {
        case .item: "camera"
        case .part: "puzzlepiece"
        case .instructions: "book.closed"
        case .productPage: "globe"
        case .warranty: "checkmark.shield"
        case .other: "doc"
        }
    }

    static let productLabels: [AttachmentLabel] = [.item, .part, .instructions, .warranty, .productPage, .other]
}

struct AttachmentEditorSection: View {
    let title: LocalizedStringKey
    @Binding var draft: AttachmentDraft
    var labels: [AttachmentLabel] = [.other]
    @Environment(TrackerStore.self) private var store

    var body: some View {
        Section(title) {
            ForEach(draft.visible, id: \.fileName) { attachment in
                HStack {
                    AttachmentThumbnail(attachment: attachment, size: 40)
                    AttachmentNameLabel(attachment: attachment, showsLabel: labels.count > 1)
                    Spacer()
                    Button {
                        draft.remove(attachment, store: store.attachmentStore)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(Color.trackerPast)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Remove \(attachment.displayName)"))
                }
            }
            AttachmentAddMenu(labels: labels) { draft.added += $0 }
        }
    }
}

/// Copies picked files, library photos or camera shots into the attachment store and hands them back,
/// labelled with whichever of `labels` the person chose.
struct AttachmentAddMenu<MenuLabel: View>: View {
    var labels: [AttachmentLabel] = [.other]
    let onAdded: ([Attachment]) -> Void
    /// The menu's face; receives whether files are still being copied in.
    @ViewBuilder let menuLabel: (_ importing: Bool) -> MenuLabel
    @Environment(TrackerStore.self) private var store
    @State private var pendingLabel = AttachmentLabel.other

    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = 0
    @State private var errorMessage: String?

    var body: some View {
        // Presentations hang off this single row; on a Section they would repeat for every row.
        Menu {
            if labels.count == 1 {
                sources(for: labels[0])
            } else {
                ForEach(labels, id: \.self) { label in
                    Menu {
                        sources(for: label)
                    } label: {
                        Label(label.addTitle, systemImage: label.symbol)
                    }
                }
            }
        } label: {
            menuLabel(importing > 0)
        }
        .disabled(importing > 0)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                add { store in
                    var imported: [Attachment] = []
                    for url in urls { imported.append(try await store.importFile(at: url)) }
                    return imported
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            add { store in
                var imported: [Attachment] = []
                for item in items {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    imported.append(try await store.importPhoto(data))
                }
                return imported
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                guard let data = image.jpegData(compressionQuality: 0.85) else { return }
                add { store in [try await store.importPhoto(data)] }
            }
            .ignoresSafeArea()
        }
        .errorAlert($errorMessage)
    }

    @ViewBuilder
    private func sources(for label: AttachmentLabel) -> some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button("Take Photo", systemImage: "camera") {
                pendingLabel = label
                showCamera = true
            }
        }
        Button("Photo Library", systemImage: "photo.on.rectangle") {
            pendingLabel = label
            showPhotos = true
        }
        Button("Choose File", systemImage: "folder") {
            pendingLabel = label
            showFiles = true
        }
    }

    private func add(_ work: @escaping @Sendable (AttachmentStore) async throws -> [Attachment]) {
        let attachmentStore = store.attachmentStore
        let label = pendingLabel
        importing += 1
        Task {
            defer { importing -= 1 }
            do {
                onAdded(try await work(attachmentStore).map { attachment in
                    var labelled = attachment
                    labelled.label = label
                    return labelled
                })
            } catch {
                errorMessage = String(localized: "A file could not be added. \(error.localizedDescription)")
            }
        }
    }
}

extension AttachmentAddMenu where MenuLabel == AnyView {
    /// The standard list-row face: a paperclip label, or progress while files are copied in.
    init(title: LocalizedStringKey = "Add photo or file", labels: [AttachmentLabel] = [.other], onAdded: @escaping ([Attachment]) -> Void) {
        self.init(labels: labels, onAdded: onAdded) { importing in
            AnyView(Group {
                if importing {
                    HStack {
                        ProgressView()
                        Text("Adding…").foregroundStyle(.secondary)
                    }
                } else {
                    Label(title, systemImage: "paperclip")
                }
            })
        }
    }
}

/// Read-only attachment rows for detail screens. The owning list presents previews and shares via
/// `attachmentPresenter`, since presentation modifiers on rows or sections would repeat per row.
struct AttachmentGallery: View {
    let attachments: [Attachment]
    var emptyText: LocalizedStringKey?
    @Binding var opened: OpenedAttachment?
    @Binding var errorMessage: String?
    var onDelete: ((Attachment) -> Void)?
    var onRelabel: ((Attachment, AttachmentLabel) -> Void)?
    @Environment(TrackerStore.self) private var store

    var body: some View {
        if attachments.isEmpty, let emptyText {
            Text(emptyText).foregroundStyle(.secondary)
        }
        ForEach(attachments) { attachment in
            Button {
                open(attachment, share: false)
            } label: {
                HStack {
                    AttachmentThumbnail(attachment: attachment, size: 44)
                    AttachmentNameLabel(attachment: attachment)
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
            .accessibilityHint("Opens a preview")
            .contextMenu {
                Button("Share", systemImage: "square.and.arrow.up") { open(attachment, share: true) }
                if let onRelabel {
                    Picker("Label", selection: Binding(get: { attachment.label }, set: { onRelabel(attachment, $0) })) {
                        ForEach(AttachmentLabel.productLabels, id: \.self) { label in
                            Label(label.title, systemImage: label.symbol).tag(label)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if let onDelete {
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete(attachment) }
                }
            }
            .swipeActions {
                if let onDelete {
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete(attachment) }
                }
                Button("Share", systemImage: "square.and.arrow.up") { open(attachment, share: true) }
                    .tint(Color.trackerAccent)
            }
        }
    }

    private func open(_ attachment: Attachment, share: Bool) {
        do {
            opened = OpenedAttachment(url: try store.attachmentStore.shareableURL(for: attachment), share: share)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct OpenedAttachment: Identifiable {
    let url: URL
    let share: Bool
    var id: URL { url }
}

extension View {
    func attachmentPresenter(_ opened: Binding<OpenedAttachment?>) -> some View {
        quickLookPreview(Binding(
            get: { opened.wrappedValue?.share == false ? opened.wrappedValue?.url : nil },
            set: { if $0 == nil { opened.wrappedValue = nil } }
        ))
        .sheet(item: Binding(
            get: { opened.wrappedValue?.share == true ? opened.wrappedValue : nil },
            set: { if $0 == nil { opened.wrappedValue = nil } }
        )) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }
}

private struct AttachmentNameLabel: View {
    let attachment: Attachment
    var showsLabel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attachment.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(showsLabel ? "\(attachment.label.title) · \(Formats.fileSize(attachment.sizeBytes))" : Formats.fileSize(attachment.sizeBytes))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Quick Look thumbnails kept in memory, so rows scrolled back into view don't render them again.
@MainActor
enum Thumbnails {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func cached(_ url: URL, size: CGSize, scale: CGFloat) -> UIImage? {
        cache.object(forKey: key(url, size, scale))
    }

    static func load(_ url: URL, size: CGSize, scale: CGFloat) async -> UIImage? {
        if let image = cached(url, size: size, scale: scale) { return image }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        guard let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage else { return nil }
        cache.setObject(image, forKey: key(url, size, scale))
        return image
    }

    private static func key(_ url: URL, _ size: CGSize, _ scale: CGFloat) -> NSString {
        "\(url.lastPathComponent)-\(Int(size.width))x\(Int(size.height))@\(Int(scale))" as NSString
    }
}

struct AttachmentThumbnail: View {
    let attachment: Attachment
    let size: CGFloat
    @Environment(TrackerStore.self) private var store
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: attachment.isImage ? "photo" : "doc")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: attachment.fileName) {
            image = await Thumbnails.load(
                store.attachmentStore.url(for: attachment.fileName), size: CGSize(width: size, height: size), scale: scale
            )
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
