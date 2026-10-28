import Foundation
import AppKit
import PDFKit
import Vision
import SwiftData

/// How the receipt says it was paid, as far as it can be told: the kind of payment when it is clear, and a short label such as "Visa ending 1234".
struct ReceiptPaymentClue: Equatable {
    /// The payment method this points to, or nil when the receipt only gives a card brand and not whether it was debit or credit.
    var type: PaymentType?
    /// What to show: "Cash", "Visa ending 1234", "Apple Pay".
    var label: String
    /// The last four digits of a card, when printed.
    var lastFour: String?
}

/// What a scan of a receipt found: the total, the date and the store's name, plus the subtotal, tax, tip and how it was paid when the receipt says,
/// any of which may be missing.
struct ReceiptReading: Equatable {
    var total: Decimal?
    var date: Date?
    var merchant: String?
    var subtotal: Decimal?
    var tax: Decimal?
    var tip: Decimal?
    /// How many items the receipt says there were, when it says.
    var itemCount: Int?
    var payment: ReceiptPaymentClue?
    /// The text as read, one line to a row, for showing what the scan saw.
    var lines: [String] = []

    var isEmpty: Bool { total == nil && date == nil && merchant == nil && tax == nil && tip == nil && payment == nil }

    /// A short note to offer as the transaction's memo from what the receipt says about itself, such as "3 items · tax $2.10 · tip $5.00". Nil when
    /// there is nothing to say.
    var memoSuggestion: String? {
        var parts: [String] = []
        if let itemCount { parts.append("\(itemCount) item\(itemCount == 1 ? "" : "s")") }
        if let tax, tax > 0 { parts.append("tax \(tax.formatted(.appCurrency))") }
        if let tip, tip > 0 { parts.append("tip \(tip.formatted(.appCurrency))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Reads a receipt's photo or PDF on this Mac, with Apple's Vision framework, and works out the total, date and store from the text. Nothing
/// is sent anywhere, and nothing is changed: the reading is only compared with what was typed.
enum ReceiptReader {
    // MARK: Reading the picture

    /// The text on a receipt photo or PDF, a row at a time from the top. Empty when nothing could be read.
    static func rows(from data: Data) async -> [String] {
        // A PDF made from a web page or an app has its text in it already, so that is used first.
        if Receipt.isPDF(data), let document = PDFDocument(data: data) {
            let embedded = (0..<min(document.pageCount, 2)).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
            let lines = embedded.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if lines.count >= 3 { return lines }
        }
        guard let image = cgImage(from: data) else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do { try handler.perform([request]) } catch { continuation.resume(returning: []); return }
                continuation.resume(returning: group(request.results ?? []))
            }
        }
    }

    private static func cgImage(from data: Data) -> CGImage? {
        if Receipt.isPDF(data) {
            guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
            let box = page.bounds(for: .mediaBox)
            let scale = min(2000 / max(box.width, box.height), 3)
            let size = NSSize(width: box.width * scale, height: box.height * scale)
            let image = page.thumbnail(of: size, for: .mediaBox)
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Vision hands back pieces of text. Pieces on the same row, such as "TOTAL" and "$13.56", are joined, and the rows run from the top.
    private static func group(_ observations: [VNRecognizedTextObservation]) -> [String] {
        let pieces: [(text: String, midY: CGFloat, minX: CGFloat, height: CGFloat)] = observations.compactMap {
            guard let text = $0.topCandidates(1).first?.string else { return nil }
            return (text, $0.boundingBox.midY, $0.boundingBox.minX, $0.boundingBox.height)
        }.sorted { $0.midY > $1.midY }
        var rows: [[(text: String, midY: CGFloat, minX: CGFloat, height: CGFloat)]] = []
        for piece in pieces {
            if let last = rows.last?.first, abs(last.midY - piece.midY) < max(last.height, piece.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: "  ") }
    }

    // MARK: Making sense of the text

    /// Finds the total, date and store in rows of receipt text. Pure, so it can be tested without a picture.
    static func parse(_ rows: [String], now: Date = .now, calendar: Calendar = .current) -> ReceiptReading {
        var total = total(in: rows)
        let tip = tip(in: rows)
        // A receipt that prints the bill and then a line with the tip added: what was charged is the one that includes the tip.
        if let bill = total, let tip, rows.flatMap(amounts(in:)).contains(bill + tip) { total = bill + tip }
        return ReceiptReading(total: total, date: date(in: rows, now: now, calendar: calendar), merchant: merchant(in: rows),
                              subtotal: subtotal(in: rows), tax: tax(in: rows), tip: tip, itemCount: itemCount(in: rows), payment: payment(in: rows), lines: rows)
    }

    private static let amountPattern = try! NSRegularExpression(pattern: #"(?<![\d.,])\$?\s?(\d{1,3}(?:,\d{3})+|\d+)[.,](\d{2})(?![\d])"#)

    private static func amounts(in line: String) -> [Decimal] {
        let range = NSRange(line.startIndex..., in: line)
        return amountPattern.matches(in: line, range: range).compactMap { match in
            guard let whole = Range(match.range(at: 1), in: line), let cents = Range(match.range(at: 2), in: line) else { return nil }
            return Decimal(string: line[whole].replacingOccurrences(of: ",", with: "") + "." + line[cents])
        }
    }

    private static func total(in rows: [String]) -> Decimal? {
        // Lines that say what the whole bill was. Sub-totals, tax and savings lines are not it.
        let strong = try! NSRegularExpression(pattern: #"(grand\s*total|amount\s*due|balance\s*due|total\s*due|total\s*amount|amount\s*paid|total\s*paid)"#, options: .caseInsensitive)
        let plain = try! NSRegularExpression(pattern: #"\btotal\b"#, options: .caseInsensitive)
        let notIt = try! NSRegularExpression(pattern: #"(sub\s*-?\s*total|tax|saving|discount|tip|items|points|change)"#, options: .caseInsensitive)
        func matches(_ regex: NSRegularExpression, _ line: String) -> Bool { regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }

        func figure(onOrAfter index: Int) -> Decimal? {
            if let amount = amounts(in: rows[index]).last { return amount }
            return index + 1 < rows.count ? amounts(in: rows[index + 1]).first : nil
        }
        // The last strong line is the bill's bottom line. Then the last line that just says "total".
        for index in rows.indices.reversed() where matches(strong, rows[index]) {
            if let amount = figure(onOrAfter: index) { return amount }
        }
        for index in rows.indices.reversed() where matches(plain, rows[index]) && !matches(notIt, rows[index]) {
            if let amount = figure(onOrAfter: index) { return amount }
        }
        // No total line was read: the biggest amount is the best guess.
        return rows.flatMap(amounts(in:)).filter { $0 < 1_000_000 }.max()
    }

    // MARK: Subtotal, tax, tip, items and payment

    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern, options: .caseInsensitive) }
    private static func matches(_ expression: NSRegularExpression, _ line: String) -> Bool { expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }

    /// The amount on a line, or on the line under it when the label sits alone: the last amount on the line.
    private static func figure(at index: Int, in rows: [String]) -> Decimal? {
        if let amount = amounts(in: rows[index]).last { return amount }
        return index + 1 < rows.count ? amounts(in: rows[index + 1]).first : nil
    }

    private static func subtotal(in rows: [String]) -> Decimal? {
        let label = regex(#"sub\s*-?\s*total"#)
        for index in rows.indices where matches(label, rows[index]) {
            if let amount = figure(at: index, in: rows) { return amount }
        }
        return nil
    }

    /// Tax: a "total tax" line when there is one, otherwise every tax line added up (a state and a county tax are two lines).
    private static func tax(in rows: [String]) -> Decimal? {
        let total = regex(#"total\s+(sales\s+)?tax"#)
        for index in rows.indices where matches(total, rows[index]) {
            if let amount = figure(at: index, in: rows), amount > 0 { return amount }
        }
        let label = regex(#"(\bsales\s+tax\b|\btax\b|\bvat\b|\bgst\b|\bhst\b|\bpst\b)"#)
        let notIt = regex(#"(before\s+tax|tax\s*id|tax\s*exempt|tax\s*free|incl|includes|included|pre-?\s*tax|taxable|total|sub\s*-?\s*total)"#)
        var sum: Decimal = 0
        var found = false
        for index in rows.indices where matches(label, rows[index]) && !matches(notIt, rows[index]) {
            if let amount = amounts(in: rows[index]).last, amount > 0 { sum += amount; found = true }
        }
        return found ? sum : nil
    }

    /// The tip or gratuity actually added: not the suggested percentages some receipts print.
    private static func tip(in rows: [String]) -> Decimal? {
        let label = regex(#"\b(tip|gratuity)\b"#)
        let notIt = regex(#"(suggest|guide|%|calculat|recommend|total\s+with|if\s+you|add\s+a)"#)
        for index in rows.indices.reversed() where matches(label, rows[index]) && !matches(notIt, rows[index]) {
            if let amount = amounts(in: rows[index]).last, amount > 0 { return amount }
        }
        return nil
    }

    /// "3 items", "Items: 3", "# of items 3": how many things were bought.
    private static func itemCount(in rows: [String]) -> Int? {
        let after = regex(#"(?:items?\s*(?:sold|purchased|count)?\s*[:=]?\s*|#\s*of\s*items\s*[:=]?\s*)(\d{1,3})\b"#)
        let before = regex(#"\b(\d{1,3})\s+items?\b"#)
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            for expression in [before, after] {
                if let match = expression.firstMatch(in: row, range: range), let found = Range(match.range(at: 1), in: row), let count = Int(row[found]), count > 0 {
                    return count
                }
            }
        }
        return nil
    }

    /// How it was paid, from a card line ("VISA ****1234", "Mastercard ending in 4321", "DEBIT"), a wallet ("Apple Pay"), or cash.
    private static func payment(in rows: [String]) -> ReceiptPaymentClue? {
        let brand = regex(#"\b(visa|master\s*card|mastercard|amex|american\s+express|discover|diners|jcb|unionpay)\b"#)
        let lastFour = regex(#"(?:\*{2,}|x{2,}|•{2,}|\.{2,}|ending\s+(?:in\s+)?|acct\.?\s*#?\s*|card\s*#?\s*)[\s*x•.]*(\d{4})\b"#)
        let wallets: [(NSRegularExpression, PaymentType, String)] = [
            (regex(#"apple\s*pay"#), .applePay, "Apple Pay"), (regex(#"google\s*pay|g\s*pay"#), .googlePay, "Google Pay"),
            (regex(#"samsung\s*pay"#), .samsungPay, "Samsung Pay"), (regex(#"paypal"#), .paypal, "PayPal"), (regex(#"venmo"#), .venmo, "Venmo")]
        let cashLine = regex(#"(^|\s)cash(\s+(tender(ed)?|payment|paid|given))?(\s|:|$)"#)
        let notCash = regex(#"(cashier|cash\s*back|cashback|cash\s+reward|cash\s+advance|cash\s+register)"#)

        for row in rows {
            for (expression, type, label) in wallets where matches(expression, row) { return ReceiptPaymentClue(type: type, label: label, lastFour: nil) }
        }
        for (index, row) in rows.enumerated() {
            guard let match = brand.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)), let range = Range(match.range, in: row) else { continue }
            var name = String(row[range]).lowercased().replacingOccurrences(of: " ", with: "")
            switch name {
            case "mastercard": name = "Mastercard"
            case "americanexpress", "amex": name = "Amex"
            default: name = name.capitalized
            }
            // The last four digits are on this line or the next.
            var digits: String?
            for candidate in [row] + (index + 1 < rows.count ? [rows[index + 1]] : []) {
                if let m = lastFour.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)), let r = Range(m.range(at: 1), in: candidate) {
                    digits = String(candidate[r]); break
                }
            }
            let window = (index > 0 ? rows[index - 1] : "") + " " + row + " " + (index + 1 < rows.count ? rows[index + 1] : "")
            let type: PaymentType? = matches(regex(#"\bdebit\b"#), window) ? .debitCard : (matches(regex(#"\bcredit\b"#), window) ? .creditCard : nil)
            return ReceiptPaymentClue(type: type, label: digits.map { "\(name) ending \($0)" } ?? name, lastFour: digits)
        }
        for row in rows where matches(cashLine, row) && !matches(notCash, row) && (!amounts(in: row).isEmpty || row.lowercased().contains("tender")) {
            return ReceiptPaymentClue(type: .cash, label: "Cash", lastFour: nil)
        }
        return nil
    }

    private static func date(in rows: [String], now: Date, calendar: Calendar) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let earliest = calendar.date(byAdding: .year, value: -3, to: now) ?? .distantPast
        let latest = calendar.date(byAdding: .day, value: 30, to: now) ?? .distantFuture
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            for match in detector.matches(in: row, range: range) {
                if let found = match.date, found >= earliest, found <= latest { return calendar.startOfDay(for: found) }
            }
        }
        return nil
    }

    private static func merchant(in rows: [String]) -> String? {
        let skip = try! NSRegularExpression(pattern: #"(receipt|invoice|welcome|thank|order|store\s*#|tel|phone|www\.|\.com|cashier|server|table|guest|check\s*#|duplicate|copy)"#, options: .caseInsensitive)
        for row in rows.prefix(8) {
            let text = row.trimmingCharacters(in: .whitespaces)
            let letters = text.filter(\.isLetter).count
            let digits = text.filter(\.isNumber).count
            guard letters >= 3, Double(digits) <= Double(letters) * 0.4, text.count <= 48 else { continue }
            if skip.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { continue }
            // A name in capitals reads better as words.
            return text == text.uppercased() ? text.capitalized : text
        }
        return nil
    }

    /// Reads a receipt picture or PDF: its text, then the total, date and store.
    static func read(_ data: Data) async -> ReceiptReading {
        parse(await rows(from: data))
    }
}

// MARK: Checking what was typed

/// What a receipt says that differs from what was typed, as suggestions. Nothing is changed until one is taken.
enum ReceiptCheck {
    struct Suggestion: Identifiable, Equatable {
        enum Field: Equatable {
            case amount(Decimal), date(Date), payee(String), category(Category), method(PaymentType), memo(String)

            static func == (lhs: Field, rhs: Field) -> Bool {
                switch (lhs, rhs) {
                case (.amount(let a), .amount(let b)): a == b
                case (.date(let a), .date(let b)): a == b
                case (.payee(let a), .payee(let b)): a == b
                case (.category(let a), .category(let b)): a.persistentModelID == b.persistentModelID
                case (.method(let a), .method(let b)): a == b
                case (.memo(let a), .memo(let b)): a == b
                default: false
                }
            }
        }
        let field: Field
        let message: String
        var id: String { message }
    }

    /// What the receipt can be set against besides the total, date and payee: the transaction's category, payment method and memo, as they stand.
    struct Fields {
        /// Whether the transaction is money out. Only categories of the right kind are suggested.
        var isPayment = true
        /// The categories this transaction can have.
        var categories: [Category] = []
        var category: Category?
        /// What the payee's earlier transactions were filed under, when this payee has been used before.
        var payeeCategory: Category?
        var payeeName = ""
        var method: PaymentChoice?
        /// False where the payment method is fixed, such as a credit card charge.
        var offersMethod = false
        var memo = ""
    }

    /// `remembered` is a payee this Mac has learned for the store on the receipt.
    static func suggestions(for reading: ReceiptReading, amount: Decimal?, date: Date, payee: String, remembered: String?,
                            calendar: Calendar = .current) -> [Suggestion] {
        var list: [Suggestion] = []
        if let total = reading.total {
            if amount == nil || (amount.map { abs($0) } ?? 0) != total {
                let said = amount.map { "you entered \(abs($0).formatted(.appCurrency))" } ?? "the amount is empty"
                list.append(Suggestion(field: .amount(total), message: "The receipt says \(total.formatted(.appCurrency)), \(said)."))
            }
        }
        if let found = reading.date, !calendar.isDate(found, inSameDayAs: date) {
            list.append(Suggestion(field: .date(found), message: "The receipt is dated \(found.formatted(date: .abbreviated, time: .omitted)), you entered \(date.formatted(date: .abbreviated, time: .omitted))."))
        }
        let name = (remembered ?? reading.merchant)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !name.isEmpty, !sameStore(name, payee) {
            let said = payee.trimmingCharacters(in: .whitespaces).isEmpty ? "the payee is empty" : "you entered \(payee)"
            list.append(Suggestion(field: .payee(name), message: "The receipt looks like \(name)\(remembered != nil ? " (remembered)" : ""), \(said)."))
        }
        return list
    }

    /// The category, payment method and memo the receipt points to, for a blank field ("add") or one that differs ("change"). A suggestion changes
    /// nothing until it is taken, and a memo that already says something is never offered a replacement.
    static func moreSuggestions(for reading: ReceiptReading, fields: Fields) -> [Suggestion] {
        var list: [Suggestion] = []
        let usable = fields.categories.filter { $0.isLive && $0.isIncome == !fields.isPayment }

        // Category: what this payee was filed under before, else what the receipt looks like.
        var candidate: Category?
        var reason = ""
        if let before = fields.payeeCategory, usable.contains(where: { $0.persistentModelID == before.persistentModelID }) {
            candidate = before
            reason = "Your earlier \(fields.payeeName) transactions are filed under \(before.name)"
        } else if let key = categoryKey(for: reading), let guess = usable.first(where: { $0.systemKey == key }) {
            candidate = guess
            reason = "The receipt looks like \(guess.name)"
        }
        if let candidate, candidate.persistentModelID != fields.category?.persistentModelID {
            if let chosen = fields.category {
                list.append(Suggestion(field: .category(candidate), message: "\(reason), you chose \(chosen.name)."))
            } else {
                list.append(Suggestion(field: .category(candidate), message: "\(reason). Add the category?"))
            }
        }

        // Payment method: only when the receipt is clear about it, and never over one of your own methods.
        if fields.offersMethod, let clue = reading.payment, let type = clue.type {
            switch fields.method {
            case nil:
                list.append(Suggestion(field: .method(type), message: "The receipt says it was paid with \(clue.label). Add the payment method?"))
            case .type(let chosen) where chosen != type:
                list.append(Suggestion(field: .method(type), message: "The receipt says \(clue.label), you chose \(chosen.title)."))
            default:
                break
            }
        }

        // Memo: a note from what the receipt says about itself, only into an empty memo.
        if fields.memo.trimmingCharacters(in: .whitespaces).isEmpty, let note = reading.memoSuggestion {
            list.append(Suggestion(field: .memo(note), message: "The receipt has \(note). Add it as the memo?"))
        }
        return list
    }

    /// A guess at the built-in category a receipt belongs to, from words on it: fuel on a gas receipt, a tip and a table on a restaurant one.
    /// Nil when nothing says. It is only ever offered as a suggestion.
    static func categoryKey(for reading: ReceiptReading) -> String? {
        let text = ([reading.merchant ?? ""] + reading.lines).joined(separator: "\n").lowercased()
        func has(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        if has(#"\b(gallons?|unleaded|diesel|price/?\s*gal|fuel\s+total|pump\s*#?\s*\d)"#) { return "gas-fuel" }
        if reading.tip != nil || has(#"\b(gratuity|server:?|table\s*#?\s*\d|guest\s*(count|#)?\s*\d)"#) { return "dining-out" }
        if has(#"\b(pharmacy|prescription|rx\s*#?\s*\d)"#) { return "pharmacy" }
        if has(#"\b(coffee|espresso|latte|cappuccino|cafe|café)\b"#) { return "coffee-snacks" }
        if has(#"\b(parking|toll)\b"#) { return "parking-tolls" }
        if has(#"\b(grocery|groceries|supermarket|produce|dairy|deli)\b"#) { return "groceries" }
        return nil
    }

    /// Whether two names are close enough to be the same place: one holds the other, or they start the same.
    static func sameStore(_ a: String, _ b: String) -> Bool {
        let x = fingerprint(a), y = fingerprint(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x.contains(y) || y.contains(x) || x.prefix(5) == y.prefix(5)
    }

    static func fingerprint(_ text: String) -> String { String(text.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(24)) }
}

// MARK: Remembering stores

/// Which payee goes with which store name on a receipt, learned on this Mac so the next receipt from the same place suggests it. It is
/// kept in a small file on this Mac only: it is not in the database, not in backups and never leaves the computer.
enum ReceiptMemory {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ReceiptMemory.json")
    }

    private static func load() -> [String: String] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    static func payee(forMerchant merchant: String?) -> String? {
        guard let merchant else { return nil }
        return load()[ReceiptCheck.fingerprint(merchant)]
    }

    static func remember(merchant: String?, payee: String) {
        let name = payee.trimmingCharacters(in: .whitespaces)
        guard let merchant, !name.isEmpty else { return }
        let key = ReceiptCheck.fingerprint(merchant)
        guard !key.isEmpty else { return }
        var all = load()
        guard all[key] != name else { return }
        all[key] = name
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: url, options: .atomic) }
    }

    /// Forgets everything learned.
    static func forgetAll() { try? FileManager.default.removeItem(at: url) }
}
