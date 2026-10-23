import Foundation
import SwiftData

/// Everything the Liabilities report shows, worked out in one pass over the accounts.
enum Liabilities {
    struct Line: Identifiable {
        let id: Account.ID
        let name: String
        let typeTitle: String
        let symbol: String
        /// What a loan is for, such as "2021 Honda Civic". Empty for cards.
        let purpose: String
        let isLoan: Bool
        let progress: LoanProgress
        /// What was owed when the period began. Nil when there is no period.
        var startOwed: Decimal?
        /// A card's limit, 0 when it has none set.
        var creditLimit: Decimal = 0

        /// A card with a limit is worked out like a loan, with the limit as the amount borrowed: whatever is not owed of it counts as paid off.
        var hasLimitBar: Bool { !isLoan && creditLimit > 0 }
        var limitFraction: Double { min(max(NSDecimalNumber(decimal: (creditLimit - owed) / creditLimit).doubleValue, 0), 1) }

        /// Positive when you paid it down, negative when you borrowed more.
        var paidDown: Decimal? { startOwed.map { $0 - owed } }

        var owed: Decimal { progress.owed }
        var isPaidOff: Bool { owed <= 0 }
        /// Only loans with an original amount have a payoff percentage.
        var hasProgress: Bool { isLoan && progress.hasOriginal }
    }

    struct Point: Identifiable {
        let date: Date
        let owed: Double
        var id: Date { date }
    }

    struct Report {
        /// Biggest balance first, paid-off accounts last.
        var lines: [Line] = []
        var totalOwed: Decimal = 0
        var loanOwed: Decimal = 0
        var cardOwed: Decimal = 0
        /// Loans that have an original amount: what was borrowed, and how much of it is paid.
        var originalBorrowed: Decimal = 0
        var paidSoFar: Decimal = 0
        var monthlyPayments: Decimal = 0
        var totalAssets: Decimal = 0
        /// The latest estimated payoff across everything still owed. Nil unless every one has a monthly payment.
        var debtFreeDate: Date?
        /// Set when the report covers a period: what was owed at the start, how much was paid down, how much more was borrowed.
        var startOwed: Decimal?
        var paidDown: Decimal = 0
        var borrowed: Decimal = 0
        /// Month-end totals owed through the period.
        var trend: [Point] = []

        var outstanding: Int { lines.filter { !$0.isPaidOff }.count }
        var paidOff: Int { lines.filter(\.isPaidOff).count }
        var netWorth: Decimal { totalAssets - totalOwed }

        /// 0...1 over the loans that have an original amount and the cards that have a limit. Nil when none do.
        var payoffFraction: Double? {
            originalBorrowed > 0 ? min(max((paidSoFar / originalBorrowed).doubleValue, 0), 1) : nil
        }

        /// What you owe for every unit you own. Nil with no assets.
        var debtToAssets: Double? {
            totalAssets > 0 ? (totalOwed / totalAssets).doubleValue : nil
        }
    }

    /// With a `range`, balances are as of the end of that period and the report also tracks how debt changed during it.
    static func build(_ accounts: [Account], range: ReportRange? = nil, now: Date = .now, calendar: Calendar = .current) -> Report {
        var report = Report()
        var lines: [Line] = []
        var latest: Date?
        var everyOneHasEstimate = true

        let asOf = range.map { Trend.endDate($0, now: now) } ?? .distantFuture
        let reference = range.map { Trend.endDate($0, now: now) } ?? now
        let before = range.map { Trend.startDate($0) }
        if before != nil { report.startOwed = 0 }

        for account in accounts.live {
            if account.isDebt {
                let isLoan = account.isLoan
                let owed = max(-account.balance(asOf: asOf), 0)
                let progress = LoanProgress(
                    original: isLoan ? account.originalLoanAmount : 0,
                    owed: owed,
                    monthlyPayment: isLoan ? account.monthlyPayment : 0,
                    targetDate: isLoan ? account.payoffDate : nil,
                    annualRate: isLoan ? account.interestRate : 0
                )
                var line = Line(
                    id: account.id,
                    name: account.name,
                    typeTitle: account.typeTitle,
                    symbol: account.type.symbol,
                    purpose: isLoan ? account.loanPurpose : "",
                    isLoan: isLoan,
                    progress: progress
                )
                line.creditLimit = isLoan ? 0 : account.creditLimit
                if let before {
                    let startOwed = max(-account.balance(asOf: before), 0)
                    line.startOwed = startOwed
                    report.startOwed = (report.startOwed ?? 0) + startOwed
                    if startOwed > owed { report.paidDown += startOwed - owed } else { report.borrowed += owed - startOwed }
                }
                lines.append(line)

                report.totalOwed += owed
                if isLoan { report.loanOwed += owed } else { report.cardOwed += owed }
                if isLoan && progress.hasOriginal {
                    report.originalBorrowed += progress.original
                    report.paidSoFar += progress.paidOff
                } else if line.hasLimitBar {
                    // A card counts like a loan: its limit is what could be owed, and what is not owed of it is paid off.
                    report.originalBorrowed += line.creditLimit
                    report.paidSoFar += min(max(line.creditLimit - owed, 0), line.creditLimit)
                }
                if owed > 0 {
                    report.monthlyPayments += progress.monthlyPayment
                    if let date = progress.payoffDate(from: reference, calendar: calendar) {
                        latest = max(latest ?? date, date)
                    } else {
                        everyOneHasEstimate = false
                    }
                }
            } else {
                report.totalAssets += account.balance(asOf: asOf)
            }
        }

        report.lines = lines.sorted {
            if $0.isPaidOff != $1.isPaidOff { return !$0.isPaidOff }
            if $0.owed != $1.owed { return $0.owed > $1.owed }
            return $0.name < $1.name
        }
        report.debtFreeDate = everyOneHasEstimate && report.outstanding > 0 ? latest : nil

        if let range {
            let debts = accounts.live.filter(\.isDebt)
            report.trend = Trend.monthEnds(range, now: now, calendar: calendar).map { date in
                Point(date: date, owed: debts.reduce(Decimal(0)) { $0 + max(-$1.balance(asOf: date), 0) }.doubleValue)
            }
        }
        return report
    }
}
