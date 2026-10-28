import Foundation
import SwiftData

/// What happens to a loan when its balance reaches zero. An auto loan or a mortgage means you now own the car or the house, so the app offers
/// to add it as an asset (and asks first). A lease that has run its course asks whether you bought the car out or handed it back. Any other
/// loan, such as a student loan, simply goes to the archive. Nothing is deleted: an archived account keeps all of its transactions and can be
/// brought back.
@MainActor
enum PaidOffLoans {
    enum Outcome: Equatable {
        /// The loan is archived and a new asset of this kind is offered.
        case becomesAsset(AccountType)
        /// The loan is archived.
        case archives
        /// A lease that has run its course: you can buy the car out (and finance it, or pay for it), or hand it back. Asked about first.
        case leaseEnded
        /// Nothing happens: a line of credit can be borrowed from again, so zero owed isn't the end of it.
        case stays
    }

    /// What a paid-off loan of this kind turns into.
    static func outcome(for type: AccountType, isLease: Bool) -> Outcome {
        switch type {
        case .mortgage: return .becomesAsset(.realEstate)
        case .autoLoan: return isLease ? .leaseEnded : .becomesAsset(.vehicle)
        case .lineOfCredit, .homeEquity: return .stays
        default: return .archives
        }
    }

    /// A loan that started out owing money and now owes nothing. A loan that never owed anything is new, not paid off.
    static func isPaidOff(_ account: Account) -> Bool {
        guard account.isLive, account.isLoan, !account.isClosed, account.openingBalance < 0 else { return false }
        return account.balance >= 0
    }

    // MARK: Remembering what you said no to

    private static let declinedKey = "paidOffLoansDeclined"
    /// Loans skipped until the app is opened again.
    private static var skippedThisSession = Set<String>()

    private static func key(_ account: Account) -> String { MonthOutlook.accountKey(account) }

    private static func isDeclined(_ account: Account) -> Bool {
        let k = key(account)
        return skippedThisSession.contains(k) || (UserDefaults.standard.stringArray(forKey: declinedKey) ?? []).contains(k)
    }

    /// Don't ask about this loan again, now or later. Also used when a loan is brought back from the archive, so it isn't archived again.
    static func decline(_ account: Account) {
        var all = UserDefaults.standard.stringArray(forKey: declinedKey) ?? []
        if !all.contains(key(account)) { all.append(key(account)) }
        UserDefaults.standard.set(all, forKey: declinedKey)
    }

    /// Ask about this loan again the next time the app is opened, not before.
    static func skipForNow(_ account: Account) { skippedThisSession.insert(key(account)) }

    /// Forgets every loan said no to, with the rest of the data it belongs to.
    static func forgetDeclined() { UserDefaults.standard.removeObject(forKey: declinedKey) }

    // MARK: Looking

    /// Archives every paid-off loan that just goes to the archive, and returns the paid-off auto loans and mortgages that should be asked about.
    @discardableResult
    static func scan(in context: ModelContext) -> [Account] {
        let accounts = ((try? context.fetch(FetchDescriptor<Account>())) ?? []).live
        var toAsk: [Account] = []
        var changed = false
        for account in accounts where isPaidOff(account) && !isDeclined(account) {
            switch outcome(for: account.type, isLease: account.isLease) {
            case .archives:
                archive(account, in: context)
                changed = true
            case .becomesAsset, .leaseEnded:
                toAsk.append(account)
            case .stays:
                break
            }
        }
        if changed { context.saveNow() }
        return toAsk
    }

    // MARK: Doing

    /// Puts the loan in the archive and takes its bill off the Bills page, since there is nothing left to pay.
    static func archive(_ account: Account, in context: ModelContext) {
        LoanBill.sync(account, dueDate: nil, in: context)
        account.isClosed = true
    }

    /// Brings an archived account back to the side panel. A loan that is still paid off is not archived again.
    static func restore(_ account: Account, in context: ModelContext) {
        account.isClosed = false
        decline(account)
        context.saveNow()
    }

    /// The name to offer for the asset: what the loan was for, such as "2021 Honda Civic", or else the loan's own name.
    static func suggestedAssetName(for loan: Account) -> String {
        let purpose = loan.loanPurpose.trimmingCharacters(in: .whitespaces)
        return purpose.isEmpty ? loan.name : purpose
    }

    /// An asset you already track that looks like the car or house this loan paid for: the same VIN, or a name that holds the other's. It is
    /// offered so the same thing isn't added twice.
    static func existingAsset(for loan: Account, in context: ModelContext) -> Account? {
        guard case .becomesAsset(let type) = outcome(for: loan.type, isLease: loan.isLease) else { return nil }
        let assets = ((try? context.fetch(FetchDescriptor<Account>())) ?? []).live.filter { $0.type == type && !$0.isClosed }
        let vin = loan.vin.trimmingCharacters(in: .whitespaces).lowercased()
        let names = [loan.loanPurpose, loan.name].map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }.filter { $0.count >= 5 }
        return assets.first { asset in
            if !vin.isEmpty, asset.vin.trimmingCharacters(in: .whitespaces).lowercased() == vin { return true }
            let assetName = asset.name.lowercased().filter { $0.isLetter || $0.isNumber }
            return assetName.count >= 5 && names.contains { $0.contains(assetName) || assetName.contains($0) }
        }
    }

    /// Turns a lease you have bought out into a regular auto loan: it now owes `owed` (what the buyout left to pay), with its own monthly payment
    /// and rate. The lease payments stay in its history, and its bill keeps its due date with the new amount. A new loan starts today.
    static func convertLeaseToLoan(_ lease: Account, owed: Decimal, monthlyPayment: Decimal, rate: Double, in context: ModelContext) {
        // The starting balance is set so that the account owes exactly `owed` now, whatever has been paid on the lease so far.
        let paidSoFar = lease.balance - lease.openingBalance
        lease.openingBalance = -abs(owed) - paidSoFar
        lease.originalLoanAmount = abs(owed)
        lease.monthlyPayment = abs(monthlyPayment)
        lease.interestRate = max(rate, 0)
        lease.isLease = false
        lease.loanStartDate = .now
        lease.payoffDate = nil
        if let due = lease.loanBill?.dueDate { LoanBill.sync(lease, dueDate: due, in: context) }
        context.saveNow()
    }

    /// Adds the car or house as an asset worth `value`, copying the picture and VIN over, and archives the loan. The loan's history stays in the archive.
    @discardableResult
    static func makeAsset(from loan: Account, type: AccountType, name: String, value: Decimal, in context: ModelContext) -> Account {
        let asset = Account(name: String(name.trimmingCharacters(in: .whitespaces).prefix(Account.maxNameLength)), type: type, openingBalance: max(value, 0))
        asset.photoData = loan.photoData
        asset.vin = Account.typeHasVIN(type) ? loan.vin : ""
        context.insert(asset)
        archive(loan, in: context)
        context.saveNow()
        return asset
    }
}
