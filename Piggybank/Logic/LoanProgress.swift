import Foundation

/// How far along a loan is. Loans are stored as a negative balance (what you owe), and each payment
/// moves that balance toward zero, so "paid off" is the original amount minus what is still owed.
struct LoanProgress {
    let original: Decimal
    let owed: Decimal
    let monthlyPayment: Decimal
    /// The payoff date the user chose, if any.
    var targetDate: Date? = nil
    /// Yearly interest rate as a percent. Zero means interest is ignored.
    var annualRate: Double = 0

    var hasOriginal: Bool { original > 0 }

    /// Never negative, and never more than the original amount.
    var paidOff: Decimal { hasOriginal ? min(max(original - owed, 0), original) : 0 }

    /// 0...1
    var fraction: Double { hasOriginal ? min(max((paidOff / original).doubleValue, 0), 1) : 0 }

    var isPaidOff: Bool { owed <= 0 && hasOriginal }

    /// Payments left at the current monthly payment. With an interest rate this uses the standard loan formula;
    /// without one it just divides. Either way it is an estimate. Nil if the payment never pays the loan off.
    var paymentsLeft: Int? {
        guard monthlyPayment > 0, owed > 0 else { return nil }
        let balance = owed.doubleValue
        let payment = monthlyPayment.doubleValue
        let monthlyRate = annualRate / 100 / 12
        let count: Double
        if monthlyRate > 0 {
            guard payment > balance * monthlyRate else { return nil }
            count = (-log(1 - balance * monthlyRate / payment) / log(1 + monthlyRate)).rounded(.up)
        } else {
            count = (balance / payment).rounded(.up)
        }
        return count.isFinite && count < 10_000 ? Int(count) : nil
    }

    /// Whole months from now until the chosen payoff date. Zero once the date has arrived or passed.
    func monthsToTarget(from now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let targetDate else { return nil }
        let months = calendar.dateComponents([.month], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: targetDate)).month ?? 0
        return max(months, 0)
    }

    /// The monthly payment needed to be done by the chosen date. Nil when there is no date or nothing is owed.
    func paymentNeeded(from now: Date = .now, calendar: Calendar = .current) -> Decimal? {
        guard owed > 0, let months = monthsToTarget(from: now, calendar: calendar) else { return nil }
        return owed / Decimal(max(months, 1))
    }

    enum TargetStatus { case onTrack, behind, pastDue }

    /// Compares your monthly payment with what the chosen date needs. Interest is ignored.
    func targetStatus(from now: Date = .now, calendar: Calendar = .current) -> TargetStatus? {
        guard owed > 0, let needed = paymentNeeded(from: now, calendar: calendar), let months = monthsToTarget(from: now, calendar: calendar) else { return nil }
        if months == 0 { return .pastDue }
        return monthlyPayment >= needed ? .onTrack : .behind
    }

    func payoffDate(from now: Date = .now, calendar: Calendar = .current) -> Date? {
        paymentsLeft.flatMap { calendar.date(byAdding: .month, value: $0, to: now) }
    }
}

extension Account {
    var loanProgress: LoanProgress {
        LoanProgress(original: originalLoanAmount, owed: max(-balance, 0), monthlyPayment: monthlyPayment, targetDate: payoffDate, annualRate: interestRate)
    }
}
