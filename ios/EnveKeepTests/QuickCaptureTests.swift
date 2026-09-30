import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import EnveKeep

private func writeFile(_ name: String, _ text: String, in directory: URL) throws -> URL {
    let url = directory.appending(path: name)
    try Data(text.utf8).write(to: url)
    return url
}

private func share(_ names: [String], to inbox: SharedInbox, from directory: URL) throws {
    let batch = try inbox.beginBatch()
    for (index, name) in names.enumerated() {
        try batch.add(try writeFile(name, name, in: directory), index: index)
    }
    try batch.commit()
}

struct SharedInboxTests {
    @Test func stagedFilesStayHiddenUntilCommitted() throws {
        let directory = try temporaryDirectory()
        let inbox = SharedInbox(root: directory.appending(path: "Inbox"))
        let batch = try inbox.beginBatch()
        try batch.add(try writeFile("Till.jpeg", "first", in: directory), index: 0)
        try batch.add(try writeFile("Invoice.pdf", "second", in: directory), index: 1)

        #expect(inbox.items().isEmpty)

        try batch.commit()
        let reopened = SharedInbox(root: inbox.root).items()
        try #require(reopened.map(\.file.lastPathComponent) == ["Till.jpeg", "Invoice.pdf"])
        #expect(try String(contentsOf: reopened[1].file, encoding: .utf8) == "second")
    }

    @Test func addsFileExtensionWhenShareProviderUsesTemporaryName() throws {
        let directory = try temporaryDirectory()
        let inbox = SharedInbox(root: directory.appending(path: "Inbox"))
        let batch = try inbox.beginBatch()
        try batch.add(try writeFile("temporary", "image bytes", in: directory), index: 0, type: .jpeg)
        try batch.commit()

        #expect(inbox.items().map(\.file.pathExtension) == ["jpeg"])
    }

    @Test func consumesItemsInShareOrder() async throws {
        let directory = try temporaryDirectory()
        let inbox = SharedInbox(root: directory.appending(path: "Inbox"))
        try share(["a.jpg", "b.jpg"], to: inbox, from: directory)
        try await Task.sleep(for: .milliseconds(5))
        try share(["c.pdf"], to: inbox, from: directory)

        #expect(inbox.items().map(\.file.lastPathComponent) == ["a.jpg", "b.jpg", "c.pdf"])

        let first = inbox.items()[0]
        inbox.remove(first)
        #expect(inbox.items().map(\.file.lastPathComponent) == ["b.jpg", "c.pdf"])
        #expect(!FileManager.default.fileExists(atPath: first.file.path))

        inbox.remove(inbox.items()[0])
        let pending = inbox.root.appending(path: "Pending")
        #expect(try FileManager.default.contentsOfDirectory(atPath: pending.path).count == 1)
    }

    @Test func discardedAndAbandonedSharesNeverAppear() throws {
        let directory = try temporaryDirectory()
        let inbox = SharedInbox(root: directory.appending(path: "Inbox"))
        let discarded = try inbox.beginBatch()
        try discarded.add(try writeFile("a.jpg", "a", in: directory), index: 0)
        discarded.discard()
        let abandoned = try inbox.beginBatch()
        try abandoned.add(try writeFile("b.jpg", "b", in: directory), index: 0)

        inbox.removeAbandonedBatches(olderThan: .now.addingTimeInterval(60))

        #expect(inbox.items().isEmpty)
        let staging = inbox.root.appending(path: "Staging")
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    @Test func prefersPDFThenImageRepresentations() {
        #expect(SharedInbox.receiptType(in: ["public.url", "public.jpeg"]) == .jpeg)
        #expect(SharedInbox.receiptType(in: ["public.heic", "com.adobe.pdf"]) == .pdf)
        #expect(SharedInbox.receiptType(in: ["public.movie", "public.plain-text"]) == nil)
    }
}

@MainActor
struct QuickCaptureTests {
    private func defaults() -> UserDefaults {
        let name = "enve-keep-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func scanRequestSurvivesRelaunchUntilConsumed() {
        let defaults = defaults()
        QuickCapture(inbox: nil, defaults: defaults).requestScan()

        let relaunched = QuickCapture(inbox: nil, defaults: defaults)
        #expect(relaunched.needsAttention)
        #expect(relaunched.consumeScanRequest())
        #expect(!relaunched.consumeScanRequest())
        #expect(!QuickCapture(inbox: nil, defaults: defaults).scanRequested)
    }

    @Test func ignoresStaleScanRequests() {
        let defaults = defaults()
        defaults.set(Date.now.addingTimeInterval(-3600), forKey: "quickCapture.scanRequestedAt")

        let capture = QuickCapture(inbox: nil, defaults: defaults)

        #expect(!capture.needsAttention)
        #expect(!capture.consumeScanRequest())
    }

