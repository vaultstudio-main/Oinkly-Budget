import Foundation
import SwiftData
import AppKit

enum CheckStatus {
    case pending, running, ok, fixed, warning, failed
}

struct CheckStep: Identifiable {
    let id: String
    let title: String
    var status: CheckStatus = .pending
    var detail = ""
}

/// Runs the launch-time sanity checks: data present, categories in place, nothing inconsistent.
/// Problems it can repair safely it repairs and reports; anything else it reports without touching your data.
@Observable
final class StartupChecker {
    var steps: [CheckStep] = [
        CheckStep(id: "data", title: "Opening your data"),
        CheckStep(id: "categories", title: "Checking categories"),
        CheckStep(id: "budgets", title: "Checking budgets"),
        CheckStep(id: "accounts", title: "Checking accounts"),
        CheckStep(id: "transactions", title: "Checking transactions"),
        CheckStep(id: "payees", title: "Checking payees"),
        CheckStep(id: "icons", title: "Checking icons"),
        CheckStep(id: "save", title: "Saving"),
    ]

    var hasFailure: Bool { steps.contains { $0.status == .failed } }
    var hasWarning: Bool { steps.contains { $0.status == .warning } }

    /// How far along the checks are, 0...1.
    var progress: Double {
        let done = steps.filter { $0.status != .pending && $0.status != .running }.count
        return Double(done) / Double(max(steps.count, 1))
    }

    /// The checks that need the user's attention: a failure or a warning.
    var problems: [CheckStep] { steps.filter { $0.status == .failed || $0.status == .warning } }

    /// How long each check shows as running. Only here so the loading bar fills at a pace you can see.
    static let stepPause: Duration = .milliseconds(350)

    func run(in context: ModelContext, databaseError: Error?) async {
        for index in steps.indices {
            steps[index].status = .running
            try? await Task.sleep(for: Self.stepPause)

            let result: (CheckStatus, String)
            switch steps[index].id {
            case "data": result = checkData(context, databaseError: databaseError)
            case "categories": result = checkCategories(context)
            case "budgets": result = checkBudgets(context)
            case "accounts": result = checkAccounts(context)
            case "transactions": result = checkTransactions(context)
            case "payees": result = checkPayees(context)
            case "icons": result = checkIcons()
            default: result = save(context)
            }
            steps[index].status = result.0
            steps[index].detail = result.1

            // Nothing after a database failure can be trusted.
            if steps[index].id == "data", result.0 == .failed { return }
        }
    }

    // MARK: Checks

    private func checkData(_ context: ModelContext, databaseError: Error?) -> (CheckStatus, String) {
        if let databaseError {
            return (.failed, "Your saved data couldn't be opened: \(databaseError.localizedDescription)")
        }
        do {
            _ = try context.fetchCount(FetchDescriptor<Account>())
            _ = try context.fetchCount(FetchDescriptor<Transaction>())
            _ = try context.fetchCount(FetchDescriptor<Category>())
            _ = try context.fetchCount(FetchDescriptor<Payee>())
            return (.ok, "Database is readable")
        } catch {
            return (.failed, "Couldn't read your data: \(error.localizedDescription)")
        }
    }

    private func checkCategories(_ context: ModelContext) -> (CheckStatus, String) {
        let report = Category.ensureSystemCategories(in: context)
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let keys = categories.filter { !$0.isCustom }.compactMap(\.systemKey)
        let expected = Category.definitions.count

        guard Set(keys).count == expected, keys.count == expected, keys.allSatisfy({ key in Category.definitions.contains { $0.key == key } }) else {
            return (.failed, "Expected \(expected) built-in categories but found \(Set(keys).count)")
        }
        if report.changes == 0 {
            return (.ok, "All \(expected) built-in categories are in place")
        }
        var parts: [String] = []
        if report.added > 0 { parts.append("restored \(report.added)") }
        if report.adopted > 0 { parts.append("updated \(report.adopted)") }
        if report.merged > 0 { parts.append("merged \(report.merged) duplicate\(report.merged == 1 ? "" : "s")") }
        if report.repaired > 0 { parts.append("repaired \(report.repaired)") }
        if report.migrated > 0 { parts.append("moved \(report.migrated) old categor\(report.migrated == 1 ? "y" : "ies") into the built-in list") }
        if report.removed > 0 { parts.append("removed \(report.removed) unused old categor\(report.removed == 1 ? "y" : "ies")") }
        return (.fixed, "Fixed categories: " + parts.joined(separator: ", "))
    }

