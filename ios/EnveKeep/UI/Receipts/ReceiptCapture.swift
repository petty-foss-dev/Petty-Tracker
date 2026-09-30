import PhotosUI
import QuickLookThumbnailing
import SwiftUI
import VisionKit

enum CaptureSource: Hashable {
    case scanner, photos, files
}

/// Page images picked for a receipt, not yet copied into the attachment store.
enum ReceiptCapture: Sendable {
    case scans([UIImage])
    case photos([PhotosPickerItem])
    case files([URL])

    /// Imports every page as JPEG, keeping the pages that succeed.
    func importPages(into store: AttachmentStore) async -> (pages: [Attachment], failed: Int, reasons: [String]) {
        var pages: [Attachment] = []
        var failed = 0
        var reasons: [String] = []
        func add(_ work: () async throws -> [Attachment]?) async {
            do {
                if let added = try await work() { pages += added } else { failed += 1 }
            } catch {
                failed += 1
                if !reasons.contains(error.localizedDescription) { reasons.append(error.localizedDescription) }
            }
        }
        switch self {
        case .scans(let images):
            let stamp = Date.now.formatted(.iso8601.year().month().day())
            for (index, image) in images.enumerated() {
                await add {
                    guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
                    return [try await store.importPhoto(data, displayName: "Scan \(stamp) page \(index + 1).jpg")]
                }
            }
        case .photos(let items):
            for item in items {
                await add {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
                    return [try await store.importPhoto(data)]
                }
            }
        case .files(let urls):
            for url in urls {
                await add { try await store.importReceiptPages(at: url) }
            }
        }
        return (pages, failed, reasons)
    }
}

struct AddPagesMenu<Label: View>: View {
    @Binding var source: CaptureSource?
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            if DocumentScanner.isSupported {
                Button("Scan with camera", systemImage: "doc.viewfinder") { source = .scanner }
            }
            Button("Photo Library", systemImage: "photo.on.rectangle") { source = .photos }
            Button("Choose Files", systemImage: "folder") { source = .files }
        } label: {
            label()
        }
    }
}

extension View {
    /// Presents the scanner or picker for `source` and reports picked pages once it has closed.
    func receiptCapture(
        _ source: Binding<CaptureSource?>,
        errorMessage: Binding<String?>,
        onCapture: @escaping (ReceiptCapture) -> Void
    ) -> some View {
        modifier(ReceiptCaptureModifier(source: source, errorMessage: errorMessage, onCapture: onCapture))
    }
}

private struct ReceiptCaptureModifier: ViewModifier {
    @Binding var source: CaptureSource?
    @Binding var errorMessage: String?
    let onCapture: (ReceiptCapture) -> Void
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var scanned: [UIImage] = []

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: presented(.scanner), onDismiss: deliverScan) {
                DocumentScanner { images in
                    scanned = images
                } onError: { error in
                    errorMessage = String(localized: "The scan could not be completed. \(error.localizedDescription)")
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: presented(.photos),
                selection: $photoItems,
                maxSelectionCount: 10,
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                onCapture(.photos(items))
            }
            .fileImporter(isPresented: presented(.files), allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls) where !urls.isEmpty: onCapture(.files(urls))
                case .success: break
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
    }

    private func presented(_ kind: CaptureSource) -> Binding<Bool> {
        Binding(get: { source == kind }, set: { if !$0 && source == kind { source = nil } })
    }

    private func deliverScan() {
        guard !scanned.isEmpty else { return }
        let images = scanned
        scanned = []
        onCapture(.scans(images))
    }
}

/// VisionKit captures cropped, straightened pages on devices with a camera.
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onError: (Error) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // VisionKit calls the delegate on the main thread but doesn't annotate the protocol.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner

        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan((0..<scan.pageCount).map(scan.imageOfPage(at:)))
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(error)
            parent.dismiss()
        }
    }
}

/// A portrait preview of a scanned page, cropped from the top where the merchant usually is.
struct ReceiptPageThumbnail: View {
    let page: Attachment
    let width: CGFloat
    let height: CGFloat
    @Environment(KeepStore.self) private var store
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height, alignment: .top)
            } else {
                Image(systemName: "doc.text.image")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2)))
        .task(id: page.fileName) {
            let request = QLThumbnailGenerator.Request(
                fileAt: store.attachmentStore.url(for: page.fileName),
                size: CGSize(width: width, height: height * 2),
                scale: scale,
                representationTypes: .thumbnail
            )
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
        }
    }
}
