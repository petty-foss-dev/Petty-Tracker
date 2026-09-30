import ImageIO
import UIKit

/// A printable warranty claim: a summary of the product followed by its linked receipt's scanned pages.
struct ClaimPacket: Sendable {
    let product: Product
    let receipt: Receipt?
    /// Page image files of the linked receipt, in order.
    let receiptPages: [URL]
    let today: Day

    private static let margin: CGFloat = 54
    private static let maxImagePixels = 2400

    private var pageSize: CGSize {
        Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
    }

    var title: String { String(localized: "Warranty claim – \(product.name)") }

    func write() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "claim", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: AttachmentStore.safeDisplayName(title, fallback: "Warranty claim") + ".pdf")
        try render().write(to: url, options: .atomic)
        return url
    }

    func render() -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let content = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Enve Keep",
        ]

        // TextKit 1 lays the summary out across as many pages as it needs.
        let storage = NSTextStorage(attributedString: summary())
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: CGSize(width: content.width, height: content.height - 24))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
        } while NSMaxRange(layout.glyphRange(for: containers.last!)) < layout.numberOfGlyphs

        let pageCount = containers.count + receiptPages.count
        return UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            var pageNumber = 0
            func beginPage() {
                context.beginPage()
                pageNumber += 1
                let footer = String(localized: "\(product.name) · page \(pageNumber) of \(pageCount)")
                NSAttributedString(string: footer, attributes: Self.captionAttributes)
                    .draw(at: CGPoint(x: content.minX, y: bounds.maxY - Self.margin / 2 - 10))
            }
            for container in containers {
                beginPage()
                layout.drawGlyphs(forGlyphRange: layout.glyphRange(for: container), at: content.origin)
            }
            for (index, url) in receiptPages.enumerated() {
                beginPage()
                let caption = String(localized: "Receipt from \(receipt?.merchant ?? "") – page \(index + 1) of \(receiptPages.count)")
                NSAttributedString(string: caption, attributes: Self.labelAttributes).draw(at: content.origin)
                let area = CGRect(x: content.minX, y: content.minY + 24, width: content.width, height: content.height - 48)
                if let image = Self.loadImage(url) {
                    UIImage(cgImage: image).draw(in: Self.aspectFit(CGSize(width: image.width, height: image.height), in: area))
                } else {
                    NSAttributedString(string: String(localized: "This page could not be read."), attributes: Self.valueAttributes)
                        .draw(at: area.origin)
                }
            }
        }
    }

    private func summary() -> NSAttributedString {
        let text = NSMutableAttributedString()
        func append(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
            text.append(NSAttributedString(string: string + "\n", attributes: attributes))
        }
        func heading(_ string: String) {
            append(string, Self.headingAttributes)
        }
        func row(_ label: String, _ value: String, monospaced: Bool = false) {
            guard !value.isEmpty else { return }
            let line = NSMutableAttributedString(string: label + "\t", attributes: Self.rowAttributes(Self.labelFont))
            line.append(NSAttributedString(
                string: value + "\n",
                attributes: Self.rowAttributes(monospaced ? Self.monospacedFont : Self.valueFont)
            ))
            text.append(line)
        }
        let money = { (amount: Decimal, currency: String) in "\(Money.format(amount, currency: currency)) (\(currency))" }

        append(String(localized: "Warranty claim"), Self.labelAttributes)
        append(product.name, Self.titleAttributes)
        append(String(localized: "Prepared \(Formats.date(today)) with Enve Keep"), Self.captionAttributes)

        heading(String(localized: "Product"))
        row(String(localized: "Name"), product.name)
        row(String(localized: "Brand"), product.brand)
        row(String(localized: "Model"), product.model, monospaced: true)
        row(String(localized: "Serial number"), product.serialNumber, monospaced: true)

        heading(String(localized: "Purchase"))
        row(String(localized: "Purchase date"), product.purchaseDate.map(Formats.date) ?? String(localized: "Not recorded"))
        row(String(localized: "Retailer"), product.retailer.isEmpty ? String(localized: "Not recorded") : product.retailer)
        row(String(localized: "Price"), product.price.map { money($0, product.currency) } ?? String(localized: "Not recorded"))

        heading(String(localized: "Warranty"))
        if let expires = product.warrantyExpires {
            let days = today.days(until: expires)
            row(String(localized: "Warranty ends"), "\(Formats.date(expires)) (\(Formats.deadline(.warranty, days: days)))")
        } else {
            row(String(localized: "Warranty ends"), String(localized: "Not recorded"))
        }

        heading(String(localized: "Proof of purchase"))
        if let receipt {
            row(String(localized: "Merchant"), receipt.merchant)
            row(String(localized: "Receipt date"), receipt.purchaseDate.map(Formats.date) ?? "")
            row(String(localized: "Receipt total"), receipt.total.map { money($0, receipt.currency) } ?? "")
            row(String(localized: "Scanned pages"), receiptPages.isEmpty
                ? String(localized: "None")
                : String(localized: "\(receiptPages.count) attached after this summary"))
        } else {
            append(String(localized: "No receipt is linked to this product."), Self.rowAttributes(Self.valueFont))
        }

        if !product.notes.isEmpty {
            heading(String(localized: "Notes"))
            append(product.notes, Self.rowAttributes(Self.valueFont))
        }
        return text
    }

    // MARK: - Drawing

    private static var labelFont: UIFont { .systemFont(ofSize: 11, weight: .semibold) }
    private static var valueFont: UIFont { .systemFont(ofSize: 11) }
    private static var monospacedFont: UIFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
    private static let labelColumn: CGFloat = 130

    private static var titleAttributes: [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.black]
    }
    private static var labelAttributes: [NSAttributedString.Key: Any] { [.font: labelFont, .foregroundColor: UIColor.darkGray] }
    private static var valueAttributes: [NSAttributedString.Key: Any] { [.font: valueFont, .foregroundColor: UIColor.black] }
    private static var captionAttributes: [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray]
    }
    private static var headingAttributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 14
        style.paragraphSpacing = 4
        return [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.black, .paragraphStyle: style]
    }

    /// Label and value on one line; wrapped values stay in the value column.
    private static func rowAttributes(_ font: UIFont) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: labelColumn)]
        style.headIndent = labelColumn
        style.paragraphSpacing = 3
        return [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: style]
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImagePixels,
        ] as CFDictionary)
    }

    private static func aspectFit(_ size: CGSize, in area: CGRect) -> CGRect {
        let scale = min(area.width / size.width, area.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: area.midX - fitted.width / 2, y: area.minY, width: fitted.width, height: fitted.height)
    }
}
