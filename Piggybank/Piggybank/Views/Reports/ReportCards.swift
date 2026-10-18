import SwiftUI

/// The reports that are built. Anything not listed here shows as a placeholder.
enum ReportCards {
    @MainActor
    static func view(section: ReportSection, title: String) -> AnyView? {
        switch "\(section.rawValue)/\(title)" {
        case "Net Worth/Assets vs Liabilities": AnyView(AssetsVsLiabilitiesReport())
        case "Net Worth/Net Worth by Account Type": AnyView(NetWorthByTypeReport())
        case "Net Worth/Biggest Movers": AnyView(BiggestMoversReport())
        case "Net Worth/Net Worth Range": AnyView(NetWorthRangeReport())

        case "Cash Flow/Monthly Cash Flow": AnyView(MonthlyCashFlowReport())
        case "Cash Flow/Account Balances Over Time": AnyView(AccountBalancesReport())
        case "Cash Flow/Cash Flow Forecast": AnyView(CashFlowForecastReport())
        case "Cash Flow/Lowest Balance Ahead": AnyView(LowestBalanceReport())
        case "Cash Flow/Transfers Between Accounts": AnyView(TransfersReport())

        case "Debt & Loans/Loan Payoff Schedule": AnyView(LoanPayoffScheduleReport())
        case "Debt & Loans/Ahead or Behind": AnyView(AheadOrBehindReport())
        case "Debt & Loans/Interest Paid": AnyView(InterestPaidReport())
        case "Debt & Loans/Credit Card Use": AnyView(CreditCardUseReport())
        case "Debt & Loans/Debt Payoff Plan": AnyView(DebtPayoffPlanReport())

        default: nil
        }
    }
}
