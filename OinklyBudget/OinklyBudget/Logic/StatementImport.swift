import Foundation
import SwiftData

/// Reading any bank's CSV file. The person can tell the app which column is which, how dates and amounts are written,
/// and where the header is; the app guesses all of it first. Nothing here touches the database until `StatementImporter.add`.

enum AmountStyle: String, Codable, CaseIterable, Identifiable {
    /// One Amount column, negative for money out.
    case signed
    /// Separate Debit (money out) and Credit (money in) columns.
    case debitCredit

    var id: Self { self }
    var title: String { self == .signed ? "One Amount column" : "Debit and Credit columns" }
}

/// A date format a bank might use. `auto` picks whichever reads the most rows.
struct DateStyle: Hashable, Identifiable, Codable {
    var format: String
    var title: String
    var id: String { format }

    static let auto = DateStyle(format: "auto", title: "Detect automatically")
    static let all: [DateStyle] = [
        auto,
        DateStyle(format: "M/d/yyyy", title: "Month/Day/Year (10/31/2026)"),
        DateStyle(format: "d/M/yyyy", title: "Day/Month/Year (31/10/2026)"),
        DateStyle(format: "yyyy-MM-dd", title: "Year-Month-Day (2026-10-31)"),
        DateStyle(format: "M/d/yy", title: "Month/Day/short year (10/31/26)"),
        DateStyle(format: "d/M/yy", title: "Day/Month/short year (31/10/26)"),
        DateStyle(format: "MM-dd-yyyy", title: "Month-Day-Year (10-31-2026)"),
        DateStyle(format: "dd-MM-yyyy", title: "Day-Month-Year (31-10-2026)"),
        DateStyle(format: "dd.MM.yyyy", title: "Day.Month.Year (31.10.2026)"),
        DateStyle(format: "d MMM yyyy", title: "31 Oct 2026"),
        DateStyle(format: "MMM d, yyyy", title: "Oct 31, 2026"),
        DateStyle(format: "yyyyMMdd", title: "20261031"),
    ]
}

/// How one kind of file is read. Columns are positions in each row, counted from 0.
struct ImportLayout: Codable, Equatable {
    var delimiter = ","
    /// The row holding the column names, counted from 0. Nil when the file has none.
    var headerRow: Int? = 0
    var dateStyle = DateStyle.auto
    var amountStyle = AmountStyle.signed
    /// Credit card files often show charges as positive numbers.
    var flipSign = false
    /// 1.234,56 instead of 1,234.56.
    var commaDecimal = false

    var dateColumn: Int?
    var payeeColumn: Int?
    var memoColumn: Int?
    var categoryColumn: Int?
    var amountColumn: Int?
    var debitColumn: Int?
    var creditColumn: Int?
    var accountColumn: Int?
    var statusColumn: Int?
    var transferColumn: Int?
}

/// A layout the person saved under a name, used again automatically when a file has the same column names.
struct SavedImportLayout: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var headers: [String]
    var layout: ImportLayout

    /// Kept in the database, so everyone who shares the data has the same saved layouts.
    static func load() -> [SavedImportLayout] {
        guard !ScreenshotMode.isOn, let context = OinklyBudgetAppDelegate.container?.mainContext else { return [] }
        return SettingsRecords.importLayouts(in: context)
    }

    static func store(_ layouts: [SavedImportLayout]) {
        guard !ScreenshotMode.isOn, let context = OinklyBudgetAppDelegate.container?.mainContext else { return }
        SettingsRecords.setImportLayouts(layouts, in: context)
        context.saveNow()
    }

    static func normalized(_ headers: [String]) -> [String] {
        headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }
}

struct ImportRow: Identifiable {
    /// The row's position in the file, counted from 1, as a person would count it.
    var id: Int
    var date: Date?
    var payee = ""
    var memo = ""
    var categoryName = ""
    var amount: Decimal?
    var accountName = ""
    var status = ClearedStatus.uncleared
    var transferID: UUID?
    var problem: String?

    var isUsable: Bool { date != nil && amount != nil }
}

struct ParsedStatement {
    var rows: [ImportRow] = []
    /// The date format used, when it was detected rather than chosen.
    var detectedDateFormat: String?
    /// Dates that could be month first or day first, where month first was assumed.
    var dateIsAmbiguous = false

    var usable: [ImportRow] { rows.filter(\.isUsable) }
    var problems: [ImportRow] { rows.filter { !$0.isUsable } }
}

