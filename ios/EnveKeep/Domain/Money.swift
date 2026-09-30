import Foundation

enum Money {
    /// Accepts either '.' or ',' as the decimal separator, with optional grouping.
    static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let raw = text.filter { !$0.isWhitespace && $0 != "'" }
        guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else {
            return nil
        }
        let lastDot = raw.lastIndex(of: ".")
        let lastComma = raw.lastIndex(of: ",")
        let normalized: String
        if let lastDot, let lastComma {
            normalized = lastDot > lastComma
                ? raw.replacingOccurrences(of: ",", with: "")
                : raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if let separatorIndex = lastDot ?? lastComma {
            let separator = raw[separatorIndex]
            let occurrences = raw.filter { $0 == separator }.count
            let decimals = raw.distance(from: separatorIndex, to: raw.endIndex) - 1
            let localDecimal = locale.decimalSeparator ?? "."
            let isDecimal = occurrences == 1 && (String(separator) == localDecimal || decimals != 3)
            normalized = isDecimal
                ? raw.replacingOccurrences(of: String(separator), with: ".")
                : raw.replacingOccurrences(of: String(separator), with: "")
        } else {
            normalized = raw
        }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }), (parts.count == 1 || parts[1].count <= 4) else {
            return nil
        }
        return AmountCoding.parse(normalized)
    }

    /// Like `parse`, but allows a leading minus sign for discounts and refunds.
    static func parseSigned(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let sign = trimmed.first, "-−".contains(sign) else { return parse(trimmed, locale: locale) }
        return parse(String(trimmed.dropFirst()), locale: locale).map { -$0 }
    }

    static func format(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }

    static func formatForInput(_ amount: Decimal) -> String {
        amount.formatted(.number.grouping(.never).precision(.fractionLength(0...4)))
    }

    static let currencies: [String] = Set(Locale.Currency.isoCurrencies.map(\.identifier)).sorted()

    static func isValidCurrency(_ code: String) -> Bool { currencies.contains(code) }

    static func currencyName(_ code: String) -> String? {
        Locale.current.localizedString(forCurrencyCode: code)
    }
}
