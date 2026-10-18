import Foundation

/// How a report is drawn, which decides the shape of its placeholder.
enum ReportShape {
    case bars, line, table, tiles, ring
}

/// One report on the Reports page. Until it is built it shows as a placeholder.
struct ReportItem: Identifiable {
    let title: String
    let summary: String
    let symbol: String
    let shape: ReportShape
    /// Reports that look ahead show a "next 6 months" projection beside the history.
    var projects = true
    /// Built reports show real data. Everything else is a placeholder.
    var isBuilt = false
    /// A wide report takes the full width of the page.
    var isWide = false
    /// Reports that are real line charts, with history and a projection.
    var trend: TrendKind? = nil

    var id: String { title }
}

/// The groups of reports across the top of the Reports page.
enum ReportSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case spending = "Spending"
    case income = "Income"
    case cashFlow = "Cash Flow"
    case netWorth = "Net Worth"
    case debt = "Debt & Loans"
    case goals = "Savings & Goals"
    case budgets = "Budgets"
    case bills = "Bills"
    case investments = "Investments"
    case health = "Books & Records"
    case projections = "Next 6 Months"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .spending: "cart"
        case .income: "arrow.down.circle"
        case .cashFlow: "arrow.left.arrow.right"
        case .netWorth: "scalemass"
        case .debt: "creditcard"
        case .goals: "target"
        case .budgets: "chart.pie"
        case .bills: "calendar"
        case .investments: "chart.line.uptrend.xyaxis"
        case .health: "checkmark.seal"
        case .projections: "forward"
        }
    }

    /// Sections whose reports cover a chosen period. The rest follow the last twelve months and look six months ahead.
    /// Cash Flow, Net Worth, Debt, Goals, Budgets, Bills and the projections don't use one.
    var usesPeriod: Bool {
        switch self {
        case .overview, .spending, .income: true
        default: false
        }
    }

    /// One line under the section name.
    var blurb: String {
        switch self {
        case .overview: "Income, spending and the year at a glance."
        case .spending: "Where the money goes, by category, payee, card and cash."
        case .income: "Where the money comes from and how steady it is."
        case .cashFlow: "Money in and out, month by month, and what's coming."
        case .netWorth: "What you own, what you owe, and where it's heading."
        case .debt: "Debt-to-income, payoff dates, interest and card use."
        case .goals: "Goal progress, pace and savings growth."
        case .budgets: "Budget against actual, and where it's heading this month."
        case .bills: "What's paid, what's due and the next six months of bills."
        case .investments: "Value, mix, gains and contributions."
        case .health: "Reconciliation, receipts and anything that needs attention."
        case .projections: "Every projection in one place, six months out."
        }
    }

    var reports: [ReportItem] {
        switch self {
        case .overview:
            [
                ReportItem(title: "Net Worth Over Time", summary: "", symbol: "scalemass", shape: .line, isWide: true, trend: .netWorth),
                ReportItem(title: "Total Debt Over Time", summary: "", symbol: "creditcard", shape: .line, trend: .debt),
                ReportItem(title: "Debt-to-Income Ratio", summary: "", symbol: "percent", shape: .line, trend: .debtToIncome),
                ReportItem(title: "Income vs Spending", summary: "Income, spending and what's left, for the period.", symbol: "chart.bar", shape: .bars, isBuilt: true),
                ReportItem(title: "Spending by Category", summary: "Every category's share of spending.", symbol: "chart.pie", shape: .table, isBuilt: true),
                ReportItem(title: "Year-End Summary", summary: "A one-page summary of the year: income, spending, savings, debt paid, net worth change.", symbol: "doc.text", shape: .tiles, isWide: true),
                ReportItem(title: "Report Card", summary: "Savings rate, debt-to-income, emergency fund and budget score in one glance.", symbol: "rosette", shape: .ring),
                ReportItem(title: "What Changed", summary: "The biggest moves compared with the last period.", symbol: "arrow.up.arrow.down", shape: .table),
            ]
        case .spending:
            [
                ReportItem(title: "Spending Trend by Category", summary: "Each category month by month, with the next six months projected.", symbol: "chart.xyaxis.line", shape: .line, isWide: true),
                ReportItem(title: "Spending by Payee", summary: "Who you pay the most, and how often.", symbol: "person.2", shape: .table),
                ReportItem(title: "Top Spending", summary: "The biggest transactions in the period.", symbol: "arrow.up.right", shape: .table, projects: false),
                ReportItem(title: "Spending by Payment Method", summary: "Card, bank transfer, cash and the rest.", symbol: "creditcard", shape: .ring),
                ReportItem(title: "Cash Spending", summary: "Cash on Hand: ATM withdrawals, cash spent and what's left.", symbol: "dollarsign.circle", shape: .bars),
                ReportItem(title: "Month Against Month", summary: "This month against last month and the same month last year.", symbol: "arrow.left.arrow.right", shape: .bars),
                ReportItem(title: "Tax-Related Spending", summary: "Categories you flag as tax-related, totalled for the year.", symbol: "doc.plaintext", shape: .table, projects: false),
            ]
        case .income:
            [
                ReportItem(title: "Income by Category", summary: "Each source of income and its share.", symbol: "chart.pie", shape: .ring),
                ReportItem(title: "Income by Payer", summary: "Who pays you, and how steady each source is.", symbol: "person.2", shape: .table),
                ReportItem(title: "Income Trend", summary: "Income month by month, with the next six months projected from your pay pattern.", symbol: "chart.xyaxis.line", shape: .line, isWide: true),
                ReportItem(title: "Savings Rate", summary: "The share of income you keep, month by month.", symbol: "percent", shape: .line),
            ]
        case .cashFlow:
            [
                ReportItem(title: "Monthly Cash Flow", summary: "Money in, money out and the net, month by month.", symbol: "arrow.left.arrow.right", shape: .bars, isWide: true),
                ReportItem(title: "Cash Flow Forecast", summary: "Expected balance each week for six months, using bills and your usual income and spending.", symbol: "forward", shape: .line, isWide: true),
                ReportItem(title: "Account Balances Over Time", summary: "Every checking and savings balance on one chart.", symbol: "chart.xyaxis.line", shape: .line),
                ReportItem(title: "Lowest Balance Ahead", summary: "The tightest week coming up and by how much.", symbol: "exclamationmark.triangle", shape: .tiles),
                ReportItem(title: "Transfers Between Accounts", summary: "Money moved between your own accounts.", symbol: "arrow.triangle.swap", shape: .table, projects: false),
            ]
        case .netWorth:
            [
                ReportItem(title: "Net Worth Over Time", summary: "", symbol: "scalemass", shape: .line, isWide: true, trend: .netWorth),
                ReportItem(title: "Assets vs Liabilities", summary: "What you own against what you owe.", symbol: "chart.bar", shape: .bars),
                ReportItem(title: "Net Worth by Account Type", summary: "Cash, investments, property, cards and loans.", symbol: "chart.pie", shape: .ring),
                ReportItem(title: "Biggest Movers", summary: "The accounts that changed your net worth most.", symbol: "arrow.up.arrow.down", shape: .table),
                ReportItem(title: "Net Worth Range", summary: "Low, expected and high paths for the next six months.", symbol: "forward", shape: .line, isWide: true),
            ]
        case .debt:
            [
                ReportItem(title: "Debt-to-Income Ratio", summary: "", symbol: "percent", shape: .line, trend: .debtToIncome),
                ReportItem(title: "Total Debt Over Time", summary: "", symbol: "creditcard", shape: .line, trend: .debt),
                ReportItem(title: "Loan Payoff Schedule", summary: "Each loan's balance, estimated payoff date and maturity date.", symbol: "calendar.badge.clock", shape: .table, isWide: true),
                ReportItem(title: "Ahead or Behind", summary: "Estimated payoff against maturity date for every loan, in months.", symbol: "flag.checkered", shape: .bars),
                ReportItem(title: "Interest Paid", summary: "Interest paid so far and still to come at the current payment.", symbol: "percent", shape: .bars),
                ReportItem(title: "Credit Card Use", summary: "Balance against limit for every card, and the projected balance.", symbol: "creditcard", shape: .ring),
                ReportItem(title: "Debt Payoff Plan", summary: "How much sooner you'd finish by adding to each payment.", symbol: "arrow.down.circle", shape: .table, isWide: true),
            ]
        case .goals:
            [
                ReportItem(title: "Goal Progress", summary: "Every goal against its target, with estimated finish dates.", symbol: "target", shape: .table, isWide: true),
                ReportItem(title: "On Track or Behind", summary: "Which goals will make their date and which need more each month.", symbol: "checkmark.circle", shape: .bars),
                ReportItem(title: "Needed Per Month", summary: "What every goal needs each month, against what you set aside now.", symbol: "calendar", shape: .bars),
                ReportItem(title: "Savings Growth", summary: "Linked savings accounts over time, with six months projected.", symbol: "chart.xyaxis.line", shape: .line),
                ReportItem(title: "Emergency Fund Coverage", summary: "How many months of spending your savings would cover.", symbol: "shield.lefthalf.filled", shape: .ring),
            ]
        case .budgets:
            [
                ReportItem(title: "Budget vs Actual", summary: "Every budget against what's been spent this month.", symbol: "chart.bar.doc.horizontal", shape: .bars, isWide: true),
                ReportItem(title: "Over and Under", summary: "Months you went over, by category.", symbol: "exclamationmark.triangle", shape: .table, projects: false),
                ReportItem(title: "Budget Trend", summary: "Spent against budget month by month, with the next six months projected.", symbol: "chart.xyaxis.line", shape: .line),
                ReportItem(title: "Projected Month End", summary: "Where each category lands by the end of the month at the current pace.", symbol: "forward", shape: .bars),
            ]
        case .bills:
            [
                ReportItem(title: "Bills by Month", summary: "What you pay in bills each month.", symbol: "calendar", shape: .bars),
                ReportItem(title: "Paid vs Due", summary: "Bills paid on time, late and still due.", symbol: "checkmark.circle", shape: .ring),
                ReportItem(title: "Next 6 Months of Bills", summary: "Every bill expected over the next six months, and the monthly total.", symbol: "forward", shape: .table, isWide: true),
                ReportItem(title: "Bills by Category", summary: "Which categories your bills fall in.", symbol: "chart.pie", shape: .ring),
            ]
        case .investments:
            [
                ReportItem(title: "Portfolio Value", summary: "Total value over time, with the next six months projected.", symbol: "chart.line.uptrend.xyaxis", shape: .line, isWide: true),
                ReportItem(title: "Allocation", summary: "How your investments are spread.", symbol: "chart.pie", shape: .ring),
                ReportItem(title: "Gains and Losses", summary: "Change in value for every holding.", symbol: "arrow.up.arrow.down", shape: .table),
                ReportItem(title: "Contributions", summary: "Money you've added, month by month.", symbol: "plus.circle", shape: .bars),
            ]
        case .health:
            [
                ReportItem(title: "Reconciliation Status", summary: "How much of every account is reconciled, pending or unreconciled.", symbol: "checkmark.circle", shape: .ring, projects: false),
                ReportItem(title: "Unreconciled by Account", summary: "What's still to match, account by account.", symbol: "list.bullet", shape: .table, projects: false),
                ReportItem(title: "Missing Receipts", summary: "Transactions with no receipt and not marked as having none.", symbol: "doc.questionmark", shape: .table, projects: false),
                ReportItem(title: "Duplicate Payees", summary: "Payees that look like the same one, to clean up.", symbol: "person.2.slash", shape: .table, projects: false),
            ]
        case .projections:
            [
                ReportItem(title: "Net Worth", summary: "", symbol: "scalemass", shape: .line, isWide: true, trend: .netWorth),
                ReportItem(title: "Cash Balance", summary: "Expected balance of your checking and savings.", symbol: "banknote", shape: .line),
                ReportItem(title: "Debt-to-Income", summary: "", symbol: "percent", shape: .line, trend: .debtToIncome),
                ReportItem(title: "Total Debt", summary: "", symbol: "creditcard", shape: .line, trend: .debt),
                ReportItem(title: "Spending", summary: "Expected spending by month, using your recent average and known bills.", symbol: "cart", shape: .bars),
                ReportItem(title: "Income", summary: "Expected income by month, using your pay pattern.", symbol: "arrow.down.circle", shape: .bars),
                ReportItem(title: "Savings Rate", summary: "The share of income you're on pace to keep.", symbol: "percent", shape: .line),
                ReportItem(title: "Loan Balances", summary: "Each loan's balance after every payment.", symbol: "calendar.badge.clock", shape: .line),
                ReportItem(title: "Credit Card Balances", summary: "Expected card balances and utilization.", symbol: "creditcard", shape: .line),
                ReportItem(title: "Goal Finish Dates", summary: "When each goal lands at the current pace.", symbol: "target", shape: .table, isWide: true),
            ]
        }
    }
}