/// Where a row would go and whether it is already there, worked out for the preview and used by the import.
struct PlannedRow: Identifiable {
    var row: ImportRow
    var account: Account?
    var isDuplicate: Bool
    var id: Int { row.id }
}

enum StatementImporter {
    // MARK: Reading the file

    /// Text from a file's bytes, trying the encodings banks use.
    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return text }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
    }

    /// The separator that splits the first lines into the most (and a steady number of) fields.
    static func detectDelimiter(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).prefix(12).map(String.init)
        var best = (",", 0)
        for candidate in [",", ";", "\t", "|"] {
            let counts = lines.map { TransactionCSV.parse($0, delimiter: Character(candidate)).first?.count ?? 0 }
            let reference = counts.first { $0 > 1 }
            let steady = counts.filter { $0 > 1 && $0 == reference }.count
            if steady > best.1 { best = (candidate, steady) }
        }
        return best.0
    }

    // MARK: Guessing the layout

    private static let dateNames = ["date", "transaction date", "posted date", "posting date", "post date", "trans date", "trans. date", "booking date", "effective date", "settlement date", "datum", "buchungstag", "buchungsdatum", "valuta", "fecha"]
    private static let payeeNames = ["payee", "description", "name", "merchant", "memo/description", "details", "transaction description", "narrative", "reference", "original description", "beschreibung", "verwendungszweck", "buchungstext", "concepto", "details"]
    private static let memoNames = ["memo", "notes", "note", "comment", "comments", "extended details"]
    private static let categoryNames = ["category", "transaction category"]
    private static let amountNames = ["amount", "transaction amount", "value", "amt", "betrag", "importe"]
    private static let debitNames = ["debit", "debits", "withdrawal", "withdrawals", "money out", "paid out", "debit amount", "soll", "ausgaben", "cargo"]
    private static let creditNames = ["credit", "credits", "deposit", "deposits", "money in", "paid in", "credit amount", "haben", "einnahmen", "abono"]
    private static let accountNames = ["account", "account name"]
    private static let statusNames = ["status", "cleared"]
    private static let transferNames = ["transfer", "transfer id"]

    /// The row that holds column names: the last row of text before the first row that has a date in it.
    static func guessHeaderRow(_ table: [[String]]) -> Int? {
        for (index, row) in table.prefix(30).enumerated() {
            let hasDate = row.contains { parseDate($0, format: nil) != nil }
            if hasDate { return index == 0 ? nil : index - 1 }
        }
        return table.isEmpty ? nil : 0
    }

    static func guessLayout(_ table: [[String]], delimiter: String) -> ImportLayout {
        var layout = ImportLayout()
        layout.delimiter = delimiter
        layout.headerRow = guessHeaderRow(table)
        let body = dataRows(table, headerRow: layout.headerRow)

        if let headerRow = layout.headerRow, headerRow < table.count {
            let head = table[headerRow].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            // Earlier names in each list win, so "Description" beats "Details" when a file has both.
            func find(_ names: [String]) -> Int? {
                for name in names { if let index = head.firstIndex(of: name) { return index } }
                return nil
            }
            layout.dateColumn = find(dateNames)
            layout.payeeColumn = find(payeeNames)
            layout.memoColumn = find(memoNames)
            layout.categoryColumn = find(categoryNames)
            layout.amountColumn = find(amountNames)
            layout.debitColumn = find(debitNames)
            layout.creditColumn = find(creditNames)
            layout.accountColumn = find(accountNames)
            layout.statusColumn = find(statusNames)
            layout.transferColumn = find(transferNames)
        }

        // Fill in what the names didn't give, from what the columns hold.
        let width = body.map(\.count).max() ?? 0
        let samples = Array(body.prefix(60))
        func cells(_ column: Int) -> [String] {
            samples.compactMap { column < $0.count ? $0[column].trimmingCharacters(in: .whitespacesAndNewlines) : nil }.filter { !$0.isEmpty }
        }
        var taken = Set([layout.dateColumn, layout.payeeColumn, layout.memoColumn, layout.categoryColumn, layout.amountColumn,
                         layout.debitColumn, layout.creditColumn, layout.accountColumn, layout.statusColumn, layout.transferColumn].compactMap { $0 })
        if layout.dateColumn == nil {
            let best = (0..<width).filter { !taken.contains($0) }.max { dateScore(cells($0)) < dateScore(cells($1)) }
            if let best, dateScore(cells(best)) > 0.6 { layout.dateColumn = best; taken.insert(best) }
        }
        if layout.amountColumn == nil, layout.debitColumn == nil, layout.creditColumn == nil {
            let numeric = (0..<width).filter { !taken.contains($0) }.filter { numberScore(cells($0)) > 0.8 }
            // The last numeric column is usually the amount (a running balance, if any, comes after it, so take the one before).
            if let amount = numeric.first { layout.amountColumn = amount; taken.insert(amount) }
        }
        if layout.payeeColumn == nil {
            let texts = (0..<width).filter { !taken.contains($0) }.filter { numberScore(cells($0)) < 0.3 && dateScore(cells($0)) < 0.3 }
            let longest = texts.max { averageLength(cells($0)) < averageLength(cells($1)) }
            if let longest, averageLength(cells(longest)) > 0 { layout.payeeColumn = longest }
        }
        if layout.amountColumn == nil, layout.debitColumn != nil || layout.creditColumn != nil { layout.amountStyle = .debitCredit }
        let moneyCells = [layout.amountColumn, layout.debitColumn, layout.creditColumn].compactMap { $0 }.flatMap { cells($0) }
        let commaStyle = moneyCells.filter { $0.range(of: #",\d{1,2}\)?$"#, options: .regularExpression) != nil }.count
        let dotStyle = moneyCells.filter { $0.range(of: #"\.\d{1,2}\)?$"#, options: .regularExpression) != nil }.count
        layout.commaDecimal = commaStyle > 0 && dotStyle == 0
        return layout
    }

    private static func dateScore(_ values: [String]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.filter { parseDate($0, format: nil) != nil }.count) / Double(values.count)
    }

    private static func numberScore(_ values: [String]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.filter { parseAmount($0, commaDecimal: false) != nil || parseAmount($0, commaDecimal: true) != nil }.count) / Double(values.count)
    }

    private static func averageLength(_ values: [String]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0) { $0 + $1.count }) / Double(values.count)
    }

    /// The rows after the header (or all rows when there is no header), each with its position in the file.
    static func dataRows(_ table: [[String]], headerRow: Int?) -> [[String]] {
        let start = (headerRow ?? -1) + 1
        return start < table.count ? Array(table[start...]) : []
    }

    // MARK: Dates and amounts

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    /// Drops a time of day after the date, such as "2026-10-31T09:30:00Z" or "10/31/2026 9:30 PM".
    private static func dateText(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: #"[T\s]\d{1,2}:\d{2}.*$"#, options: .regularExpression) { s.removeSubrange(range) }
        return s
    }

    /// Reads a date with the given format, or with the common ones when no format is given.
    static func parseDate(_ text: String, format: String?) -> Date? {
        let s = dateText(text)
        guard !s.isEmpty else { return nil }
        let formats = format.map { [$0] } ?? DateStyle.all.dropFirst().map(\.format)
        for candidate in formats {
            if let date = formatter(candidate).date(from: s), Calendar.current.component(.year, from: date) >= 1900 {
                return Calendar.current.startOfDay(for: date)
            }
        }
        return nil
    }

    /// Which format reads the most of these dates. Month first wins when it can't be told apart from day first.
    static func detectDateFormat(_ values: [String]) -> (format: String, ambiguous: Bool)? {
        let sample = Array(values.prefix(300))
        guard !sample.isEmpty else { return nil }
        var best: (format: String, count: Int)?
        var counts: [String: Int] = [:]
        for style in DateStyle.all.dropFirst() {
            let f = formatter(style.format)
            let shape = formatShape(style.format)
            let count = sample.filter { value in
                let s = dateText(value)
                guard textShape(s) == shape, let date = f.date(from: s) else { return false }
                return Calendar.current.component(.year, from: date) >= 1900
            }.count
            counts[style.format] = count
            if count > (best?.count ?? 0) { best = (style.format, count) }
        }
        guard let best, best.count > 0 else { return nil }
        let ambiguous = (best.format == "M/d/yyyy" && counts["d/M/yyyy"] == best.count)
            || (best.format == "M/d/yy" && counts["d/M/yy"] == best.count)
            || (best.format == "MM-dd-yyyy" && counts["dd-MM-yyyy"] == best.count)
        return (best.format, ambiguous)
    }

    /// "M/d/yyyy" becomes "0/0/0": digits and letters collapse, separators stay, so "31.10.2026" can't pass for "d/M/yyyy".
    private static func formatShape(_ format: String) -> String {
        var s = format.replacingOccurrences(of: "MMM", with: "A")
        s = s.replacingOccurrences(of: #"[dMy]+"#, with: "0", options: .regularExpression)
        return s
    }

    private static func textShape(_ text: String) -> String {
        var s = text.replacingOccurrences(of: #"\d+"#, with: "0", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[A-Za-z]+"#, with: "A", options: .regularExpression)
        return s
    }

    static func parseAmount(_ text: String, commaDecimal: Bool) -> Decimal? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var negative = false
        let upper = s.uppercased()
        if upper.hasSuffix("DR") { negative = true; s = String(s.dropLast(2)) } else if upper.hasSuffix("CR") { s = String(s.dropLast(2)) }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("(") && s.hasSuffix(")") { negative.toggle(); s = String(s.dropFirst().dropLast()) }
        if s.hasSuffix("-") { negative.toggle(); s = String(s.dropLast()) }
        s = s.filter { !"$£€¥ \u{00A0}".contains($0) }
        if commaDecimal {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            s = s.replacingOccurrences(of: ",", with: "")
        }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() }
        if s.hasPrefix("+") { s.removeFirst() }
        // One decimal point at most: "1.234.567" is not an amount, and reading its first part would be a wrong one.
        guard !s.isEmpty, s.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." }), s.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    // MARK: Reading rows

    static func parse(_ table: [[String]], layout: ImportLayout) -> ParsedStatement {
        var result = ParsedStatement()
        let firstDataRow = (layout.headerRow ?? -1) + 1
        guard firstDataRow < table.count else { return result }
        let body = Array(table[firstDataRow...])

        func value(_ row: [String], _ column: Int?) -> String {
            guard let column, column >= 0, column < row.count else { return "" }
            return row[column].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var dateFormat: String? = layout.dateStyle.format == "auto" ? nil : layout.dateStyle.format
        if dateFormat == nil, let dateColumn = layout.dateColumn,
           let detected = detectDateFormat(body.map { value($0, dateColumn) }.filter { !$0.isEmpty }) {
            dateFormat = detected.format
            result.detectedDateFormat = detected.format
            result.dateIsAmbiguous = detected.ambiguous
        }

        for (offset, row) in body.enumerated() {
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            var item = ImportRow(id: firstDataRow + offset + 1)
            item.accountName = value(row, layout.accountColumn)
            item.payee = value(row, layout.payeeColumn)
            item.memo = value(row, layout.memoColumn)
            item.categoryName = value(row, layout.categoryColumn)
            item.status = ClearedStatus(rawValue: value(row, layout.statusColumn).lowercased()) ?? .uncleared
            item.transferID = UUID(uuidString: value(row, layout.transferColumn))

            let dateText = value(row, layout.dateColumn)
            item.date = dateFormat.flatMap { parseDate(dateText, format: $0) }
            if item.date == nil { item.problem = dateText.isEmpty ? "No date" : "Date “\(dateText)” isn't in the chosen format" }

            switch layout.amountStyle {
            case .signed:
                let text = value(row, layout.amountColumn)
                item.amount = parseAmount(text, commaDecimal: layout.commaDecimal)
                if item.amount == nil, item.problem == nil { item.problem = text.isEmpty ? "No amount" : "Amount “\(text)” can't be read" }
            case .debitCredit:
                let debit = parseAmount(value(row, layout.debitColumn), commaDecimal: layout.commaDecimal)
                let credit = parseAmount(value(row, layout.creditColumn), commaDecimal: layout.commaDecimal)
                if let debit, debit != 0 { item.amount = -abs(debit) } else if let credit { item.amount = abs(credit) } else if let debit { item.amount = debit }
                if item.amount == nil, item.problem == nil { item.problem = "No debit or credit amount" }
            }
            if layout.flipSign, let amount = item.amount { item.amount = -amount }
            result.rows.append(item)
        }
        return result
    }

    // MARK: Cleaning up bank text

    /// Bank descriptions are full of noise: card prefixes, store numbers, long digit runs, repeated spaces.
    static func tidy(_ payee: String) -> String {
        var s = payee
        for prefix in ["POS DEBIT ", "POS PURCHASE ", "DEBIT CARD PURCHASE ", "CHECKCARD ", "CHECK CARD ", "PURCHASE AUTHORIZED ON ", "VISA DEBIT ", "SQ *", "TST* ", "PAYPAL *"] {
            if s.uppercased().hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        s = s.replacingOccurrences(of: #"\s+\d{2}/\d{2}\b.*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*#\s*\d+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b\d{5,}\b"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "*-")))
        // ALL CAPS text reads better as words.
        if s == s.uppercased(), s.contains(where: \.isLetter) { s = s.capitalized }
        return s.isEmpty ? payee : s
    }

    // MARK: Planning and importing

    @MainActor
    private static func key(_ date: Date, _ account: Account, _ payee: String, _ amount: Decimal) -> String {
        "\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)|\(account.persistentModelID.hashValue)|\(payee.lowercased())|\(amount)"
    }

    /// Where each usable row would go, and whether the same transaction is already there.
    /// With `account` set, every row goes to it. Otherwise rows go to the account their name column names, else `fallback`.
    @MainActor
    static func plan(_ rows: [ImportRow], account: Account?, fallback: Account?, tidyPayees: Bool, in context: ModelContext) -> [PlannedRow] {
        let usable = rows.filter(\.isUsable)
        guard let first = usable.compactMap(\.date).min(), let last = usable.compactMap(\.date).max() else { return [] }
        let accounts = ((try? context.fetch(FetchDescriptor<Account>())) ?? []).live
        var byName: [String: Account] = [:]
        for candidate in accounts { byName[candidate.name.lowercased()] = candidate }

        let end = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last
        let existing = ((try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.date >= first && $0.date < end }))) ?? []).live
        var counts: [String: Int] = [:]
        for t in existing {
            guard let owner = t.account, owner.isLive else { continue }
            counts[key(t.date, owner, t.payee, t.amount), default: 0] += 1
        }

        return usable.map { row in
            let target = account ?? byName[row.accountName.lowercased()] ?? fallback
            var isDuplicate = false
            if let target, let date = row.date, let amount = row.amount {
                let k = key(date, target, tidyPayees ? tidy(row.payee) : row.payee, amount)
                if let count = counts[k], count > 0 { counts[k] = count - 1; isDuplicate = true }
            }
            return PlannedRow(row: row, account: target, isDuplicate: isDuplicate)
        }
    }

    struct ImportResult {
        var added = 0
        var duplicatesSkipped = 0
        var uncategorized = 0
        var ids: [PersistentIdentifier] = []
    }

    @MainActor
    static func add(_ planned: [PlannedRow], skipDuplicates: Bool, tidyPayees: Bool, fillCategories: Bool, in context: ModelContext) throws -> ImportResult {
        let categories = ((try? context.fetch(FetchDescriptor<Category>())) ?? []).live
        var categoriesByName: [String: Category] = [:]
        for category in categories { categoriesByName[category.name.lowercased()] = category }
        let payees = fillCategories ? ((try? context.fetch(FetchDescriptor<Payee>())) ?? []) : []

        var result = ImportResult()
        var inserted: [Transaction] = []
        for item in planned {
            guard let account = item.account, let date = item.row.date, let amount = item.row.amount else { continue }
            if skipDuplicates && item.isDuplicate { result.duplicatesSkipped += 1; continue }
            let payee = tidyPayees ? tidy(item.row.payee) : item.row.payee
            var category = item.row.categoryName.isEmpty ? nil : categoriesByName[item.row.categoryName.lowercased()]
            if category == nil && !item.row.categoryName.isEmpty { result.uncategorized += 1 }
            if category == nil, fillCategories, let remembered = PayeeMemory.exactMatch(for: payee, in: payees)?.lastCategory, remembered.isLive {
                category = remembered
            }
            let t = Transaction(account: account, date: date, payee: payee, category: category, memo: item.row.memo, amount: amount)
            t.status = item.row.status
            t.transferID = item.row.transferID
            context.insert(t)
            inserted.append(t)
            result.added += 1
        }
        try context.save()
        result.ids = inserted.map(\.persistentModelID)
        ImportHistory.last = ImportHistory.Entry(ids: result.ids, label: "\(result.added) transaction\(result.added == 1 ? "" : "s")")
        return result
    }
}

/// The most recent import, kept until the app quits so it can be undone. Nothing is stored in the database for this.
@MainActor
enum ImportHistory {
    struct Entry {
        var ids: [PersistentIdentifier]
        var label: String
    }

    static var last: Entry?

    /// Removes what the last import added, except anything that has already gone. Returns how many were removed.
    @discardableResult
    static func undo(in context: ModelContext) -> Int {
        guard let entry = last else { return 0 }
        let wanted = Set(entry.ids)
        var removed = 0
        let all = ((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).live
        for t in all where wanted.contains(t.persistentModelID) {
            context.delete(t)
            removed += 1
        }
        try? context.save()
        last = nil
        return removed
    }
}
