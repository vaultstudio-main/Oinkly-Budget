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

        case "Savings & Goals/Goal Progress": AnyView(GoalProgressReport())
        case "Savings & Goals/On Track or Behind": AnyView(GoalStatusReport())
        case "Savings & Goals/Needed Per Month": AnyView(GoalNeededReport())
        case "Savings & Goals/Savings Growth": AnyView(SavingsGrowthReport())
        case "Savings & Goals/Emergency Fund Coverage": AnyView(EmergencyFundReport())

        case "Budgets/Budget vs Actual": AnyView(BudgetVsActualReport())
        case "Budgets/Over and Under": AnyView(BudgetOverUnderReport())
        case "Budgets/Budget Trend": AnyView(BudgetTrendReport())
        case "Budgets/Projected Month End": AnyView(ProjectedMonthEndReport())

        case "Spending/Spending Trend by Category": AnyView(SpendingTrendReport())
        case "Spending/Spending by Payee": AnyView(SpendingByPayeeReport())
        case "Spending/Top Spending": AnyView(TopSpendingReport())
        case "Spending/Spending by Payment Method": AnyView(PaymentMethodReport())
        case "Spending/Cash Spending": AnyView(CashSpendingReport())
        case "Spending/Month Against Month": AnyView(MonthAgainstMonthReport())
        case "Spending/Tax-Related Spending": AnyView(TaxRelatedReport())

        case "Income/Income by Category": AnyView(IncomeByCategoryReport())
        case "Income/Income by Payer": AnyView(IncomeByPayerReport())
        case "Income/Income Trend": AnyView(IncomeTrendReport())
        case "Income/Savings Rate": AnyView(SavingsRateReport())

        case "Bills/Bills by Month": AnyView(BillsByMonthReport())
        case "Bills/Paid vs Due": AnyView(BillsPaidVsDueReport())
        case "Bills/Next 6 Months of Bills": AnyView(NextSixMonthsBillsReport())
        case "Bills/Bills by Category": AnyView(BillsByCategoryReport())

        case "Debt & Loans/Loan Balances Ahead": AnyView(LoanBalancesProjectionReport())
        case "Debt & Loans/Card Balances Ahead": AnyView(CardBalancesProjectionReport())
        case "Savings & Goals/Goal Finish Dates": AnyView(GoalFinishDatesReport())

        case "Investments/Portfolio Value": AnyView(PortfolioValueReport())
        case "Investments/Allocation": AnyView(InvestmentAllocationReport())
        case "Investments/Gains and Losses": AnyView(InvestmentGainsReport())
        case "Investments/Contributions": AnyView(InvestmentContributionsReport())
        case "Investments/Projection of Growth": AnyView(InvestmentProjectionReport())
        case "Investments/Where It Is": AnyView(InvestmentBucketsReport())
        case "Investments/Growth by Account": AnyView(InvestmentGrowthReport())

        case "Overview/Income & Spending": AnyView(IncomeSpendingWindowsReport())
        case "Overview/Spending by Category": AnyView(SpendingByCategoryWindowsReport())
        case "Overview/Year-End Summary": AnyView(YearEndSummaryReport())
        case "Overview/Report Card": AnyView(ReportCardReport())
        case "Overview/What Changed": AnyView(WhatChangedReport())

        case "Books & Records/Reconciliation Status": AnyView(ReconciliationStatusReport())
        case "Books & Records/Unreconciled by Account": AnyView(UnreconciledByAccountReport())
        case "Books & Records/Missing Receipts": AnyView(MissingReceiptsReport())
        case "Books & Records/Duplicate Payees": AnyView(DuplicatePayeesReport())

        default: nil
        }
    }
}
