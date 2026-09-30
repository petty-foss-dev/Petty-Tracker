import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import EnveKeep

struct TextLayoutTests {
    private func fragment(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.3, height: CGFloat = 0.03) -> TextLayout.Fragment {
        TextLayout.Fragment(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func joinsColumnsOnTheSameRowTopToBottom() {
        let lines = TextLayout.lines([
            fragment("4.49", x: 0.8, y: 0.702, width: 0.1),
            fragment("TOTAL", x: 0.05, y: 0.5),
            fragment("MILK", x: 0.05, y: 0.7),
            fragment("STORE", x: 0.3, y: 0.9),
            fragment("4.49", x: 0.8, y: 0.495, width: 0.1),
        ])
        #expect(lines == ["STORE", "MILK 4.49", "TOTAL 4.49"])
    }

    @Test func keepsCloseButSeparateRowsApart() {
        let lines = TextLayout.lines([
            fragment("SUBTOTAL", x: 0.05, y: 0.50),
            fragment("TAX", x: 0.05, y: 0.46),
            fragment("1.00", x: 0.8, y: 0.461, width: 0.1),
            fragment("9.00", x: 0.8, y: 0.501, width: 0.1),
        ])
        #expect(lines == ["SUBTOTAL 9.00", "TAX 1.00"])
    }
}

/// Tests real Vision recognition without depending on exact OS-specific wording.
struct TextRecognizerTests {
    private func renderReceipt() -> CGImage {
        let size = CGSize(width: 1200, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let font = UIFont.monospacedSystemFont(ofSize: 56, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            let rows = [("CORNER CAFE", nil), ("COFFEE", "3.50"), ("MUFFIN", "2.25"), ("TOTAL", "5.75")] as [(String, String?)]
            for (index, row) in rows.enumerated() {
                let y = 80 + CGFloat(index) * 180
                (row.0 as NSString).draw(at: CGPoint(x: 80, y: y), withAttributes: attributes)
                if let price = row.1 {
                    (price as NSString).draw(at: CGPoint(x: 880, y: y), withAttributes: attributes)
                }
            }
        }
        return image.cgImage!
    }

    @Test func recognizesRenderedReceiptRows() throws {
        let page = try TextRecognizer.recognizeText(in: renderReceipt())
        let text = page.text
        // Clean printed text must not be reported as hard to read.
        #expect(try #require(page.confidence) >= ReceiptReview.uncertainConfidence)
        let lines = text.components(separatedBy: .newlines).map { $0.uppercased() }

        #expect(lines.contains { $0.contains("COFFEE") && $0.contains("3.50") })
        #expect(lines.contains { $0.contains("TOTAL") && $0.contains("5.75") })

        let parsed = ReceiptParser.parse(text, today: day("2026-09-29"), locale: Locale(identifier: "en_US"), defaultCurrency: "USD")
        #expect(parsed.total == Decimal(string: "5.75"))
        #expect(parsed.items.count == 2)
    }
}
