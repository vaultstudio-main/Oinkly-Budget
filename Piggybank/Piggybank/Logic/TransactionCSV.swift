import Foundation
import SwiftData

/// Transactions as a spreadsheet (CSV): export every transaction, or split a file into rows. Reading a bank's file into
/// transactions is in `StatementImport.swift`.
enum TransactionCSV {
    static let header = ["Date", "Account", "Payee", "Category", "Memo", "Amount", "Status", "Transfer"]

    // MARK: Export

    /// The given transactions as CSV, in the same layout the importer reads, so an export can be brought back in.
    @MainActor
    static func text(for transactions: [Transaction]) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"

        var lines = [header.map(escape).joined(separator: ",")]
        for t in transactions {
            // A split goes out as one row per part, with the same date and payee, so the rows add up by category.
            let ordered = t.isSplit ? t.splits.sorted { $0.order < $1.order } : []
            let parts: [(category: Category?, amount: Decimal, memo: String)] = ordered.isEmpty
                ? [(t.category, t.amount, t.memo)]
                : ordered.map { ($0.category, $0.amount, $0.memo.isEmpty ? t.memo : $0.memo) }
            for part in parts {
                let fields = [
                    day.string(from: t.date),
                    t.account?.name ?? "",
                    t.payee,
                    part.category?.isLive == true ? (part.category?.name ?? "") : "",
                    part.memo,
                    "\(part.amount)",
                    t.status.rawValue,
                    t.transferID?.uuidString ?? "",
                ]
                lines.append(fields.map(escape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Reading

    /// Splits CSV text into rows of fields, honouring quotes, doubled quotes and line breaks inside quotes.
    static func parse(_ text: String, delimiter: Character = ",") -> [[String]] {
        let separator = delimiter.unicodeScalars.first ?? ","
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
                case separator: row.append(field); field = ""
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
}
