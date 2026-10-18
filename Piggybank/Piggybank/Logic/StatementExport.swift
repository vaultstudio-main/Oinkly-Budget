import AppKit
import SwiftData

/// How much to export: one month, a year, every transaction, or a pair of dates. Dates are whole days, and `end` is
/// the first instant after the last day, so a month is simply start-of-month up to start-of-next-month.
struct ExportPeriod: Equatable {
    var start: Date
    var end: Date
    var label: String

    static let all = ExportPeriod(start: .distantPast, end: .distantFuture, label: "All Transactions")

    var isAll: Bool { start == .distantPast && end == .distantFuture }

    static func month(_ month: Date, calendar: Calendar = .current) -> ExportPeriod {
        let start = MonthFilter.start(of: month, calendar: calendar)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return ExportPeriod(start: start, end: end, label: start.formatted(.dateTime.month(.wide).year()))
    }

    static func year(_ year: Int, calendar: Calendar = .current) -> ExportPeriod {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return ExportPeriod(start: start, end: end, label: String(year))
    }

    /// `from` and `to` are both included, so the end moves to the start of the day after `to`.
    static func dates(from: Date, to: Date, calendar: Calendar = .current) -> ExportPeriod {
        let first = calendar.startOfDay(for: min(from, to))
        let last = calendar.startOfDay(for: max(from, to))
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        return ExportPeriod(start: first, end: end, label: "\(first.formatted(style)) to \(last.formatted(style))")
    }
}

enum PaperSize: String, CaseIterable, Identifiable {
    case letter, a4

    var id: Self { self }
    var title: String { self == .letter ? "US Letter" : "A4" }
    var size: CGSize { self == .letter ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842) }

    /// The paper most people in the current region use.
    static var regional: PaperSize {
        Locale.current.measurementSystem == .us ? .letter : .a4
    }
}

/// One line of a statement, read once from a transaction so the drawing code never touches the database.
struct StatementLine {
    var date: Date
    var account: String
    var payee: String
    var category: String
    var memo: String
    var amount: Decimal
    var status: String
    var isTransfer: Bool
    var balance: Decimal?
}

/// Everything a statement shows. Built from the database on the main thread, then drawn to PDF or written as CSV.
struct Statement {
    var title: String
    var subtitle: String
    /// The accounts column is shown when the statement spans more than one account.
    var showsAccount: Bool
    /// A running balance only makes sense for a single account.
    var showsBalance: Bool
    var openingBalance: Decimal?
    var lines: [StatementLine]
    /// The transactions themselves, for writing a CSV.
    var transactions: [Transaction]

    var moneyIn: Decimal {
        lines.filter { showsBalance || !$0.isTransfer }.reduce(0) { $1.amount > 0 ? $0 + $1.amount : $0 }
    }

    var moneyOut: Decimal {
        lines.filter { showsBalance || !$0.isTransfer }.reduce(0) { $1.amount < 0 ? $0 - $1.amount : $0 }
    }

    var closingBalance: Decimal? { lines.last?.balance ?? openingBalance }
}

enum StatementBuilder {
    /// Transactions in the period, for one account or (with `account` nil) all of them, oldest first.
    @MainActor
    static func transactions(account: Account?, period: ExportPeriod, in context: ModelContext) -> [Transaction] {
        let start = period.start
        let end = period.end
        let predicate: Predicate<Transaction>
        if let id = account?.persistentModelID {
            predicate = #Predicate<Transaction> { $0.date >= start && $0.date < end && $0.account?.persistentModelID == id }
        } else {
            predicate = #Predicate<Transaction> { $0.date >= start && $0.date < end }
        }
        let found = (try? context.fetch(FetchDescriptor<Transaction>(predicate: predicate))) ?? []
        return found.filter { $0.isLive && $0.account?.isLive == true }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    private static func categoryTitle(_ transaction: Transaction) -> String {
        if transaction.account?.supportsHoldings == true { return InvestmentType.of(transaction).title }
        if let fixed = transaction.fixedCategoryTitle { return fixed }
        if let split = transaction.splitTitle { return split }
        return transaction.category?.isLive == true ? (transaction.category?.name ?? "") : ""
    }

    @MainActor
    static func make(account: Account?, period: ExportPeriod, in context: ModelContext) -> Statement {
        let found = transactions(account: account, period: period, in: context)
        var running: Decimal?
        if let account {
            running = period.isAll ? account.openingBalance : account.balance(asOf: period.start.addingTimeInterval(-0.001))
        }
        let opening = running
        let lines = found.map { transaction -> StatementLine in
            if let current = running { running = current + transaction.amount }
            return StatementLine(
                date: transaction.date,
                account: transaction.account?.name ?? "",
                payee: transaction.payee,
                category: categoryTitle(transaction),
                memo: transaction.memo,
                amount: transaction.amount,
                status: transaction.state.title,
                isTransfer: transaction.isTransfer,
                balance: running)
        }
        return Statement(
            title: account?.name ?? "Transactions",
            subtitle: account == nil ? "All accounts · \(period.label)" : period.label,
            showsAccount: account == nil,
            showsBalance: account != nil,
            openingBalance: opening,
            lines: lines,
            transactions: found)
    }
}

/// A statement as a document: the title block, the headline figures, then the table of transactions.
@MainActor
enum StatementPDF {
    static func document(for s: Statement) -> ExportDocument {
        let money: (Decimal) -> String = { $0.formatted(.appCurrency) }
        let day = Date.FormatStyle.dateTime.month(.abbreviated).day().year()

        var summary: [(label: String, value: String)]
        if s.showsBalance, let opening = s.openingBalance {
            summary = [("Opening balance", money(opening)), ("Money in", money(s.moneyIn)), ("Money out", money(s.moneyOut)),
                       ("Closing balance", money(s.closingBalance ?? opening))]
        } else {
            summary = [("Transactions", s.lines.count.formatted()), ("In", money(s.moneyIn)), ("Out", money(s.moneyOut))]
        }

        var columns: [DocColumn] = [.fixed("Date", 66)]
        if s.showsAccount { columns.append(.fixed("Account", 84)) }
        columns += [.flexible("Payee", 0.58), .flexible("Memo", 0.42), .fixed("Category", 92), .fixed("Amount", 70, right: true)]
        if s.showsBalance { columns.append(.fixed("Balance", 74, right: true)) }

        let rows = s.lines.map { line -> [String] in
            var row = [line.date.formatted(day)]
            if s.showsAccount { row.append(line.account) }
            row += [line.payee, line.memo, line.category, money(line.amount)]
            if s.showsBalance { row.append(line.balance.map(money) ?? "") }
            return row
        }

        var sections: [DocSection] = []
        if !s.showsBalance { sections.append(.text("Transfers between accounts are not counted in In and Out.")) }
        sections.append(.table(DocTable(columns: columns, rows: rows, emptyNote: "No transactions in this period.")))
        return ExportDocument(title: s.title, subtitle: s.subtitle, summary: summary, sections: sections)
    }

    static func render(_ statement: Statement, paper: PaperSize) -> Data {
        DocumentPDF.render(document(for: statement), paper: paper)
    }
}
