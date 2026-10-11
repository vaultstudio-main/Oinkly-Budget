import Foundation
import SwiftData

/// Transactions as a spreadsheet (CSV): export every transaction, or bring rows in from another program or a bank.
enum TransactionCSV {
    static let header = ["Date", "Account", "Payee", "Category", "Memo", "Amount", "Status", "Transfer"]

    // MARK: Export

    @MainActor
    static func export(from context: ModelContext) throws -> String {
        let transactions = try context.fetch(FetchDescriptor<Transaction>()).live
            .filter { $0.account?.isLive == true }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"

        var lines = [header.map(escape).joined(separator: ",")]
        for t in transactions {
            let fields = [
                day.string(from: t.date),
                t.account?.name ?? "",
                t.payee,
                t.category?.isLive == true ? (t.category?.name ?? "") : "",
                t.memo,
                "\(t.amount)",
                t.status.rawValue,
                t.transferID?.uuidString ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Reading

    /// Splits CSV text into rows of fields, honouring quotes, doubled quotes and line breaks inside quotes.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.unicodeScalars)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var index = 0
        while index < chars.count {
            let c = chars[index]
            if inQuotes {
                if c == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" { field.unicodeScalars.append("\""); index += 1 }
                    else { inQuotes = false }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                case "\r": break
                default: field.unicodeScalars.append(c)
                }
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    /// One row, read into real values. `accountName` is empty when the file has no account column.
    struct Row {
        var date: Date
        var accountName: String
        var payee: String
        var categoryName: String
        var memo: String
        var amount: Decimal
        var status: ClearedStatus
        var transferID: UUID?
    }

    struct Parsed {
        var rows: [Row] = []
        var skipped = 0
        /// Why the file can't be used at all, if it can't.
        var problem: String?
        var hasAccountColumn = false
    }

    static func read(_ text: String) -> Parsed {
        var result = Parsed()
        let table = parse(text)
        guard let head = table.first else { result.problem = "The file is empty."; return result }

        func column(_ names: [String]) -> Int? {
            head.firstIndex { names.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) }
        }
        let dateCol = column(["date", "transaction date", "posted date", "posting date"])
        let accountCol = column(["account", "account name"])
        let payeeCol = column(["payee", "description", "name", "merchant", "memo/description"])
        let categoryCol = column(["category"])
        let memoCol = column(["memo", "notes", "note"])
        let amountCol = column(["amount"])
        let debitCol = column(["debit", "withdrawal", "withdrawals"])
        let creditCol = column(["credit", "deposit", "deposits"])
        let statusCol = column(["status"])
        let transferCol = column(["transfer", "transfer id"])

        guard let dateCol else { result.problem = "No Date column found. The first row should name each column, such as Date, Payee and Amount."; return result }
        guard amountCol != nil || debitCol != nil || creditCol != nil else {
            result.problem = "No Amount column found. Add a column called Amount, or Debit and Credit."
            return result
        }
        result.hasAccountColumn = accountCol != nil

        func value(_ row: [String], _ col: Int?) -> String {
            guard let col, col < row.count else { return "" }
            return row[col].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for row in table.dropFirst() {
            guard let date = parseDate(value(row, dateCol)) else { result.skipped += 1; continue }
            var amount: Decimal?
            if amountCol != nil {
                amount = parseAmount(value(row, amountCol))
            } else {
                let debit = parseAmount(value(row, debitCol))
                let credit = parseAmount(value(row, creditCol))
                if let debit, debit != 0 { amount = -abs(debit) } else if let credit { amount = abs(credit) }
            }
            guard let amount else { result.skipped += 1; continue }
            result.rows.append(Row(
                date: date,
                accountName: value(row, accountCol),
                payee: value(row, payeeCol),
                categoryName: value(row, categoryCol),
                memo: value(row, memoCol),
                amount: amount,
                status: ClearedStatus(rawValue: value(row, statusCol).lowercased()) ?? .uncleared,
                transferID: UUID(uuidString: value(row, transferCol))
            ))
        }
        return result
    }

    private static let dateFormats = ["yyyy-MM-dd", "M/d/yyyy", "M/d/yy", "MM-dd-yyyy", "d MMM yyyy", "MMM d, yyyy", "yyyy/MM/dd", "yyyy-MM-dd'T'HH:mm:ssZ"]

    static func parseDate(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return Calendar.current.startOfDay(for: date) }
        }
        return nil
    }

    static func parseAmount(_ text: String) -> Decimal? {
        var s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        if s.hasSuffix("-") { negative = true; s = String(s.dropLast()) }
        s = s.filter { !"$£€, ".contains($0) }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() }
        if s.hasPrefix("+") { s.removeFirst() }
        guard let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    // MARK: Importing

    struct ImportResult {
        var added = 0
        var duplicates = 0
        var uncategorized = 0
    }

    /// Adds the rows. Each row goes to the account named in the file, or `defaultAccount` when it names none that exists.
    /// With `skipDuplicates`, a row that matches an existing transaction (same day, account, payee and amount) is left out.
    @MainActor
    static func add(_ rows: [Row], defaultAccount: Account?, skipDuplicates: Bool, in context: ModelContext) throws -> ImportResult {
        let accounts = try context.fetch(FetchDescriptor<Account>()).live
        let categories = try context.fetch(FetchDescriptor<Category>()).live
        var accountsByName: [String: Account] = [:]
        for account in accounts { accountsByName[account.name.lowercased()] = account }
        var categoriesByName: [String: Category] = [:]
        for category in categories { categoriesByName[category.name.lowercased()] = category }

        func key(_ date: Date, _ account: Account, _ payee: String, _ amount: Decimal) -> String {
            "\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)|\(account.persistentModelID.hashValue)|\(payee.lowercased())|\(amount)"
        }
        var existing: [String: Int] = [:]
        if skipDuplicates {
            for t in try context.fetch(FetchDescriptor<Transaction>()).live {
                guard let account = t.account, account.isLive else { continue }
                existing[key(t.date, account, t.payee, t.amount), default: 0] += 1
            }
        }

        var result = ImportResult()
        for row in rows {
            guard let account = accountsByName[row.accountName.lowercased()] ?? defaultAccount else { continue }
            if skipDuplicates {
                let k = key(row.date, account, row.payee, row.amount)
                if let count = existing[k], count > 0 { existing[k] = count - 1; result.duplicates += 1; continue }
            }
            let category = row.categoryName.isEmpty ? nil : categoriesByName[row.categoryName.lowercased()]
            if category == nil && !row.categoryName.isEmpty { result.uncategorized += 1 }
            let t = Transaction(account: account, date: row.date, payee: row.payee, category: category, memo: row.memo, amount: row.amount)
            t.status = row.status
            t.transferID = row.transferID
            context.insert(t)
            result.added += 1
        }
        try context.save()
        return result
    }
}
