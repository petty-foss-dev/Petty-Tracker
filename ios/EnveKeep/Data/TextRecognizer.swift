import CoreGraphics
import Foundation
import ImageIO
import Vision

struct RecognizedPage: Sendable {
    let text: String
    /// Mean of Vision's top-candidate confidences, or nil when nothing was recognized.
    let confidence: Double?
}

/// On-device text recognition with Apple Vision. Results can contain mistakes, especially for handwriting.
enum TextRecognizer {
    private static let maxPixelSize = 4096

    static func recognizeText(inImageAt url: URL) async throws -> RecognizedPage {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  ] as CFDictionary)
            else { throw CocoaError(.fileReadCorruptFile) }
            return try recognizeText(in: image)
        }.value
    }

    static func recognizeText(in image: CGImage) throws -> RecognizedPage {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let candidates = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { (candidate: $0, box: observation.boundingBox) }
        }
        let fragments = candidates.map { TextLayout.Fragment(text: $0.candidate.string, box: $0.box) }
        let confidence = candidates.isEmpty
            ? nil
            : candidates.map { Double($0.candidate.confidence) }.reduce(0, +) / Double(candidates.count)
        return RecognizedPage(text: TextLayout.lines(fragments).joined(separator: "\n"), confidence: confidence)
    }
}

/// Joins Vision's separate description and price observations into rows.
enum TextLayout {
    struct Fragment: Sendable {
        let text: String
        /// Normalized coordinates with the origin at the bottom left, as Vision reports them.
        let box: CGRect
    }

    static func lines(_ fragments: [Fragment]) -> [String] {
        var rows: [[Fragment]] = []
        for fragment in fragments.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let index = rows.firstIndex(where: { sharesRow(fragment, $0) }) {
                rows[index].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows
            .sorted { midY($0) > midY($1) }
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }

    private static func sharesRow(_ fragment: Fragment, _ row: [Fragment]) -> Bool {
        let height = row.map(\.box.height).reduce(0, +) / CGFloat(row.count)
        let overlapsHorizontally = row.contains { $0.box.minX < fragment.box.maxX && fragment.box.minX < $0.box.maxX }
        return !overlapsHorizontally && abs(fragment.box.midY - midY(row)) < min(height, fragment.box.height) / 2
    }

    private static func midY(_ row: [Fragment]) -> CGFloat {
        row.map(\.box.midY).reduce(0, +) / CGFloat(row.count)
    }
}