    private func checkBudgets(_ context: ModelContext) -> (CheckStatus, String) {
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let expenses = categories.filter { !$0.isIncome }
        var fixed = 0
        for category in expenses where category.monthlyLimit < 0 {
            category.monthlyLimit = 0
            fixed += 1
        }
        let total = expenses.reduce(Decimal(0)) { $0 + $1.monthlyLimit }
        let summary = "\(expenses.count) budgets, \(total.formatted(.appCurrency)) a month"
        return fixed > 0 ? (.fixed, "Reset \(fixed) negative budget\(fixed == 1 ? "" : "s"). \(summary)") : (.ok, summary)
    }

    private func checkAccounts(_ context: ModelContext) -> (CheckStatus, String) {
        // Cash on Hand is always there. Without it the app would have nowhere to record cash.
        Account.ensureDefault(in: context)
        try? context.save()
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        if accounts.addedByUser.isEmpty { return (.ok, "No accounts yet. Opening account setup") }

        // An account with no name can't be told apart in the sidebar: give it a name from its type.
        var named = 0
        for (index, account) in accounts.enumerated() where account.name.trimmingCharacters(in: .whitespaces).isEmpty {
            account.name = "\(account.type.title) \(index + 1)"
            named += 1
        }
        if named > 0 {
            return (.fixed, "Gave \(named) unnamed account\(named == 1 ? "" : "s") a name. \(accounts.count) found")
        }
        return (.ok, "\(accounts.count) account\(accounts.count == 1 ? "" : "s") found")
    }

    private static let recoveryAccountName = "Recovered Transactions"

    private func checkTransactions(_ context: ModelContext) -> (CheckStatus, String) {
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        var fixes: [String] = []

        // A transaction with no account is invisible everywhere. Attach it to a recovery account so nothing is lost.
        let orphans = transactions.filter { $0.account == nil }
        if !orphans.isEmpty {
            let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
            let recovery = accounts.first { $0.name == Self.recoveryAccountName } ?? {
                let created = Account(name: Self.recoveryAccountName, type: .checking)
                context.insert(created)
                return created
            }()
            for transaction in orphans { transaction.account = recovery }
            fixes.append("moved \(orphans.count) transaction\(orphans.count == 1 ? "" : "s") with no account into \"\(Self.recoveryAccountName)\"")
        }

        // A check number only means something on a check.
        let stray = transactions.filter { !$0.checkNumber.isEmpty && $0.paymentChoice?.isCheck != true }
        for transaction in stray { transaction.checkNumber = "" }
        if !stray.isEmpty { fixes.append("cleared \(stray.count) stray check number\(stray.count == 1 ? "" : "s")") }

        // A transfer has two sides. If one is gone (for example its account was deleted), the survivor
        // becomes an ordinary transaction so it can be edited and counted normally.
        let transferIDs = Dictionary(grouping: transactions.filter { $0.transferID != nil }, by: { $0.transferID! })
        let broken = transferIDs.values.filter { $0.count != 2 }.flatMap { $0 }
        for transaction in broken { transaction.transferID = nil }
        if !broken.isEmpty { fixes.append("released \(broken.count) transfer\(broken.count == 1 ? "" : "s") missing the other side") }

        // Confirm the repairs held.
        if transactions.contains(where: { $0.account == nil }) {
            return (.warning, "Some transactions still have no account")
        }
        if fixes.isEmpty { return (.ok, "\(transactions.count) transaction\(transactions.count == 1 ? "" : "s") found") }
        return (.fixed, "Fixed: " + fixes.joined(separator: ", "))
    }

    private func checkPayees(_ context: ModelContext) -> (CheckStatus, String) {
        let payees = (try? context.fetch(FetchDescriptor<Payee>())) ?? []
        var seen: [String: Payee] = [:]
        var merged = 0
        for payee in payees {
            let key = PayeeMemory.normalized(payee.name)
            if seen[key] != nil {
                context.delete(payee)
                merged += 1
            } else {
                seen[key] = payee
            }
        }
        if merged > 0 { return (.fixed, "Merged \(merged) duplicate payee\(merged == 1 ? "" : "s")") }
        return (.ok, "\(payees.count) memorized payee\(payees.count == 1 ? "" : "s")")
    }

    private func checkIcons() -> (CheckStatus, String) {
        let symbols = Set(Category.definitions.map(\.symbol) + AccountType.allCases.map(\.symbol) + PaymentType.allCases.map(\.symbol))
        let missing = symbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }.sorted()
        if !missing.isEmpty { return (.warning, "Missing icons: " + missing.joined(separator: ", ")) }
        return (.ok, "All \(symbols.count) icons found")
    }

    private func save(_ context: ModelContext) -> (CheckStatus, String) {
        do {
            if context.hasChanges {
                try context.save()
                return (.ok, "Saved repairs")
            }
            return (.ok, "Everything is up to date")
        } catch {
            return (.failed, "Couldn't save: \(error.localizedDescription)")
        }
    }
}
