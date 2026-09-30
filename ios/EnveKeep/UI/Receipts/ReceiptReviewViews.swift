import SwiftUI

extension ReviewFlag.Kind {
    var otherReceiptId: Int64? {
        switch self {
        case .sameScan(let id), .possibleDuplicate(let id): id
        default: nil
        }
    }
}

struct ReviewFlagRow: View {
    let flag: ReviewFlag
    let currency: String
    @Environment(KeepStore.self) private var store

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.keepSoon)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch flag.kind {
        case .missingDate, .missingTotal: "questionmark.circle"
        case .noText, .uncertainText: "eye.trianglebadge.exclamationmark"
        case .itemsDontMatchSubtotal, .totalDoesntAddUp: "plusminus.circle"
        case .sameScan, .possibleDuplicate: "doc.on.doc"
        }
    }

    private var title: String {
        switch flag.kind {
        case .missingDate: String(localized: "No purchase date found")
        case .missingTotal: String(localized: "No total found")
        case .noText(let page, _): String(localized: "No text found on page \(page)")
        case .uncertainText(let page, _, _): String(localized: "Page \(page) was hard to read")
        case .itemsDontMatchSubtotal: String(localized: "Items don't match the subtotal")
        case .totalDoesntAddUp: String(localized: "Total doesn't add up")
        case .sameScan: String(localized: "Same scan as another receipt")
        case .possibleDuplicate: String(localized: "Possible duplicate")
        }
    }

    private var detail: String {
        let money = { Money.format($0, currency: currency) }
        switch flag.kind {
        case .missingDate:
            return String(localized: "The scan didn't clearly show a date. Add it if the receipt has one.")
        case .missingTotal:
            return String(localized: "The scan didn't clearly show a total. Enter it from the receipt.")
        case .noText:
            return String(localized: "Text recognition found nothing on this page. Check the image and enter its details manually.")
        case .uncertainText(_, _, let confidence):
            let percent = confidence.formatted(.percent.precision(.fractionLength(0)))
            return String(localized: "Text recognition was \(percent) confident on this page. Compare the fields with the scan.")
        case .itemsDontMatchSubtotal(let sum, let subtotal):
            return String(localized: "Items add up to \(money(sum)), but the subtotal is \(money(subtotal)). An item may be missing or misread.")
        case .totalDoesntAddUp(let expected, let total):
            return String(localized: "Subtotal, tax and tip come to \(money(expected)), but the total is \(money(total)).")
        case .sameScan(let id):
            return String(localized: "An identical page image is saved with \(describe(id)).")
        case .possibleDuplicate(let id):
            return String(localized: "\(describe(id)) has the same merchant, date and total.")
        }
    }

    private func describe(_ id: Int64) -> String {
        guard let other = store.receipt(id) else { return String(localized: "another receipt") }
        return [other.merchant, other.purchaseDate.map(Formats.date)].compactMap { $0 }.joined(separator: ", ")
    }
}
