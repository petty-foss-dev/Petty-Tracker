import Foundation

/// Draft values read from receipt text. Anything the text doesn't clearly state stays nil.
struct ParsedReceipt: Equatable, Sendable {
    var merchant: String?
    var purchaseDate: Day?
    var currency: String?
    var items: [ReceiptItem] = []
    var subtotal: Decimal?
    var tax: Decimal?
    var tip: Decimal?
    var total: Decimal?
    var purchaseTime: ClockTime?
    var storeAddress: String?
    var storePhone: String?
    var transactionId: String?
    var paymentMethod: String?
    var cardLastFour: String?
    /// Set only on strong evidence, such as a volume with a pump number or a price per gallon.
    var isFuel = false
    var fuelGrade: String?
    var fuelVolume: Decimal?
    var fuelUnit: FuelUnit?
    var fuelUnitPrice: Decimal?
    var pumpNumber: String?
    var odometer: String?
}

/// Reads two-decimal amounts without treating summaries or payment lines as items.
enum ReceiptParser {
    static func parse(_ text: String, today: Day, locale: Locale = .current, defaultCurrency: String) -> ParsedReceipt {
        let lines = text.components(separatedBy: .newlines).map(normalize).filter { !$0.isEmpty }.map(Line.init)
        var result = ParsedReceipt()
        let merchant = merchant(in: lines)
        result.merchant = merchant?.name
        let date = purchaseDate(in: lines.map(\.text), today: today, locale: locale)
        result.purchaseDate = date?.day
        result.currency = currency(in: text, defaultCurrency: defaultCurrency)
        readDetails(lines, merchantLine: merchant?.index, dateLine: date?.line, into: &result)

        var subtotal: Decimal?
        var taxes: [(keyword: String, value: Decimal)] = []
        var taxTotal: Decimal?
        var tips: [Decimal] = []
        var totals: [(value: Decimal, afterTip: Bool)] = []
        var items: [ReceiptItem] = []
        var pendingDescription: String?
        var pendingQuantity: Quantity?

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let kind = classify(line)
            var amount = line.lineAmounts.last?.value
            if amount == nil, kind.isSummary, index + 1 < lines.count, lines[index + 1].isAmountOnly {
                index += 1
                amount = lines[index].lineAmounts.last?.value
            }
            defer { index += 1 }

            switch kind {
            case .ignore:
                pendingDescription = nil
                continue
            case .subtotal:
                if let amount, subtotal == nil { subtotal = amount }
            case .tip:
                if let amount { tips.append(amount) }
            case .tax(let keyword, let isTotal):
                if let amount {
                    if isTotal { taxTotal = amount } else { taxes.append((keyword, amount)) }
                }
            case .total:
                if let amount { totals.append((amount, !tips.isEmpty)) }
            case .item:
                break
            }
            if kind.isSummary {
                pendingDescription = nil
                continue
            }

            let summaryStarted = subtotal != nil || taxTotal != nil || !taxes.isEmpty || !tips.isEmpty
            guard totals.isEmpty, !summaryStarted || line.isDiscount else { continue }

            if let quantity = line.quantity, line.letterCount < 2 {
                if let lineTotal = amount {
                    if let description = pendingDescription {
                        items.append(ReceiptItem(description: description, quantity: quantity.count, amount: lineTotal))
                        pendingDescription = nil
                    } else if let last = items.indices.last, items[last].quantity == nil, items[last].amount == lineTotal {
                        items[last].quantity = quantity.count
                    } else {
                        pendingQuantity = quantity
                    }
                } else if let last = items.indices.last, items[last].quantity == nil, items[last].amount == quantity.lineTotal {
                    items[last].quantity = quantity.count
                } else if let description = pendingDescription {
                    items.append(ReceiptItem(description: description, quantity: quantity.count, amount: quantity.lineTotal))
                    pendingDescription = nil
                } else {
                    pendingQuantity = quantity
                }
                continue
            }

            guard let amount else {
                if line.letterCount >= 2 {
                    if let quantity = line.quantity {
                        items.append(ReceiptItem(description: line.itemDescription, quantity: quantity.count, amount: quantity.lineTotal))
                        pendingDescription = nil
                    } else {
                        pendingDescription = line.itemDescription
                    }
                }
                continue
            }

            if line.letterCount < 2 {
                if let description = pendingDescription {
                    let count = pendingQuantity.flatMap { $0.lineTotal == amount ? $0.count : nil }
                    items.append(ReceiptItem(description: description, quantity: count, amount: amount))
                    pendingDescription = nil
                    pendingQuantity = nil
                }
                continue
            }

            var count = line.quantity?.count ?? line.leadingCount
            if count == nil, let pending = pendingQuantity, pending.lineTotal == amount { count = pending.count }
            let signed = line.isDiscount && amount > 0 ? -amount : amount
            items.append(ReceiptItem(description: line.itemDescription, quantity: count, amount: signed))
            pendingDescription = nil
            pendingQuantity = nil
        }

