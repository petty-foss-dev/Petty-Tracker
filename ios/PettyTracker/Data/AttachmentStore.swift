import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Imported files are copied under random names; only temporary, user-named links leave the store.
struct AttachmentStore: Sendable {
    let directory: URL

    func url(for fileName: String) -> URL { directory.appending(path: fileName) }

    /// Copies a user-picked file, which may be security scoped or still downloading from a file provider.
    func importFile(at source: URL) async throws -> Attachment {
        try await Task.detached(priority: .userInitiated) { [self] in
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }

            let type = (try? source.resourceValues(forKeys: [.contentTypeKey]).contentType)
                ?? UTType(filenameExtension: source.pathExtension)
            let target = url(for: newFileName(extension: Self.fileExtension(for: source.pathExtension, type: type)))
            do {
                try Self.coordinatedRead(source) { try FileManager.default.copyItem(at: $0, to: target) }
            } catch {
                try? FileManager.default.removeItem(at: target)
                throw error
            }
            return try attachment(for: target, displayName: source.lastPathComponent, type: type)
        }.value
    }

    /// Reads a user-picked image file and stores it as JPEG, like a photo.
    func importImage(at source: URL) async throws -> Attachment {
        let data = try await Task.detached(priority: .userInitiated) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            var data = Data()
            try Self.coordinatedRead(source) { data = try Data(contentsOf: $0) }
            return data
        }.value
        let name = source.deletingPathExtension().lastPathComponent + ".jpg"
        return try await importPhoto(data, displayName: name)
    }

    /// Stores an image as one JPEG page, or renders each page of a PDF to JPEG so Vision can read it.
    func importReceiptPages(at source: URL) async throws -> [Attachment] {
        let type = (try? source.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: source.pathExtension)
        guard type?.conforms(to: .pdf) == true else { return [try await importImage(at: source)] }
        return try await importPDFPages(at: source)
    }

    private func importPDFPages(at source: URL) async throws -> [Attachment] {
        try await Task.detached(priority: .userInitiated) { [self] in
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let name = source.lastPathComponent
            let baseName = source.deletingPathExtension().lastPathComponent
            var pages: [Attachment] = []
            do {
                try Self.coordinatedRead(source) { readable in
                    guard let document = CGPDFDocument(readable as CFURL), document.numberOfPages > 0 else {
                        throw PDFImportError.unreadable(name)
                    }
                    guard document.isUnlocked else { throw PDFImportError.locked(name) }
                    guard document.numberOfPages <= PDFImportError.maxPages else { throw PDFImportError.tooManyPages(name) }
                    for number in 1...document.numberOfPages {
                        try autoreleasepool {
                            guard let page = document.page(at: number) else { throw PDFImportError.unreadable(name) }
                            let target = url(for: newFileName(extension: "jpg"))
                            try Self.renderJPEG(page).write(to: target, options: .completeFileProtectionUntilFirstUserAuthentication)
                            let displayName = document.numberOfPages == 1 ? "\(baseName).jpg" : "\(baseName) page \(number).jpg"
                            pages.append(try attachment(for: target, displayName: displayName, type: .jpeg))
                        }
                    }
                }
            } catch {
                delete(pages.map(\.fileName))
                throw error
            }
            return pages
        }.value
    }

    /// Renders at 200 dpi, capped at the size text recognition reads and at about 64 MB of bitmap.
    private static func renderJPEG(_ page: CGPDFPage) throws -> Data {
        let box = page.getBoxRect(.cropBox)
        let size = Int(page.rotationAngle).isMultiple(of: 180) ? box.size : CGSize(width: box.height, height: box.width)
        guard size.width >= 1, size.height >= 1 else { throw CocoaError(.fileReadCorruptFile) }
        let scale = min(200 / 72, 4096 / max(size.width, size.height), (16_000_000 / (size.width * size.height)).squareRoot())
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)

        let output = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
    }

    /// Stores photos as JPEG so they open everywhere, including older Android devices without HEIC support.
    func importPhoto(_ data: Data, displayName: String? = nil) async throws -> Attachment {
        try await Task.detached(priority: .userInitiated) { [self] in
            let jpeg = try Self.jpegData(from: data)
            let c = Calendar.gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second], from: .now)
            let name = displayName ?? String(
                format: "Photo %04d-%02d-%02d %02d%02d%02d.jpg", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!
            )
            let target = url(for: newFileName(extension: "jpg"))
            try jpeg.write(to: target, options: .completeFileProtectionUntilFirstUserAuthentication)
            return try attachment(for: target, displayName: name, type: .jpeg)
        }.value
    }

    private static func coordinatedRead(_ source: URL, _ read: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinatorError) { readable in
            do {
                try read(readable)
            } catch {
                readError = error
            }
        }
        if let error = coordinatorError ?? readError { throw error }
    }

    private static func jpegData(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw CocoaError(.fileReadCorruptFile) }
        if CGImageSourceGetType(source) as String? == UTType.jpeg.identifier { return data }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImageFromSource(
            destination, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
    }

    /// Hex SHA-256 of a stored file's bytes.
    func digest(of fileName: String) async throws -> String {
        let file = url(for: fileName)
        return try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.value
    }

    func delete(_ fileNames: [String]) {
        for name in fileNames {
            try? FileManager.default.removeItem(at: url(for: name))
        }
    }

    /// Removes files left behind by abandoned edits or interrupted imports.
    func deleteOrphans(referenced: Set<String>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        delete(names.filter { !referenced.contains($0) })
    }

    /// A temporary hard link named after the original file, so previews and shares show a meaningful name.
    func shareableURL(for attachment: Attachment) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "shared/\(attachment.fileName)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appending(path: Self.safeDisplayName(attachment.displayName, fallback: attachment.fileName))
        do {
            try FileManager.default.linkItem(at: url(for: attachment.fileName), to: link)
        } catch {
            try FileManager.default.copyItem(at: url(for: attachment.fileName), to: link)
        }
        return link
    }

    static func safeDisplayName(_ name: String, fallback: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:").union(.controlCharacters))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(120))
    }

    private func attachment(for file: URL, displayName: String, type: UTType?) throws -> Attachment {
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64 ?? 0
        return Attachment(
            ownerType: .product,
            ownerId: 0,
            displayName: displayName,
            mimeType: type?.preferredMIMEType ?? "application/octet-stream",
            fileName: file.lastPathComponent,
            sizeBytes: size
        )
    }

    private func newFileName(extension ext: String?) -> String {
        UUID().uuidString.lowercased() + (ext.map { ".\($0)" } ?? "")
    }

    private static func fileExtension(for original: String, type: UTType?) -> String? {
        if original.wholeMatch(of: /[A-Za-z0-9]{1,10}/) != nil { return original.lowercased() }
        return type?.preferredFilenameExtension
    }
}

enum PDFImportError: LocalizedError {
    static let maxPages = 20

    case unreadable(String)
    case locked(String)
    case tooManyPages(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): String(localized: "“\(name)” could not be read. It may be damaged or not a PDF.")
        case .locked(let name): String(localized: "“\(name)” is password protected.")
        case .tooManyPages(let name): String(localized: "“\(name)” has more than \(Self.maxPages) pages.")
        }
    }
}
