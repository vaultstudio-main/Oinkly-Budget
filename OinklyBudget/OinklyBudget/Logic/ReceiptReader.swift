import Foundation
import AppKit
import PDFKit
import Vision

/// What a scan of a receipt found: the total, the date and the store's name, any of which may be missing.
struct ReceiptReading: Equatable {
    var total: Decimal?
    var date: Date?
    var merchant: String?
    /// The text as read, one line to a row, for showing what the scan saw.
    var lines: [String] = []

    var isEmpty: Bool { total == nil && date == nil && merchant == nil }
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
        ReceiptReading(total: total(in: rows), date: date(in: rows, now: now, calendar: calendar), merchant: merchant(in: rows), lines: rows)
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
        enum Field: Equatable { case amount(Decimal), date(Date), payee(String) }
        let field: Field
        let message: String
        var id: String { message }
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
