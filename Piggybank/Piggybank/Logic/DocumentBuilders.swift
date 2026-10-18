import AppKit
import SwiftData
import UniformTypeIdentifiers

/// Turns what the app knows into an `ExportDocument` for each thing that can be exported to PDF. To print any of
/// them, open the PDF and print it from Preview.
@MainActor
enum DocumentBuilders {
    private static let money: (Decimal) -> String = { $0.formatted(.appCurrency) }
    private static let day = Date.FormatStyle.dateTime.month(.abbreviated).day().year()

    // MARK: One transaction

    static func transaction(_ t: Transaction) -> ExportDocument {
        var rows: [[String]] = [
            ["Date", t.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())],
            ["Account", t.account?.name ?? ""],
            ["Amount", money(t.amount)],
        ]
        let category = t.account?.supportsHoldings == true ? InvestmentType.of(t).title
            : (t.fixedCategoryTitle ?? t.splitTitle ?? (t.category?.isLive == true ? (t.category?.name ?? "") : ""))
        if !category.isEmpty { rows.append(["Category", category]) }
        if t.isSplit {
            for part in t.splits.sorted(by: { $0.order < $1.order }) {
                rows.append(["   \(part.category?.name ?? "Uncategorized")", money(part.amount)])
            }
        }
        if !t.paymentTitle.isEmpty { rows.append(["Payment method", t.paymentTitle]) }
        if !t.checkNumber.isEmpty { rows.append(["Check number", t.checkNumber]) }
        rows.append(["Status", t.state.title])
        if let bill = t.paidBill, bill.isLive { rows.append(["Paid bill", bill.name]) }
        if !t.memo.isEmpty { rows.append(["Memo", t.memo]) }