    @Test func postponedFilesWaitAndFinishedFilesAreDeleted() throws {
        let directory = try temporaryDirectory()
        let inbox = SharedInbox(root: directory.appending(path: "Inbox"))
        let defaults = defaults()
        let capture = QuickCapture(inbox: inbox, defaults: defaults)
        #expect(!capture.needsAttention)

        try share(["a.jpg", "b.pdf"], to: inbox, from: directory)
        capture.refresh()
        let first = try #require(capture.nextAutomaticItem)
        #expect(first.file.lastPathComponent == "a.jpg")

        capture.postpone(first)
        #expect(capture.nextAutomaticItem?.file.lastPathComponent == "b.pdf")
        capture.postpone(try #require(capture.nextAutomaticItem))
        #expect(!capture.needsAttention)
        #expect(capture.sharedItems.count == 2)

        let relaunched = QuickCapture(inbox: inbox, defaults: defaults)
        #expect(relaunched.nextAutomaticItem == first)
        relaunched.finish(first)
        #expect(relaunched.sharedItems.map(\.file.lastPathComponent) == ["b.pdf"])
        #expect(inbox.items().map(\.file.lastPathComponent) == ["b.pdf"])
    }
}

struct PDFPageImportTests {
    private func makePDF(named name: String, pages: [String], in directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 400)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: url) { context in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .semibold), .foregroundColor: UIColor.black,
            ]
            for text in pages {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 24, y: 40), withAttributes: attributes)
            }
        }
        return url
    }

    private func attachmentStore(in directory: URL) throws -> AttachmentStore {
        let store = AttachmentStore(directory: directory.appending(path: "attachments"))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        return store
    }

    private func storedFiles(_ store: AttachmentStore) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
    }

    @Test func rendersEachPDFPageAsReadableJPEG() async throws {
        let directory = try temporaryDirectory()
        let store = try attachmentStore(in: directory)
        let pdf = try makePDF(named: "Lunch.pdf", pages: ["TOTAL 5.75", "THANK YOU"], in: directory)

        let pages = try await store.importReceiptPages(at: pdf)

        #expect(pages.map(\.displayName) == ["Lunch page 1.jpg", "Lunch page 2.jpg"])
        #expect(pages.allSatisfy { $0.mimeType == "image/jpeg" && $0.fileName.hasSuffix(".jpg") })
        let first = store.url(for: pages[0].fileName)
        #expect(try Data(contentsOf: first).starts(with: [0xFF, 0xD8]))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(first as CFURL, nil)!, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 833)

        let recognized = try await TextRecognizer.recognizeText(inImageAt: first)
        #expect(recognized.text.uppercased().contains("TOTAL"))
    }

    @Test func singlePagePDFKeepsItsName() async throws {
        let directory = try temporaryDirectory()
        let store = try attachmentStore(in: directory)
        let pdf = try makePDF(named: "Fuel.pdf", pages: ["TOTAL 40.00"], in: directory)

        let pages = try await store.importReceiptPages(at: pdf)

        #expect(pages.map(\.displayName) == ["Fuel.jpg"])
    }

    @Test func rejectsDamagedAndOversizedPDFsWithoutLeavingFiles() async throws {
        let directory = try temporaryDirectory()
        let store = try attachmentStore(in: directory)
        let broken = try writeFile("Broken.pdf", "not a pdf", in: directory)
        let long = try makePDF(named: "Long.pdf", pages: Array(repeating: "PAGE", count: PDFImportError.maxPages + 1), in: directory)

        await #expect(throws: PDFImportError.self) { try await store.importReceiptPages(at: broken) }
        await #expect(throws: PDFImportError.self) { try await store.importReceiptPages(at: long) }
        #expect(try storedFiles(store).isEmpty)
    }

    @Test func fileCaptureMixesImagesAndPDFsAndReportsFailures() async throws {
        let directory = try temporaryDirectory()
        let store = try attachmentStore(in: directory)
        let pdf = try makePDF(named: "Invoice.pdf", pages: ["ONE", "TWO"], in: directory)
        let png = directory.appending(path: "Slip.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        try image.pngData()!.write(to: png)
        let broken = try writeFile("Broken.pdf", "not a pdf", in: directory)

        let result = await ReceiptCapture.files([pdf, png, broken]).importPages(into: store)

        #expect(result.pages.map(\.displayName) == ["Invoice page 1.jpg", "Invoice page 2.jpg", "Slip.jpg"])
        #expect(result.failed == 1)
        #expect(result.reasons == [PDFImportError.unreadable("Broken.pdf").localizedDescription])
        #expect(try storedFiles(store).count == 3)
    }
}