        result.items = items
        result.subtotal = subtotal
        result.tip = tips.last
        if let taxTotal {
            result.tax = taxTotal
        } else if !taxes.isEmpty {
            var seen = Set<String>()
            result.tax = taxes.filter { seen.insert("\($0.keyword) \($0.value)").inserted }.reduce(0) { $0 + $1.value }
        }
        result.total = chooseTotal(totals, subtotal: subtotal, tax: result.tax, tip: result.tip, items: items)
        return result
    }

    /// Differing totals stay blank unless a tip or arithmetic resolves them.
    private static func chooseTotal(
        _ totals: [(value: Decimal, afterTip: Bool)],
        subtotal: Decimal?,
        tax: Decimal?,
        tip: Decimal?,
        items: [ReceiptItem]
    ) -> Decimal? {
        let values = Set(totals.map(\.value))
        if values.count <= 1 { return values.first }
        if let withTip = totals.last(where: \.afterTip) { return withTip.value }
        let amounts = items.compactMap(\.amount)
        guard let base = subtotal ?? (amounts.isEmpty ? nil : amounts.reduce(0, +)) else { return nil }
        let expected = [base + (tax ?? 0), base + (tax ?? 0) + (tip ?? 0)]
        let matching = totals.map(\.value).filter(expected.contains)
        return Set(matching).count == 1 ? matching.first : nil
    }

    // MARK: - Header fields

    private static func merchant(in lines: [Line]) -> (index: Int, name: String)? {
        let bodyStart = lines.firstIndex { !$0.amounts.isEmpty } ?? lines.count
        for (index, line) in lines.prefix(min(8, bodyStart)).enumerated() {
            var candidate = line.text
            if let welcome = candidate.range(of: #"^welcome to\s+"#, options: [.regularExpression, .caseInsensitive]) {
                candidate.removeSubrange(welcome)
            }
            let folded = fold(candidate)
            let letters = candidate.filter(\.isLetter).count
            let digits = candidate.filter(\.isNumber).count
            guard letters >= 3, digits < 5, candidate.first?.isNumber == false, !candidate.contains(":"),
                  !Patterns.merchantJunk.matches(folded), dateMatch(in: candidate) == nil
            else { continue }
            return (index, candidate.trimmingCharacters(in: CharacterSet(charactersIn: " *#-=_~.,")))
        }
        return nil
    }

    private static func purchaseDate(in lines: [String], today: Day, locale: Locale) -> (day: Day, line: Int)? {
        let monthFirst = localeIsMonthFirst(locale)
        let latest = today.adding(days: 1)
        for (index, line) in lines.enumerated() where !Patterns.notPurchaseDate.matches(fold(line)) {
            guard let match = dateMatch(in: line) else { continue }
            let resolved: Day? = switch match {
            case .ymd(let y, let m, let d): Day(year: y, month: m, day: d)
            case .monthName(let y, let m, let d): Day(year: y, month: m, day: d)
            case .numeric(let a, let b, let y, let dotted):
                if dotted || a > 12 { Day(year: y, month: b, day: a) }
                else if b > 12 { Day(year: y, month: a, day: b) }
                else { monthFirst ? Day(year: y, month: a, day: b) : Day(year: y, month: b, day: a) }
            }
            if let resolved, resolved.year >= 2000, resolved <= latest { return (resolved, index) }
        }
        return nil
    }

    private enum DateMatch {
        case ymd(Int, Int, Int)
        case monthName(Int, Int, Int)
        case numeric(Int, Int, year: Int, dotted: Bool)
    }

    private static func dateMatch(in line: String) -> DateMatch? {
        if let g = Patterns.isoDate.groups(in: line), let y = Int(g[1]), let m = Int(g[2]), let d = Int(g[3]) {
            return .ymd(y, m, d)
        }
        if let g = Patterns.numericDate.groups(in: line), let a = Int(g[1]), let b = Int(g[3]), let y = Int(g[4]) {
            return .numeric(a, b, year: fullYear(y), dotted: g[2] == ".")
        }
        let folded = fold(line)
        if let g = Patterns.monthFirstDate.groups(in: folded), let m = month(g[1]), let d = Int(g[2]), let y = Int(g[3]) {
            return .monthName(fullYear(y), m, d)
        }
        if let g = Patterns.dayFirstDate.groups(in: folded), let d = Int(g[1]), let m = month(g[2]), let y = Int(g[3]) {
            return .monthName(fullYear(y), m, d)
        }
        return nil
    }

    private static func fullYear(_ year: Int) -> Int { year < 100 ? 2000 + year : year }

    private static func month(_ name: String) -> Int? {
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "mai": 5, "jun": 6, "jul": 7, "aug": 8,
                      "sep": 9, "oct": 10, "okt": 10, "nov": 11, "dec": 12, "dez": 12]
        return months[String(name.prefix(3))]
    }

    // MARK: - Printed details

    private static func readDetails(_ lines: [Line], merchantLine: Int?, dateLine: Int?, into result: inout ParsedReceipt) {
        let texts = lines.map(\.text)
        result.storeAddress = storeAddress(in: lines, skipping: merchantLine)
        result.storePhone = storePhone(in: lines)
        result.transactionId = texts.lazy.compactMap { Patterns.transactionId.groups(in: $0)?[1] }.first
        result.purchaseTime = purchaseTime(in: texts, dateLine: dateLine)
        (result.paymentMethod, result.cardLastFour) = payment(in: lines)
        result.odometer = texts.lazy.compactMap { Patterns.odometer.groups(in: $0)?[2] }.first
            .map { $0.filter(\.isNumber) }
        readFuel(texts, into: &result)
    }

    /// Street and city lines in the header, next to each other; nothing is inferred from the merchant name.
    private static func storeAddress(in lines: [Line], skipping merchantLine: Int?) -> String? {
        let bodyStart = lines.firstIndex { !$0.amounts.isEmpty } ?? lines.count
        var parts: [String] = []
        for (index, line) in lines.prefix(min(10, bodyStart)).enumerated() where index != merchantLine {
            let text = line.text
            let isStreet = Patterns.street.matches(text)
            let isCity = Patterns.cityLine.matches(text) || (!parts.isEmpty && Patterns.postalCity.matches(text))
            if isStreet || isCity {
                parts.append(text.trimmingCharacters(in: CharacterSet(charactersIn: " ,")))
            } else if !parts.isEmpty {
                break
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func storePhone(in lines: [Line]) -> String? {
        let texts = lines.map(\.text)
        let labeled = texts.lazy.compactMap { Patterns.labeledPhone.groups(in: $0)?[1] }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { (7...15).contains($0.filter(\.isNumber).count) }
        if let labeled { return labeled }
        return lines.lazy.filter { $0.lineAmounts.isEmpty }
            .compactMap { Patterns.northAmericanPhone.groups(in: $0.text)?[0] ?? Patterns.internationalPhone.groups(in: $0.text)?[0] }
            .first { (10...15).contains($0.filter(\.isNumber).count) }
    }

    /// Only a time on the purchase date's line or on a line labeled as a time.
    private static func purchaseTime(in lines: [String], dateLine: Int?) -> ClockTime? {
        let candidates = (dateLine.map { [lines[$0]] } ?? []) + lines.filter { Patterns.timeLabel.matches(fold($0)) }
        for line in candidates {
            guard let g = Patterns.time.groups(in: line), var hour = Int(g[1]), let minute = Int(g[2]) else { continue }
            switch g[3].lowercased() {
            case "a":
                guard (1...12).contains(hour) else { continue }
                if hour == 12 { hour = 0 }
            case "p":
                guard (1...12).contains(hour) else { continue }
                if hour != 12 { hour += 12 }
            default:
                break
            }
            if let time = ClockTime(hour: hour, minute: minute) { return time }
        }
        return nil
    }

    /// Payment is read from the summary and tender lines, plus any line with a masked card number.
    private static func payment(in lines: [Line]) -> (method: String?, lastFour: String?) {
        let summaryStart = lines.firstIndex { classify($0).isSummary } ?? lines.count
        var method: String?
        var lastFour: String?
        for (index, line) in lines.enumerated() {
            let masked = Patterns.maskedCard.groups(in: line.text)?[1]
            guard index >= summaryStart || masked != nil else { continue }
            if lastFour == nil { lastFour = masked }
            if method == nil {
                let found = Patterns.paymentMethod.allGroups(in: fold(line.text)).compactMap { paymentNames[Search.key($0[1])] }
                method = found.min { $0.rank < $1.rank }?.name
            }
        }
        return (method, lastFour)
    }

    private static let paymentNames: [String: (name: String, rank: Int)] = [
        "visa": ("Visa", 0), "mastercard": ("Mastercard", 0), "master card": ("Mastercard", 0),
        "amex": ("American Express", 0), "american express": ("American Express", 0), "discover": ("Discover", 0),
        "diners": ("Diners Club", 0), "jcb": ("JCB", 0), "unionpay": ("UnionPay", 0), "interac": ("Interac", 0),
        "maestro": ("Maestro", 0), "girocard": ("girocard", 0), "apple pay": ("Apple Pay", 1),
        "google pay": ("Google Pay", 1), "samsung pay": ("Samsung Pay", 1), "paypal": ("PayPal", 1),
        "debit": ("Debit", 2), "credit": ("Credit", 2), "cash": ("Cash", 3),
    ]

    private static func readFuel(_ lines: [String], into result: inout ParsedReceipt) {
        let folded = lines.map(fold)
        let whole = folded.joined(separator: "\n")
        var volume: (value: Decimal, unit: FuelUnit?, line: Int)?
        for (index, line) in folded.enumerated() where volume == nil {
            if let g = Patterns.gallonsVolume.groups(in: line) {
                volume = (decimal(g[1]), .gallons, index)
            } else if let g = Patterns.litersVolume.groups(in: line) {
                volume = (decimal(g[1]), .liters, index)
            } else if let g = Patterns.labeledVolume.groups(in: line) {
                volume = (decimal(g[2]), unit(named: g[1]), index)
            }
        }
        // A price counts as fuel evidence when it is per volume, sits on the volume line or has three decimals.
        var unitPrice: (value: Decimal, unit: FuelUnit?, isFuelPrice: Bool)?
        if let g = Patterns.perVolumePrice.groups(in: whole) {
            unitPrice = (decimal(g[1]), unit(named: g[2]), true)
        } else if let g = Patterns.labeledUnitPrice.groups(in: whole) {
            unitPrice = (decimal(g[3]), g[2].isEmpty ? nil : unit(named: g[2]), !g[2].isEmpty || g[3].suffix(4).first.map { ".,".contains($0) } == true)
        } else if let volume, let g = Patterns.atPrice.groups(in: folded[volume.line]) {
            unitPrice = (decimal(g[1]), nil, true)
        }
        let pump = folded.lazy.compactMap { Patterns.pump.groups(in: $0).map { $0[1].isEmpty ? $0[2] : $0[1] } }.first
        let keyword = Patterns.fuelKeyword.matches(whole)
        let fuelPrice = unitPrice?.isFuelPrice == true

        result.isFuel = (volume != nil && (pump != nil || fuelPrice || keyword))
            || (pump != nil && keyword)
            || (unitPrice?.unit != nil && keyword)
        guard result.isFuel else { return }

        let unit = volume?.unit ?? unitPrice?.unit
        if let volume, let unit {
            result.fuelVolume = volume.value
            result.fuelUnit = unit
        }
        result.fuelUnitPrice = unitPrice?.value
        result.pumpNumber = pump
        // Grade words like "plus" or "super" only count on a line that is clearly about the fuel.
        let fuelLines = lines.indices.filter { index in
            index == volume?.line || Patterns.fuelContext.matches(folded[index])
        }
        let grade = fuelLines.lazy.compactMap { Patterns.grade.groups(in: lines[$0])?[1] }.first
            ?? lines.lazy.compactMap { Patterns.strongGrade.groups(in: $0)?[1] }.first
        result.fuelGrade = grade.map { $0.capitalized }
    }

    private static func unit(named name: String) -> FuelUnit? {
        let name = name.lowercased()
        if name.hasPrefix("g") { return .gallons }
        if name.hasPrefix("l") { return .liters }
        return nil
    }

    private static func decimal(_ text: String) -> Decimal {
        Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static func localeIsMonthFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d"
        guard let m = format.firstIndex(of: "M"), let d = format.firstIndex(of: "d") else { return true }
        return m < d
    }

    private static func currency(in text: String, defaultCurrency: String) -> String? {
        let codes = Set(Patterns.currencyCode.allGroups(in: text).map { $0[1] })
        if codes.count == 1 { return codes.first }
        if codes.count > 1 { return nil }
        let unique: [(String, String)] = [("€", "EUR"), ("£", "GBP"), ("₹", "INR"), ("₩", "KRW"), ("₺", "TRY"), ("₪", "ILS"), ("zł", "PLN")]
        let found = Set(unique.filter { text.contains($0.0) }.map(\.1))
        if found.count == 1 { return found.first }
        if found.count > 1 { return nil }
        // Symbols shared by several currencies only confirm the default; they never pick a different one.
        let shared: [(String, Set<String>)] = [
            ("$", ["USD", "CAD", "AUD", "NZD", "MXN", "SGD", "HKD"]),
            ("¥", ["JPY", "CNY"]),
            ("kr", ["SEK", "NOK", "DKK", "ISK"]),
        ]
        for (symbol, currencies) in shared where text.contains(symbol) && currencies.contains(defaultCurrency) {
            return defaultCurrency
        }
        return nil
    }

    // MARK: - Lines

    private static func normalize(_ raw: String) -> String {
        var line = raw.replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { fixMisreadDigits(String($0)) }
            .joined(separator: " ")
        // Handwriting often leaves a gap around the decimal point of the final amount.
        line = line.replacingOccurrences(of: #"(\d)\s+([.,]\d{2})\s*$"#, with: "$1$2", options: .regularExpression)
        line = line.replacingOccurrences(of: #"(\d[.,])\s+(\d{2})\s*$"#, with: "$1$2", options: .regularExpression)
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// "4.OO" or "l2.50" in an otherwise numeric token are OCR confusions of 0 and 1.
    private static func fixMisreadDigits(_ token: String) -> String {
        guard token.wholeMatch(of: /[-−(]?[$€£]?[0-9OoIl]*[0-9][0-9OoIl]*[.,][0-9OoIl]{2}[)\-]?/) != nil else { return token }
        return String(token.map { "Oo".contains($0) ? "0" : "Il".contains($0) ? "1" : $0 })
    }

    fileprivate static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Keyword text with digit-for-letter OCR slips undone, so "T0TAL" and "SUBT0TAL" still match.
    fileprivate static func keywordText(_ label: String) -> String {
        fold(label).split(separator: " ").map { word in
            guard word.contains(where: \.isLetter), word.contains(where: \.isNumber) else { return String(word) }
            return String(word.map { $0 == "0" ? "o" : $0 == "1" ? "l" : $0 == "5" ? "s" : $0 })
        }.joined(separator: " ")
    }

    private enum Kind {
        case item, ignore, subtotal, tip, total
        case tax(keyword: String, isTotal: Bool)

        var isSummary: Bool {
            switch self {
            case .item, .ignore: false
            default: true
            }
        }
    }

    private static func classify(_ line: Line) -> Kind {
        let label = line.keywords
        if Patterns.payment.matches(label) { return .ignore }
        if Patterns.subtotal.matches(label) { return .subtotal }
        if Patterns.tip.matches(label) { return .tip }
        let isTotal = Patterns.total.matches(label)
        if let keyword = Patterns.tax.groups(in: label)?[1] {
            if !isTotal { return .tax(keyword: keyword, isTotal: false) }
            return Patterns.included.matches(label) ? .total : .tax(keyword: keyword, isTotal: true)
        }
        return isTotal ? .total : .item
    }
}

private struct Amount {
    let value: Decimal
    let range: NSRange
}

private struct Quantity {
    let count: Decimal
    let unitPrice: Decimal
    let range: NSRange

    var lineTotal: Decimal { count * unitPrice }
}

private struct Line {
    let text: String
    let amounts: [Amount]
    let quantity: Quantity?
    /// Amounts outside the quantity expression, i.e. candidates for the line's own total.
    let lineAmounts: [Amount]
    let keywords: String
    let letterCount: Int

    init(_ text: String) {
        self.text = text
        amounts = Patterns.amount.matches(in: text).map { match in
            let ns = text as NSString
            let number = ns.substring(with: match.range(withName: "num"))
            let negative = match.range(withName: "sign").location != NSNotFound
                || match.range(withName: "sign2").location != NSNotFound
                || match.range(withName: "trail").location != NSNotFound
                || (match.range(withName: "open").location != NSNotFound && match.range(withName: "close").location != NSNotFound)
            let value = Line.decimal(number)
            return Amount(value: negative ? -value : value, range: match.range)
        }
        quantity = Patterns.quantity.firstMatch(in: text).flatMap { match in
            let ns = text as NSString
            guard let count = Decimal(string: ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "."),
                                      locale: Locale(identifier: "en_US_POSIX")),
                  count > 0
            else { return nil }
            return Quantity(count: count, unitPrice: Line.decimal(ns.substring(with: match.range(at: 2))), range: match.range)
        }
        let quantityRange = quantity?.range
        lineAmounts = amounts.filter { amount in
            quantityRange.map { NSIntersectionRange($0, amount.range).length == 0 } ?? true
        }
        let label = Line.removing(amounts.map(\.range) + [quantityRange].compactMap { $0 }, from: text)
        keywords = ReceiptParser.keywordText(label)
        letterCount = ReceiptParser.fold(label)
            .replacingOccurrences(of: Patterns.unitWords, with: " ", options: .regularExpression)
            .filter(\.isLetter).count
    }

    var isAmountOnly: Bool { !lineAmounts.isEmpty && letterCount < 2 }
    var isDiscount: Bool { Patterns.discount.matches(keywords) }

    /// A leading "2 x" or "2x" before the description.
    var leadingCount: Decimal? {
        Patterns.leadingCount.groups(in: text).flatMap { Decimal(string: $0[1]) }
    }

    var itemDescription: String {
        let ns = text as NSString
        let end = lineAmounts.first?.range.location ?? ns.length
        var removed = [NSRange(location: end, length: ns.length - end)]
        if let quantity { removed.append(quantity.range) }
        var description = Line.removing(removed, from: text)
        for pattern in [#"^\d{1,3}\s*[x×]\s+"#, #"^\d{5,}\s+"#, #"[$€£¥₹₩]"#, Patterns.currencyCodePattern] {
            description = description.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return description
            .split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:*#-=_~@"))
    }

    /// The last separator before two final digits is the decimal point; any others group thousands.
    static func decimal(_ number: String) -> Decimal {
        let digits = number.filter(\.isNumber)
        return Decimal(string: "\(digits.dropLast(2)).\(digits.suffix(2))", locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    static func removing(_ ranges: [NSRange], from text: String) -> String {
        let result = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) where NSMaxRange(range) <= result.length {
            result.replaceCharacters(in: range, with: " ")
        }
        return result as String
    }
}

private enum Patterns {
    static let amount = TextPattern(
        #"(?<![\d.,])(?<sign>[-−–]\s?)?(?<open>\()?(?:[$€£¥₹₩]\s?)?(?<sign2>[-−–])?"#
            + #"(?<num>\d{1,3}(?:[.,']\d{3})+[.,]\d{2}|\d+[.,]\d{2})(?<close>\))?(?<trail>-(?!\d))?(?!\d|[.,]\d|\s?%)"#
    )
    static let quantity = TextPattern(
        #"(?<![\d.,])(\d{1,4}(?:[.,]\d{1,3})?)\s*(?:(?:lb|lbs|kg|g|oz|ea|pc|pcs|stk|st)\.?\s*)?[x×*@]\s*(?:[$€£]\s*)?(\d+[.,]\d{2})(?:\s*/\s*(?:lb|kg|ea|st|stk|pc))?"#
    )
    static let leadingCount = TextPattern(#"^(\d{1,3})\s*[x×]\s+(?=\p{L})"#)
    static let unitWords = #"\b(lb|lbs|kg|g|oz|ea|each|pc|pcs|stk|st|x)\b"#

    static let payment = TextPattern(
        #"\b(cash|change|tender(ed)?|visa|mastercard|amex|debit|auth(orization)?|approval|approved|you saved|total savings|loyalty|points|ruckgeld|gegeben|especes|rendu|efectivo|contanti|paid|payment|balance(?!\s*due)|rounding)\b"#
    )
    static let subtotal = TextPattern(
        #"(sub\s*-?\s*total|zwischensumme|sous[\s-]*total|subtotale|\bht\b|hors taxes?|\bexcl|\bexkl|before tax|pre-?tax|\bnetto\b)"#
    )
    static let tip = TextPattern(#"\b(tip|tips|gratuity|trinkgeld|pourboire|propina|mancia)\b"#)
    static let total = TextPattern(
        #"\b(total|amount due|balance due|to pay|summe|gesamt|gesamtbetrag|zu zahlen|totale|importe|totaal|te betalen|brutto|montant|a payer|ttc)\b"#
    )
    static let tax = TextPattern(#"\b(tax|taxes|sales tax|vat|gst|hst|pst|qst|mwst|ust|tva|iva|btw|moms|igic)\b"#)
    static let included = TextPattern(#"\b(incl|inkl|including|included|inc|ttc)\b"#)
    static let discount = TextPattern(
        #"\b(discount|coupon|savings|saving|promo|promotion|rabatt|remise|descuento|sconto|korting|reduction|markdown)\b"#
    )

    static let merchantJunk = TextPattern(
        #"(receipt|invoice|welcome|thank|\btel\b|phone|\bfax\b|store\s*#|\border\b|\btable\b|server|cashier|register|\bdate\b|\btime\b|guest|customer|copy|terminal|www|http|@|\.com\b)"#
    )
    static let notPurchaseDate = TextPattern(#"\b(exp|expires?|expiry|valid|return|returns|until|best before|use by|bis|gultig)\b"#)
    static let isoDate = TextPattern(#"\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b"#)
    static let numericDate = TextPattern(#"\b(\d{1,2})([./-])(\d{1,2})\2(\d{4}|\d{2})\b"#)
    static let monthFirstDate = TextPattern(
        #"\b(jan|feb|mar|apr|may|mai|jun|jul|aug|sep|oct|okt|nov|dec|dez)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4}|\d{2})\b"#
    )
    static let dayFirstDate = TextPattern(
        #"\b(\d{1,2})\.?\s+(jan|feb|mar|apr|may|mai|jun|jul|aug|sep|oct|okt|nov|dec|dez)[a-z]*\.?,?\s+(\d{4}|\d{2})\b"#
    )

    static let street = TextPattern(
        #"^\d{1,6}[a-z]?\s+(?:[nsew]\.?\s+)?[\p{L}0-9][\p{L}0-9 .'-]*\b(st|street|ave|avenue|rd|road|blvd|boulevard|dr|drive|hwy|highway|ln|lane|way|pkwy|parkway|ct|court|pl|place|plaza|sq|square|ter|terrace|cir|circle|trl|trail|rte|route|expy|fwy|freeway|pike|tpke)\b\.?"#
            + #"|^\d{1,5}[a-z]?,?\s+(rue|avenue|boulevard|bd|chemin|allee|allée|via|viale|piazza|calle|avenida|carrer)\b"#
            + #"|^[\p{L}][\p{L}.' -]*(straße|strasse|str\.|weg|platz|gasse|allee|ring|damm|ufer|laan|straat|plein|gracht)\s*\d{1,4}[a-z]?\b"#
    )
    /// "Portland, OR 97201", "Toronto ON M5V 2T6" or a UK postcode.
    static let cityLine = TextPattern(
        #"^[\p{L}][\p{L} .'-]*,?\s+[A-Z]{2}\s+(\d{5}(-\d{4})?|[A-Z]\d[A-Z]\s?\d[A-Z]\d)$|\b[A-Z]{1,2}\d[A-Z\d]?\s\d[A-Z]{2}$"#,
        caseInsensitive: false
    )
    /// "10115 Berlin"; only trusted right after a street line.
    static let postalCity = TextPattern(#"^(?:[A-Z]{1,2}-)?\d{4,5}\s+[\p{L}][\p{L} .'-]+$"#)
    static let labeledPhone = TextPattern(#"\b(?:tel|phone|ph|telefon|telephone|téléphone|call)\b\.?\s*:?\s*(\+?[\d(][\d\s().\-/]{5,}\d)"#)
    static let northAmericanPhone = TextPattern(#"(?<![\d.])(?:\+?1[\s.-])?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]\d{4}(?![\d.])"#)
    static let internationalPhone = TextPattern(#"(?<!\d)\+\d{1,3}[\s\d().-]{6,}\d"#)
    static let transactionId = TextPattern(
        #"\b(?:transaction|trans|tran|txn|trx|receipt|rcpt|invoice|inv|order|ticket|tkt|ref|reference|seq|bon|beleg)\b\.?(?:\s*(?:#|no\.?|nr\.?|num(?:ber)?|id|-nr\.?))?\s*[:#.]?\s*((?=[A-Z-]*\d)[A-Z0-9][A-Z0-9-]{2,31})\b(?![.,]\d)"#
    )
    static let timeLabel = TextPattern(#"\b(time|zeit|heure|hora|ora|uhrzeit)\b"#)
    static let time = TextPattern(#"(?<![\d:])(\d{1,2}):([0-5]\d)(?::[0-5]\d)?(?:\s*([ap])\.?\s?m\b\.?)?(?![\d:])"#)
    static let paymentMethod = TextPattern(
        #"\b(visa|master\s?card|amex|american express|discover|diners|jcb|unionpay|interac|maestro|girocard|apple pay|google pay|samsung pay|paypal|debit|credit|cash)\b"#
    )
    static let maskedCard = TextPattern(#"(?<![\p{L}\d*•])[*xX•]{2,}[\s*xX•-]*(\d{4})(?!\d)"#, caseInsensitive: false)
    static let odometer = TextPattern(
        #"\b(odometer|odo|mileage|km[- ]?stand|kilometerstand)\b\.?\s*:?\s*(\d{1,3}(?:[,.' ]\d{3})+|\d{1,7})(?![\d.,])"#
    )

    static let fuelKeyword = TextPattern(#"\b(fuel|gasoline|petrol|diesel|unleaded|benzin|gazole|gasoil|carburant)\b"#)
    static let fuelContext = TextPattern(#"\b(fuel|gas|grade|product|pump|gallons?|gal|litres?|liters?|ltr|unleaded|diesel|octane)\b"#)
    static let gallonsVolume = TextPattern(#"(?<![\d.,])(\d{1,3}[.,]\d{2,3})\s*(?:gal|gals|gallons?|g)\b"#)
    static let litersVolume = TextPattern(#"(?<![\d.,])(\d{1,3}[.,]\d{2,3})\s*(?:l|lt|ltr|ltrs|litres?|liters?)\b"#)
    static let labeledVolume = TextPattern(#"\b(gallons?|gals?|litres?|liters?|ltrs?|volume|vol|menge)\b\.?\s*:?\s*(\d{1,3}[.,]\d{2,3})(?![\d.,])"#)
    static let perVolumePrice = TextPattern(#"(?<![\d.,])(\d{1,2}[.,]\d{2,3})\s*/\s*(gal|gallon|g|l|ltr|litre|liter)\b"#)
    static let labeledUnitPrice = TextPattern(
        #"\b(price|ppg|ppl|unit price|preis)\b\s*(?:/\s*(gal|g|l|ltr|litre|liter)\b)?\s*:?\s*[$€£]?\s*(\d{1,2}[.,]\d{2,3})(?![\d.,])"#
    )
    static let atPrice = TextPattern(#"@\s*[$€£]?\s*(\d{1,2}[.,]\d{2,3})(?![\d.,])"#)
    static let pump = TextPattern(
        #"\b(?:pump|zapfsaule|saule)\s*(?:(?:#|no\.?|nr\.?|number)\s*:?|:)\s*(\d{1,3})\b|^(?:pump|zapfsaule|saule)\s+(\d{1,3})$"#
    )
    static let grade = TextPattern(
        #"\b(super unleaded|premium unleaded|unleaded plus|super\s?(?:plus|e10|e5)|unleaded|regular|mid-?grade|premium|plus|super|diesel|e85|e15|e10|v-power|supreme|ultimate)\b"#
    )
    static let strongGrade = TextPattern(#"\b(super unleaded|premium unleaded|unleaded plus|super\s?(?:plus|e10|e5)|unleaded|mid-?grade|diesel|e85|e15)\b"#)

    static let currencyCodePattern = #"\b(USD|EUR|GBP|CAD|AUD|NZD|CHF|JPY|CNY|SEK|NOK|DKK|PLN|CZK|HUF|INR|MXN|BRL|ZAR|SGD|HKD|KRW|TRY|ILS)\b"#
    static let currencyCode = TextPattern(currencyCodePattern, caseInsensitive: false)
}

/// A thin wrapper over `NSRegularExpression`, which supports the lookbehind these patterns rely on.
private struct TextPattern: @unchecked Sendable {
    let expression: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = true) {
        expression = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func matches(in text: String) -> [NSTextCheckingResult] {
        expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    func firstMatch(in text: String) -> NSTextCheckingResult? {
        expression.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    func matches(_ text: String) -> Bool { firstMatch(in: text) != nil }

    /// Capture groups of the first match, with index 0 as the whole match.
    func groups(in text: String) -> [String]? {
        firstMatch(in: text).map { groups(of: $0, in: text) }
    }

    func allGroups(in text: String) -> [[String]] {
        matches(in: text).map { groups(of: $0, in: text) }
    }

    private func groups(of match: NSTextCheckingResult, in text: String) -> [String] {
        (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : (text as NSString).substring(with: range)
        }
    }
}