        var sections: [DocSection] = [
            .table(DocTable(columns: [.fixed("Detail", 120), .flexible("")], rows: rows)),
        ]
        var attachments: [DocAttachment] = []
        if let data = t.receiptData {
            attachments.append(DocAttachment(title: "Receipt", data: data))
        } else if t.noReceipt {
            sections.append(.text("Marked as having no receipt."))
        }
        return ExportDocument(
            title: t.payee.isEmpty ? "Transaction" : t.payee,
            subtitle: "\(t.date.formatted(day)) · \(t.account?.name ?? "")",
            summary: [("Amount", money(t.amount)), ("Status", t.state.title)],
            sections: sections, attachments: attachments)
    }

    // MARK: Accounts and net worth

    static func netWorth(accounts: [Account], asOf date: Date = .now) -> ExportDocument {
        let live = accounts.filter { $0.isLive && !($0.isClosed && $0.balance(asOf: date) == 0) }
        var assets: Decimal = 0
        var liabilities: Decimal = 0
        var sections: [DocSection] = []
        for group in AccountGroup.allCases {
            let members = live.filter { $0.type.group == group }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            guard !members.isEmpty else { continue }
            var total: Decimal = 0
            let rows = members.map { account -> [String] in
                let balance = account.balance(asOf: date)
                total += balance
                return [account.name + (account.isClosed ? " (closed)" : ""), account.typeTitle, money(balance)]
            }
            if group.isLiability { liabilities += total } else { assets += total }
            sections.append(.table(DocTable(title: group.title, columns: [.flexible("Account", 0.55), .flexible("Type", 0.3), .fixed("Balance", 100, right: true)],
                                            rows: rows, totalRow: ["Total", "", money(total)])))
        }
        return ExportDocument(
            title: "Accounts and Net Worth",
            subtitle: "As of \(date.formatted(day))",
            summary: [("Total assets", money(assets)), ("Total liabilities", money(liabilities)), ("Net worth", money(assets + liabilities))],
            sections: sections.isEmpty ? [.text("There are no accounts yet.")] : sections)
    }

    // MARK: Bills

    static func bills(_ all: [Bill], now: Date = .now) -> ExportDocument {
        let calendar = Calendar.current
        let live = all.filter(\.isLive)
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 60, to: start) ?? start
        let upcoming = Bills.occurrences(live, from: start, through: end, now: now)
            .sorted { ($0.date, $0.bill.name) < ($1.date, $1.bill.name) }

        func status(_ item: Bills.Occurrence) -> String {
            if item.isPaid { return "Paid" }
            if item.isOverdue { return "Overdue" }
            let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: item.date)).day ?? 0
            return days == 0 ? "Due today" : "In \(days) day\(days == 1 ? "" : "s")"
        }
        let upcomingRows = upcoming.map { [$0.date.formatted(day), $0.bill.name, money($0.bill.amount), status($0)] }
        let dueTotal = upcoming.filter { !$0.isPaid }.reduce(Decimal(0)) { $0 + $1.bill.amount }

        let billRows = live.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map { bill -> [String] in
            let next = Bills.nearestDue(bill, to: now).map { $0.formatted(day) } ?? "—"
            return [bill.name + (bill.isImportant ? " ★" : ""), money(bill.amount), BillFrequency(rawValue: bill.frequencyRaw)?.title ?? "", next]
        }
        return ExportDocument(
            title: "Bills",
            subtitle: "Next 60 days from \(start.formatted(day))",
            summary: [("Bills", live.count.formatted()), ("Still to pay", money(dueTotal)), ("Due dates listed", upcoming.count.formatted())],
            sections: [
                .table(DocTable(title: "Coming up", columns: [.fixed("Due", 80), .flexible("Bill"), .fixed("Amount", 80, right: true), .fixed("Status", 90)],
                                rows: upcomingRows, emptyNote: "No bills are due in the next 60 days.")),
                .table(DocTable(title: "All bills", columns: [.flexible("Bill"), .fixed("Amount", 80, right: true), .fixed("How often", 110), .fixed("Next due", 90)],
                                rows: billRows, emptyNote: "There are no bills yet.")),
            ])
    }

    // MARK: A report

    static func report(_ report: Reports.Report, periodLabel: String, periodName: String) -> ExportDocument {
        let totals = report.totals
        let percent: (Decimal) -> String = { $0.formatted(.percent.precision(.fractionLength(0))) }
        let buckets = report.buckets.map { [$0.label, money($0.income), money($0.spending), money($0.income - $0.spending)] }
        let totalSpending = report.spending.reduce(Decimal(0)) { $0 + $1.amount }
        let categories = report.spending.map { line -> [String] in
            [line.name, money(line.amount), totalSpending > 0 ? percent(line.amount / totalSpending) : ""]
        }
        var summary: [(label: String, value: String)] = [
            ("Income", money(totals.income)), ("Spending", money(totals.spending)), ("Net", money(totals.net)),
            ("Savings rate", totals.savingsRate.map(percent) ?? "—"),
        ]
        if report.previous.count > 0 {
            summary.append(("Previous income", money(report.previous.income)))
            summary.append(("Previous spending", money(report.previous.spending)))
        }
        return ExportDocument(
            title: "Report",
            subtitle: "\(periodName) · \(periodLabel)",
            summary: summary,
            sections: [
                .table(DocTable(title: "Income vs spending", columns: [.flexible("Period"), .fixed("Income", 90, right: true), .fixed("Spending", 90, right: true), .fixed("Net", 90, right: true)],
                                rows: buckets, totalRow: ["Total", money(totals.income), money(totals.spending), money(totals.net)])),
                .table(DocTable(title: "Spending by category", columns: [.flexible("Category"), .fixed("Spent", 90, right: true), .fixed("Share", 60, right: true)],
                                rows: categories, emptyNote: "No spending in this period.")),
            ])
    }

    // MARK: The budget

    static func budget(categories: [Category], month: Date, in context: ModelContext) -> ExportDocument {
        let calendar = Calendar.current
        let start = MonthFilter.start(of: month)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let found = ((try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.date >= start && $0.date < end }))) ?? []).live
        let table = Budget.spentTable(found, month: start)

        struct Line { let category: Category; let spent: Decimal }
        var lines: [Line] = []
        for category in categories where category.isLive && !category.isIncome && category.showOnBudgets {
            let spent = table[category]
            if category.monthlyLimit > 0 || spent > 0 { lines.append(Line(category: category, spent: spent)) }
        }
        lines.sort { $0.category.name.localizedCaseInsensitiveCompare($1.category.name) == .orderedAscending }
        var budgeted: Decimal = 0
        var spent: Decimal = 0
        var rows: [[String]] = []
        for line in lines {
            let limit = line.category.monthlyLimit
            let left = limit - line.spent
            budgeted += limit
            spent += line.spent
            let leftText = limit > 0 ? (left < 0 ? "Over by \(money(-left))" : money(left)) : "—"
            rows.append([line.category.name, limit > 0 ? money(limit) : "—", money(line.spent), leftText])
        }
        return ExportDocument(
            title: "Budget",
            subtitle: start.formatted(.dateTime.month(.wide).year()),
            summary: [("Budgeted", money(budgeted)), ("Spent", money(spent)), ("Left", money(budgeted - spent))],
            sections: [
                .table(DocTable(columns: [.flexible("Category"), .fixed("Budget", 90, right: true), .fixed("Spent", 90, right: true), .fixed("Left", 110, right: true)],
                                rows: rows, totalRow: ["Total", money(budgeted), money(spent), money(budgeted - spent)],
                                emptyNote: "No budgets are set up for this month.")),
            ])
    }
}

/// Asks where to save, draws the document as a PDF and shows it in Finder.
@MainActor
enum PDFSaver {
    static func save(_ document: ExportDocument, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let cleaned = suggestedName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = cleaned + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = DocumentPDF.render(document, paper: .preferred)
        do {
            guard !data.isEmpty else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save the PDF"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
