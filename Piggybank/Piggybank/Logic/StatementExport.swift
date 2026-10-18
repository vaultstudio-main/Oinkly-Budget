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

/// Draws a statement as a PDF: a title block, a summary, then a table that carries on over as many pages as it needs,
/// repeating its column headings and ending each page with a footer. Plain black and grey, so it prints well.
@MainActor
enum StatementPDF {
    private struct Column {
        var title: String
        var width: CGFloat
        var rightAligned = false
        var text: (StatementLine) -> String
    }

    private static let margin: CGFloat = 40
    /// A fixed dark grey. System colours change with light and dark mode, which would make printed text pale.
    private static let grey = NSColor(white: 0.38, alpha: 1)
    private static let rowHeight: CGFloat = 15
    private static let footerHeight: CGFloat = 28

    static func render(_ statement: Statement, paper: PaperSize) -> Data {
        let page = paper.size
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        let info = [kCGPDFContextTitle: "\(statement.title), \(statement.subtitle)", kCGPDFContextCreator: "OinklyBudget"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info) else { return Data() }

        let columns = makeColumns(statement, usable: page.width - margin * 2)
        let money: (Decimal) -> String = { $0.formatted(.appCurrency) }

        // Where each page's rows come from. The first page has less room because of the title block.
        let headerBlock = headerHeight(statement)
        let bodyTop = margin + 14 + headerBlock + rowHeight + 4
        let firstCapacity = max(Int((page.height - footerHeight - margin - bodyTop) / rowHeight), 1)
        let laterTop = margin + rowHeight + 4
        let laterCapacity = max(Int((page.height - footerHeight - margin - laterTop) / rowHeight), 1)
        var pages: [Range<Int>] = []
        var index = 0
        var capacity = firstCapacity
        repeat {
            let end = min(index + capacity, statement.lines.count)
            pages.append(index..<end)
            index = end
            capacity = laterCapacity
        } while index < statement.lines.count

        let made = Date.now.formatted(.dateTime.month(.abbreviated).day().year())
        for (number, rows) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: page.height)
            context.scaleBy(x: 1, y: -1)
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

            var y = margin
            if number == 0 {
                y = drawHeader(statement, at: y, width: page.width - margin * 2, money: money)
            }
            y = drawColumnHeadings(columns, at: y, context: context)
            for line in statement.lines[rows] {
                drawRow(line, columns: columns, at: y, money: money)
                y += rowHeight
            }
            if statement.lines.isEmpty {
                draw("No transactions in this period.", in: CGRect(x: margin, y: y + 8, width: page.width - margin * 2, height: 16),
                     size: 10, color: grey)
            }
            drawFooter(left: "\(statement.title) · \(statement.subtitle) · made \(made)",
                       right: "Page \(number + 1) of \(pages.count)", page: page)

            NSGraphicsContext.current = previous
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: Layout

    private static func makeColumns(_ s: Statement, usable: CGFloat) -> [Column] {
        let day = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        var fixed: [Column] = [Column(title: "Date", width: 66) { $0.date.formatted(day) }]
        if s.showsAccount { fixed.append(Column(title: "Account", width: 84) { $0.account }) }
        let flexIndex = fixed.count
        let tail: [Column] = [
            Column(title: "Category", width: 92) { $0.category },
            Column(title: "Amount", width: 70, rightAligned: true) { $0.amount.formatted(.appCurrency) },
        ] + (s.showsBalance ? [Column(title: "Balance", width: 74, rightAligned: true) { $0.balance?.formatted(.appCurrency) ?? "" }] : [])
        let fixedWidth = fixed.reduce(0) { $0 + $1.width } + tail.reduce(0) { $0 + $1.width }
        let flexible = max(usable - fixedWidth, 120)
        let payee = Column(title: "Payee", width: flexible * 0.58) { $0.payee }
        let memo = Column(title: "Memo", width: flexible * 0.42) { $0.memo }
        var all = fixed
        all.insert(payee, at: flexIndex)
        all.insert(memo, at: flexIndex + 1)
        // Category sits after the memo so the long text columns stay together; the amounts end the row.
        all.append(contentsOf: tail)
        return all
    }

    private static func headerHeight(_ s: Statement) -> CGFloat { 22 + 18 + 12 + 34 + 12 }

    @discardableResult
    private static func drawHeader(_ s: Statement, at top: CGFloat, width: CGFloat, money: (Decimal) -> String) -> CGFloat {
        var y = top
        draw(s.title, in: CGRect(x: margin, y: y, width: width, height: 24), size: 19, weight: .bold)
        y += 22
        draw(s.subtitle, in: CGRect(x: margin, y: y + 2, width: width, height: 16), size: 11, color: grey)
        y += 18 + 12

        var items: [(String, String)] = []
        if s.showsBalance, let opening = s.openingBalance {
            items.append(("Opening balance", money(opening)))
            items.append(("Money in", money(s.moneyIn)))
            items.append(("Money out", money(s.moneyOut)))
            items.append(("Closing balance", money(s.closingBalance ?? opening)))
        } else {
            items.append(("Transactions", s.lines.count.formatted()))
            items.append(("In", money(s.moneyIn)))
            items.append(("Out", money(s.moneyOut)))
            items.append(("", "Transfers between accounts are not counted"))
        }
        let cell = width / CGFloat(items.count)
        for (offset, item) in items.enumerated() {
            let x = margin + cell * CGFloat(offset)
            if offset < 3 || s.showsBalance {
                draw(item.0, in: CGRect(x: x, y: y, width: cell - 8, height: 12), size: 8, color: grey)
                draw(item.1, in: CGRect(x: x, y: y + 12, width: cell - 8, height: 16), size: 12, weight: .semibold)
            } else {
                draw(item.1, in: CGRect(x: x, y: y + 12, width: cell - 8, height: 16), size: 7.5, color: grey)
            }
        }
        return y + 34 + 12
    }

    private static func drawColumnHeadings(_ columns: [Column], at y: CGFloat, context: CGContext) -> CGFloat {
        var x = margin
        for column in columns {
            draw(column.title.uppercased(), in: CGRect(x: x, y: y + 2, width: column.width - 6, height: rowHeight),
                 size: 7.5, weight: .semibold, color: grey, right: column.rightAligned)
            x += column.width
        }
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(0.8)
        context.move(to: CGPoint(x: margin, y: y + rowHeight))
        context.addLine(to: CGPoint(x: x - 6, y: y + rowHeight))
        context.strokePath()
        return y + rowHeight + 4
    }

    private static func drawRow(_ line: StatementLine, columns: [Column], at y: CGFloat, money: (Decimal) -> String) {
        var x = margin
        for column in columns {
            draw(column.text(line), in: CGRect(x: x, y: y + 1.5, width: column.width - 6, height: rowHeight),
                 size: 8.5, right: column.rightAligned)
            x += column.width
        }
        if let context = NSGraphicsContext.current?.cgContext {
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.12).cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: y + rowHeight))
            context.addLine(to: CGPoint(x: x - 6, y: y + rowHeight))
            context.strokePath()
        }
    }

    private static func drawFooter(left: String, right: String, page: CGSize) {
        let y = page.height - margin + 6
        let width = page.width - margin * 2
        draw(left, in: CGRect(x: margin, y: y, width: width * 0.75, height: 12), size: 7.5, color: grey)
        draw(right, in: CGRect(x: margin + width * 0.75, y: y, width: width * 0.25, height: 12), size: 7.5,
             color: grey, right: true)
    }

    private static func draw(_ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
                             color: NSColor = .black, right: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = right ? .right : .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }
}
