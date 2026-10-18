import Foundation
import SwiftData

/// The Summary page and each section of the Reports page as a printable PDF. The pages are charts and cards, which don't
/// print well in black and white, so the PDF has the same figures as tables: the numbers behind each chart.
@MainActor
enum PageDocuments {
    private static let money: (Decimal) -> String = { $0.formatted(.appCurrency) }
    private static let moneyD: (Double) -> String = { Decimal($0).formatted(.appCurrency) }
    private static let percent: (Double) -> String = { $0.formatted(.percent.precision(.fractionLength(0))) }
    private static let monthName = Date.FormatStyle.dateTime.month(.abbreviated).year()
    private static let dayName = Date.FormatStyle.dateTime.month(.abbreviated).day().year()

    /// Everything the pages read, gathered once by the screen that asks for the PDF.
    struct Source {
        var accounts: [Account]
        /// The last thirteen months of transactions (narrowed to a tag on the Reports page, when one is chosen).
        var year: [Transaction]
        var categories: [Category]
        var bills: [Bill]
        var goals: [Goal]
        var snapshot: LedgerSnapshot?
        var tagName: String?
        var now = Date.now
    }

    /// Reads what the pages need from the database. With a tag, only transactions carrying it are counted.
    static func source(in context: ModelContext, tag: Tag? = nil, now: Date = .now) -> Source {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let yearStart = calendar.date(byAdding: .month, value: -13, to: thisMonth) ?? thisMonth
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.date >= yearStart })
        var year = ((try? context.fetch(descriptor)) ?? []).live
        if let tag, tag.isLive { year = year.filter { $0.tags.contains { $0 === tag } } }
        return Source(accounts: ((try? context.fetch(FetchDescriptor<Account>())) ?? []).live,
                      year: year,
                      categories: ((try? context.fetch(FetchDescriptor<Category>())) ?? []).live,
                      bills: ((try? context.fetch(FetchDescriptor<Bill>())) ?? []).live,
                      goals: ((try? context.fetch(FetchDescriptor<Goal>())) ?? []).live,
                      snapshot: LedgerIndex.shared.latest,
                      tagName: tag.flatMap { $0.isLive ? $0.name : nil }, now: now)
    }

    private static func note(_ source: Source) -> DocSection? {
        source.snapshot == nil ? .text("The figures behind the charts are still being worked out. Print again in a moment for the full picture.") : nil
    }

    // MARK: Tables shared by several pages

    private static func trendTable(_ title: String, _ points: [TrendPoint], valueTitle: String) -> DocSection {
        let rows = points.filter { !$0.projected }.map { [$0.date.formatted(monthName), moneyD($0.value), ""] }
            + points.filter(\.projected).dropFirst().map { [$0.date.formatted(monthName), moneyD($0.value), "Projected"] }
        return .table(DocTable(title: title, columns: [.flexible("Month"), .fixed(valueTitle, 110, right: true), .fixed("", 80)], rows: rows,
                               emptyNote: "Not enough history yet."))
    }

    private static func flowTable(_ source: Source) -> DocSection {
        guard let snapshot = source.snapshot else { return .text("Waiting for the figures.") }
        let months = ReportMath.monthlyFlow(snapshot: snapshot)
        let rows = months.map { [$0.date.formatted(monthName), moneyD($0.income), moneyD($0.spending), moneyD($0.net), $0.projected ? "Projected" : ""] }
        return .table(DocTable(title: "Money in and out, by month",
                               columns: [.flexible("Month"), .fixed("In", 90, right: true), .fixed("Out", 90, right: true), .fixed("Net", 90, right: true), .fixed("", 70)],
                               rows: rows, emptyNote: "No income or spending yet."))
    }

    private static func categoryTable(_ title: String, _ transactions: [Transaction], income: Bool, limit: Int = 15) -> DocSection {
        let lines = ReportInputs.categories(transactions, income: income)
        let total = lines.reduce(0) { $0 + $1.amount }
        let rows = lines.prefix(limit).map { [$0.name, moneyD($0.amount), total > 0 ? percent($0.amount / total) : ""] }
        return .table(DocTable(title: title, columns: [.flexible("Category"), .fixed("Amount", 100, right: true), .fixed("Share", 60, right: true)],
                               rows: rows, totalRow: rows.isEmpty ? nil : ["Total", moneyD(total), ""], emptyNote: "Nothing in this period."))
    }

    private static func real(_ source: Source, since start: Date) -> [Transaction] {
        source.year.filter { !$0.isTransfer && $0.date >= start }
    }

    private static func start(monthsBack: Int, _ now: Date) -> Date {
        let calendar = Calendar.current
        return calendar.startOfDay(for: calendar.date(byAdding: .month, value: -monthsBack, to: now) ?? now)
    }

    private static func goalsTable(_ goals: [Goal], now: Date) -> DocSection {
        let rows = goals.live.filter { !$0.isArchived }.map { goal -> [String] in
            let progress = goal.progress(now: now)
            let status: String
            switch progress.status {
            case .achieved: status = "Reached"
            case .onTrack: status = "On track"
            case .behind: status = "Behind"
            case .pastDue: status = "Past the date"
            case .noDate: status = ""
            }
            return [goal.name + (goal.isPayoff ? " (payoff)" : ""), money(goal.saved), money(goal.targetAmount),
                    percent(progress.fraction), goal.targetDate?.formatted(dayName) ?? "", status]
        }
        return .table(DocTable(title: "Goals", columns: [.flexible("Goal"), .fixed("So far", 80, right: true), .fixed("Target", 80, right: true),
                                                         .fixed("Done", 44, right: true), .fixed("Date", 80), .fixed("Status", 70)],
                               rows: rows, emptyNote: "There are no goals yet."))
    }

    private static func debtTable(_ accounts: [Account], now: Date) -> DocSection {
        let debts = accounts.live.filter { ($0.isLoan || $0.isCreditCard) && !$0.isClosed }
        let rows = debts.map { account -> [String] in
            let owed = money(max(-account.balance, 0))
            let payoff = account.isLoan ? (account.loanProgress.payoffDate(from: now).map { $0.formatted(monthName) } ?? "") : ""
            let rate = account.interestRate > 0 ? "\(account.interestRate.formatted(.number.precision(.fractionLength(0...2))))%" : ""
            return [account.name, account.typeTitle, owed, rate, account.monthlyPayment > 0 ? money(account.monthlyPayment) : "", payoff]
        }
        let total = debts.reduce(Decimal(0)) { $0 + max(-$1.balance, 0) }
        return .table(DocTable(title: "What you owe", columns: [.flexible("Account"), .fixed("Type", 90), .fixed("Owed", 90, right: true), .fixed("Rate", 44, right: true),
                                                              .fixed("Payment", 70, right: true), .fixed("Paid off", 62)],
                               rows: rows, totalRow: rows.isEmpty ? nil : ["Total", "", money(total), "", "", ""], emptyNote: "No loans or cards."))
    }

    private static func budgetTable(_ source: Source) -> DocSection {
        let table = Budget.spentTable(source.year, month: source.now)
        let budgeted = source.categories.live.filter { !$0.isIncome && $0.showOnBudgets && $0.monthlyLimit > 0 }
            .sorted { $0.monthlyLimit > $1.monthlyLimit }
        let rows = budgeted.map { category -> [String] in
            let spent = table[category]
            let left = category.monthlyLimit - spent
            return [category.name, money(category.monthlyLimit), money(spent), money(left)]
        }
        let totalLimit = budgeted.reduce(Decimal(0)) { $0 + $1.monthlyLimit }
        let totalSpent = budgeted.reduce(Decimal(0)) { $0 + table[$1] }
        return .table(DocTable(title: "This month's budgets", columns: [.flexible("Category"), .fixed("Budget", 90, right: true), .fixed("Spent", 90, right: true), .fixed("Left", 90, right: true)],
                               rows: rows, totalRow: rows.isEmpty ? nil : ["Total", money(totalLimit), money(totalSpent), money(totalLimit - totalSpent)],
                               emptyNote: "No budgets are set."))
    }

    private static func investmentTables(_ source: Source) -> [DocSection] {
        let data = InvestmentsData.make(accounts: source.accounts, transactions: source.year, snapshot: source.snapshot)
        let accounts = DocTable(title: "Investment accounts", columns: [.flexible("Account"), .fixed("Type", 110), .fixed("Value", 90, right: true),
                                                                       .fixed("Growth, 12 months", 100, right: true), .fixed("Return", 56, right: true)],
                                rows: data.accounts.map { [$0.name, $0.typeTitle, moneyD($0.value), moneyD($0.growth), $0.growthRate.map(percent) ?? ""] },
                                totalRow: data.accounts.isEmpty ? nil : ["Total", "", moneyD(data.totalValue), moneyD(data.growth12), ""],
                                emptyNote: "No investment accounts.")
        var sections: [DocSection] = [.table(accounts)]
        if !data.holdings.isEmpty {
            sections.append(.table(DocTable(title: "Holdings", columns: [.flexible("Holding"), .fixed("Account", 100), .fixed("Value", 80, right: true),
                                                                         .fixed("Cost", 80, right: true), .fixed("Gain", 80, right: true)],
                                            rows: data.holdings.map { [$0.name, $0.accountName, moneyD($0.value), moneyD($0.cost), moneyD($0.gain)] })))
        }
        return sections
    }

    private static func taxTable(_ source: Source) -> DocSection {
        var table: [String: (count: Int, amount: Decimal)] = [:]
        let since = start(monthsBack: 12, source.now)
        for transaction in real(source, since: since) where transaction.amount < 0 {
            for part in transaction.categoryParts where part.category?.isTaxRelated == true {
                let name = part.category?.name ?? "Uncategorized"
                var entry = table[name] ?? (0, 0)
                entry.count += 1
                entry.amount -= part.amount
                table[name] = entry
            }
        }
        let rows = table.sorted { $0.value.amount > $1.value.amount }.map { [$0.key, "\($0.value.count)", money($0.value.amount)] }
        let total = table.values.reduce(Decimal(0)) { $0 + $1.amount }
        return .table(DocTable(title: "Tax-related spending, last 12 months", columns: [.flexible("Category"), .fixed("Entries", 60, right: true), .fixed("Amount", 100, right: true)],
                               rows: rows, totalRow: rows.isEmpty ? nil : ["Total", "", money(total)], emptyNote: "No spending in categories marked tax-related."))
    }

    private static func windowTable(_ source: Source) -> DocSection {
        let windows = ReportInputs.windows(now: source.now)
        let rows = windows.map { window -> [String] in
            let list = real(source, since: window.start)
            let income = list.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
            let spending = list.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount }
            return [window.title, money(income), money(spending), money(income - spending)]
        }
        return .table(DocTable(title: "Income and spending", columns: [.flexible("Period"), .fixed("Income", 100, right: true), .fixed("Spending", 100, right: true), .fixed("Kept", 100, right: true)],
                               rows: rows))
    }

    // MARK: Summary

    static func summary(_ source: Source) -> ExportDocument {
        let accounts = source.accounts.live
        var assets: Decimal = 0, liabilities: Decimal = 0
        for account in accounts where !(account.isClosed && account.balance == 0) {
            if account.isDebt { liabilities += account.balance } else { assets += account.balance }
        }
        let thisMonth = source.snapshot.flatMap { snapshot -> (Decimal, Decimal)? in
            guard let income = snapshot.income.last, let spending = snapshot.spending.last else { return nil }
            return (income, spending)
        }
        var summary: [(label: String, value: String)] = [("Net worth", money(assets + liabilities)), ("Assets", money(assets)), ("Liabilities", money(liabilities))]
        if let thisMonth {
            summary.append(("Income this month", money(thisMonth.0)))
            summary.append(("Spending this month", money(thisMonth.1)))
        }

        var sections: [DocSection] = []
        if let note = note(source) { sections.append(note) }
        sections.append(contentsOf: DocumentBuilders.netWorth(accounts: accounts, asOf: source.now).sections)
        if let snapshot = source.snapshot {
            sections.append(trendTable("Net worth over the last 12 months", ReportTrends.netWorth(accounts: accounts, snapshot: snapshot, now: source.now).filter { !$0.projected },
                                       valueTitle: "Net worth"))
        }
        sections.append(flowTable(source))
        let priority = Bills.priority(source.bills.live, now: source.now)
        sections.append(.table(DocTable(title: "Priority bills", columns: [.fixed("Due", 80), .flexible("Bill"), .fixed("Amount", 90, right: true), .fixed("Status", 100)],
                                        rows: priority.map { [$0.date.formatted(dayName), $0.bill.name, money($0.bill.amount), $0.dueText] },
                                        emptyNote: "No important bills are overdue or due in the next 20 days.")))
        sections.append(debtTable(accounts, now: source.now))
        sections.append(goalsTable(source.goals, now: source.now))
        sections.append(categoryTable("Top spending categories, last 3 months", real(source, since: start(monthsBack: 3, source.now)), income: false, limit: 10))
        return ExportDocument(title: "Summary", subtitle: "As of \(source.now.formatted(dayName))", summary: summary, sections: sections)
    }

    // MARK: Reports

    static func report(_ section: ReportSection, _ source: Source) -> ExportDocument {
        let accounts = source.accounts.live
        let year = real(source, since: start(monthsBack: 12, source.now))
        let three = real(source, since: start(monthsBack: 3, source.now))
        var sections: [DocSection] = []
        if let note = note(source) { sections.append(note) }
        var summary: [(label: String, value: String)] = []

        switch section {
        case .overview:
            if let snapshot = source.snapshot {
                sections.append(trendTable("Net worth, with the next six months projected", ReportTrends.netWorth(accounts: accounts, snapshot: snapshot, now: source.now), valueTitle: "Net worth"))
                sections.append(trendTable("Total debt, with the next six months projected", ReportTrends.debt(accounts: accounts, snapshot: snapshot, now: source.now), valueTitle: "Owed"))
            }
            sections.append(windowTable(source))
        case .spending:
            sections.append(categoryTable("Spending by category, last 3 months", three, income: false))
            sections.append(categoryTable("Spending by category, last 12 months", year, income: false))
            let biggest = three.filter { $0.amount < 0 }.sorted { $0.amount < $1.amount }.prefix(10)
            sections.append(.table(DocTable(title: "Biggest single payments, last 3 months", columns: [.fixed("Date", 80), .flexible("Payee"), .fixed("Category", 110), .fixed("Amount", 90, right: true)],
                                            rows: biggest.map { [$0.date.formatted(dayName), $0.payee, $0.categoryTitle, money(-$0.amount)] }, emptyNote: "No spending in this period.")))
        case .income:
            sections.append(categoryTable("Income by category, last 3 months", three.filter { $0.amount > 0 }, income: true))
            sections.append(categoryTable("Income by category, last 12 months", year.filter { $0.amount > 0 }, income: true))
        case .cashFlow:
            sections.append(flowTable(source))
        case .netWorth:
            if let snapshot = source.snapshot {
                sections.append(trendTable("Net worth, with the next six months projected", ReportTrends.netWorth(accounts: accounts, snapshot: snapshot, now: source.now), valueTitle: "Net worth"))
            }
            sections.append(contentsOf: DocumentBuilders.netWorth(accounts: accounts, asOf: source.now).sections)
        case .debt:
            sections.append(debtTable(accounts, now: source.now))
            if let snapshot = source.snapshot {
                sections.append(trendTable("Total debt, with the next six months projected", ReportTrends.debt(accounts: accounts, snapshot: snapshot, now: source.now), valueTitle: "Owed"))
            }
        case .goals:
            sections.append(goalsTable(source.goals, now: source.now))
        case .budgets:
            sections.append(budgetTable(source))
        case .bills:
            sections.append(contentsOf: DocumentBuilders.bills(source.bills, now: source.now).sections)
        case .investments:
            sections.append(contentsOf: investmentTables(source))
        case .health:
            sections.append(taxTable(source))
            sections.append(windowTable(source))
        }
        if let tag = source.tagName {
            summary.append(("Only transactions tagged", tag))
        }
        return ExportDocument(title: "Report: \(section.rawValue)", subtitle: "As of \(source.now.formatted(dayName))", summary: summary, sections: sections)
    }
}
