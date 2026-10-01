import Foundation
import PDFKit
import Testing
import UIKit
@testable import PettyTracker

struct ClaimPacketTests {
    private let product = Product(
        id: 3, name: "Espresso Machine", brand: "Brewco", model: "BX-900", serialNumber: "SN-4242-XY",
        purchaseDate: day("2026-03-01"), retailer: "Kitchen Shop", price: Decimal(string: "499.99"), currency: "EUR",
        warrantyExpires: day("2028-03-01")
    )

    private func jpeg(in directory: URL, _ name: String) throws -> URL {
        let url = directory.appending(path: name)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 800)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 800))
        }
        try image.jpegData(compressionQuality: 0.8)!.write(to: url)
        return url
    }

    @Test func summaryThenOnePagePerReceiptScan() throws {
        let directory = try temporaryDirectory()
        let receipt = Receipt(id: 1, merchant: "Kitchen Shop", purchaseDate: day("2026-03-01"), currency: "EUR",
                              total: Decimal(string: "520.00"), addedOn: day("2026-03-02"))
        let packet = ClaimPacket(
            product: product,
            receipt: receipt,
            receiptPages: [try jpeg(in: directory, "a.jpg"), try jpeg(in: directory, "b.jpg")],
            today: day("2026-09-29")
        )

        let document = try #require(PDFDocument(data: packet.render()))

        #expect(document.pageCount == 3)
        let summary = try #require(document.page(at: 0)?.string)
        for expected in [
            "Espresso Machine", "Brewco", "BX-900", "SN-4242-XY", "Kitchen Shop", "EUR",
            Money.format(Decimal(string: "499.99")!, currency: "EUR"), Formats.date(day("2028-03-01")),
            Formats.date(day("2026-03-01")), Money.format(520, currency: "EUR"),
        ] {
            #expect(summary.contains(expected), "Summary is missing \(expected)")
        }
        #expect(document.page(at: 1)?.string?.contains("page 1 of 2") == true)
        #expect(document.page(at: 2)?.string?.contains("page 2 of 2") == true)
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == packet.title)
    }

    @Test func saysSoWhenNoReceiptIsLinked() throws {
        let packet = ClaimPacket(product: product, receipt: nil, receiptPages: [], today: day("2026-09-29"))
        let document = try #require(PDFDocument(data: packet.render()))

        #expect(document.pageCount == 1)
        #expect(document.page(at: 0)?.string?.contains("No receipt is linked") == true)
    }

    @Test func longNotesFlowOntoMorePagesWithoutLosingText() throws {
        var long = product
        long.notes = (1...200).map { "Note line \($0)." }.joined(separator: "\n")
        let document = try #require(PDFDocument(data: ClaimPacket(product: long, receipt: nil, receiptPages: [], today: day("2026-09-29")).render()))

        #expect(document.pageCount > 1)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        #expect(text.contains("Note line 1."))
        #expect(text.contains("Note line 200."))
    }

    @Test func writesNamedPDFFile() throws {
        let url = try ClaimPacket(product: product, receipt: nil, receiptPages: [], today: day("2026-09-29")).write()
        #expect(url.pathExtension == "pdf")
        #expect(url.lastPathComponent.contains("Espresso Machine"))
        #expect(try Data(contentsOf: url).starts(with: Array("%PDF".utf8)))
    }
}
