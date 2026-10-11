import Foundation
import SwiftData
import UniformTypeIdentifiers

/// A complete copy of everything in Piggybank, as one JSON file. Saved and opened from the Mac.
/// Debug builds also use it so the testing tools can keep a safety copy.
/// Money amounts are stored as text so no cent is ever lost to rounding.
struct BackupFile: Codable {
    static let currentVersion = 1

    var version = BackupFile.currentVersion
    var exportedAt = Date.now
    var categories: [CategoryRecord] = []
    var accounts: [AccountRecord] = []
    var payees: [PayeeRecord] = []
    var transactions: [TransactionRecord] = []
    var holdings: [HoldingRecord] = []
    var bills: [BillRecord] = []
    /// Added after format 1 shipped, so files from before it simply have none.
    var goals: [GoalRecord] = []
    var paymentMethods: [PaymentMethodRecord] = []
    /// Your preferences, so a restore brings back the whole setup. Absent in older files.
    var settings: SettingsRecord?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        categories = try c.decode([CategoryRecord].self, forKey: .categories)
        accounts = try c.decode([AccountRecord].self, forKey: .accounts)
        payees = try c.decode([PayeeRecord].self, forKey: .payees)
        transactions = try c.decode([TransactionRecord].self, forKey: .transactions)
        holdings = try c.decode([HoldingRecord].self, forKey: .holdings)
        bills = try c.decode([BillRecord].self, forKey: .bills)
        goals = try c.decodeIfPresent([GoalRecord].self, forKey: .goals) ?? []
        paymentMethods = try c.decodeIfPresent([PaymentMethodRecord].self, forKey: .paymentMethods) ?? []
        settings = try c.decodeIfPresent(SettingsRecord.self, forKey: .settings)
    }

    struct SettingsRecord: Codable {
        /// Empty means "use this device's currency".
        var currencyCode: String
        var appearance: String
        var billRemindersOn: Bool
    }

    struct PaymentMethodRecord: Codable {
        var name: String
        var symbol: String
    }

    struct GoalRecord: Codable {
        var name: String
        var targetAmount: String
        var startingAmount: String
        var targetDate: Date?
        var symbol: String
        var colorHex: String
        var notes: String
        var createdAt: Date
        var completedAt: Date?
        var accountID: Int?
        var contributions: [ContributionRecord]
        /// Added with payoff goals. Missing in older files, which were all saving goals.
        var kind: String?
        var goalBalance: String?
        var finalAmount: String?
        var categoryName: String?
    }

    struct ContributionRecord: Codable {
        var amount: String
        var date: Date
        var note: String
        var createdAt: Date
    }

    struct CategoryRecord: Codable {
        var key: String?
        var name: String
        var colorHex: String
        var symbol: String
        var monthlyLimit: String
        var isIncome: Bool
        var showOnBudgets: Bool
    }

    struct AccountRecord: Codable {
        var id: Int
        var name: String
        var type: String
        var openingBalance: String
        var isClosed: Bool
        var institution: String
        var accountNumber: String
        var routingNumber: String
        var loanPurpose: String
        var originalLoanAmount: String
        var monthlyPayment: String
        var payoffDate: Date?
        var loanStartDate: Date?
        var interestRate: Double
        var isLease: Bool
        var vin: String
        var notes: String
        var photoData: Data?
        /// Added after version 1 files existed, so older backups simply leave it out.
        var creditLimit: String?
        /// The built-in Cash on Hand.
        var isDefault: Bool?
    }

    struct PayeeRecord: Codable {
        var name: String
        var lastCategoryKey: String?
        var lastAmount: String
    }

    struct TransactionRecord: Codable {
        var accountID: Int
        var date: Date
        var payee: String
        var categoryKey: String?
        var memo: String
        var amount: String
        var status: String
        var transferID: String?
        var paymentType: String?
        /// Name of one of your own payment methods. Added after format 1; absent in older files.
        var customMethodName: String?
        var checkNumber: String
        var createdAt: Date
        /// Added after format 1; absent in older files.
        var receiptData: Data?
        var noReceipt: Bool?
        var isBillPayment: Bool?
        /// Position in `bills` of the bill this payment settled, and the due date it settled.
        var isAtmWithdrawal: Bool?
        var paidBillIndex: Int?
        var paidDueDate: Date?
    }

    struct HoldingRecord: Codable {
        var accountID: Int
        var name: String
        var symbol: String
        var shares: String
        var price: String
        var costBasis: String
        var priceDate: Date
        var createdAt: Date
        var events: [EventRecord]
    }

    struct EventRecord: Codable {
        var date: Date
        var shares: String
        var price: String
        var createdAt: Date
    }

    struct BillRecord: Codable {
        var name: String
        var amount: String
        var frequency: String
        var dueDate: Date
        var remindDaysBefore: Int
        var remindersOn: Bool
        var isImportant: Bool
        var notes: String
        var paidDates: [Date]
        var loanAccountID: Int?
        var createdAt: Date
        /// Added after version 1 files existed, so older backups simply leave it out.
        var photoData: Data?
        var categoryKey: String?
    }

    /// A short description for the confirmation message.
    var summary: String {
        func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        let customCategories = categories.filter { $0.key?.hasPrefix(Category.customKeyPrefix) == true }.count
        var parts = [count(accounts.count, "account"), count(transactions.count, "transaction"), count(bills.count, "bill"), count(goals.count, "goal")]
        if customCategories > 0 { parts.append("\(customCategories) custom categor\(customCategories == 1 ? "y" : "ies")") }
        if !paymentMethods.isEmpty { parts.append(count(paymentMethods.count, "custom payment method")) }
        return parts.joined(separator: ", ")
    }
}

enum DataBackup {
    /// Backups are saved as `.pig` files, a type the app declares in its Info.plist so Finder shows them with the app's icon.
    static let fileExtension = "pig"
    static let fileType = UTType(exportedAs: "vault.Piggybank.backup", conformingTo: .json)

    enum BackupError: LocalizedError {
        case unreadable
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unreadable: "That file isn't a Piggybank Financial backup."
            case .newerVersion(let version): "That backup is from a newer version of Piggybank Financial (format \(version)). Update the app and try again."
            }
        }
    }

    private static func text(_ value: Decimal) -> String { "\(value)" }
    private static func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }

    // MARK: Export

    @MainActor
    static func make(from context: ModelContext) throws -> BackupFile {
        var file = BackupFile()
        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)])).live
        let ids = Dictionary(uniqueKeysWithValues: accounts.enumerated().map { ($1.persistentModelID, $0) })

        file.categories = try context.fetch(FetchDescriptor<Category>()).live.map {
            .init(key: $0.systemKey, name: $0.name, colorHex: $0.colorHex, symbol: $0.symbol,
                  monthlyLimit: text($0.monthlyLimit), isIncome: $0.isIncome, showOnBudgets: $0.showOnBudgets)
        }

        file.accounts = accounts.enumerated().map { index, a in
            .init(id: index, name: a.name, type: a.type.rawValue, openingBalance: text(a.openingBalance), isClosed: a.isClosed,
                  institution: a.institution, accountNumber: a.accountNumber, routingNumber: a.routingNumber,
                  loanPurpose: a.loanPurpose, originalLoanAmount: text(a.originalLoanAmount),
                  monthlyPayment: text(a.monthlyPayment), payoffDate: a.payoffDate, loanStartDate: a.loanStartDate,
                  interestRate: a.interestRate, isLease: a.isLease, vin: a.vin, notes: a.notes, photoData: a.photoData,
                  creditLimit: text(a.creditLimit), isDefault: a.isDefault)
        }

        file.payees = try context.fetch(FetchDescriptor<Payee>()).live.map {
            .init(name: $0.name, lastCategoryKey: $0.lastCategory?.isLive == true ? $0.lastCategory?.systemKey : nil,
                  lastAmount: text($0.lastAmount))
        }

        let liveBills = try context.fetch(FetchDescriptor<Bill>()).live
        let billIDs = Dictionary(uniqueKeysWithValues: liveBills.enumerated().map { ($1.persistentModelID, $0) })

        for account in accounts {
            guard let accountID = ids[account.persistentModelID] else { continue }
            for t in account.transactions.live {
                file.transactions.append(.init(
                    accountID: accountID, date: t.date, payee: t.payee,
                    categoryKey: t.category?.isLive == true ? t.category?.systemKey : nil,
                    memo: t.memo, amount: text(t.amount), status: t.status.rawValue,
                    transferID: t.transferID?.uuidString, paymentType: t.paymentType?.rawValue,
                    customMethodName: t.customMethod?.isLive == true ? t.customMethod?.name : nil,
                    checkNumber: t.checkNumber, createdAt: t.createdAt, receiptData: t.receiptData,
                    noReceipt: t.noReceipt, isBillPayment: t.isBillPayment, isAtmWithdrawal: t.isAtmWithdrawal,
                    paidBillIndex: t.paidBill?.isLive == true ? billIDs[t.paidBill!.persistentModelID] : nil,
                    paidDueDate: t.paidDueDate))
            }
            for h in account.holdings.live {
                file.holdings.append(.init(
                    accountID: accountID, name: h.name, symbol: h.symbol, shares: text(h.shares), price: text(h.price),
                    costBasis: text(h.costBasis), priceDate: h.priceDate, createdAt: h.createdAt,
                    events: h.events.live.map { .init(date: $0.date, shares: text($0.shares), price: text($0.price), createdAt: $0.createdAt) }))
            }
        }

        file.bills = liveBills.map { b in
            .init(name: b.name, amount: text(b.amount), frequency: b.frequencyRaw, dueDate: b.dueDate,
                  remindDaysBefore: b.remindDaysBefore, remindersOn: b.remindersOn, isImportant: b.isImportant,
                  notes: b.notes, paidDates: b.paidDates,
                  loanAccountID: b.loan?.isLive == true ? ids[b.loan!.persistentModelID] : nil,
                  createdAt: b.createdAt, photoData: b.photoData,
                  categoryKey: b.category?.isLive == true ? b.category?.systemKey : nil)
        }

        file.paymentMethods = try context.fetch(FetchDescriptor<CustomPaymentMethod>()).live.map { .init(name: $0.name, symbol: $0.symbol) }

        file.goals = try context.fetch(FetchDescriptor<Goal>()).live.map { g in
            .init(name: g.name, targetAmount: text(g.targetAmount), startingAmount: text(g.startingAmount),
                  targetDate: g.targetDate, symbol: g.symbol, colorHex: g.colorHex, notes: g.notes,
                  createdAt: g.createdAt, completedAt: g.completedAt,
                  accountID: g.account?.isLive == true ? ids[g.account!.persistentModelID] : nil,
                  contributions: g.contributions.live.map { .init(amount: text($0.amount), date: $0.date, note: $0.note, createdAt: $0.createdAt) },
                  kind: g.kindRaw, goalBalance: text(g.goalBalance), finalAmount: g.finalAmount.map { text($0) }, categoryName: g.categoryName)
        }
        file.settings = .init(
            currencyCode: AppSettings.shared.currencyCode,
            appearance: AppSettings.shared.appearance.rawValue,
            billRemindersOn: BillNotifier.isEnabled
        )
        return file
    }

    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let file = try? decoder.decode(BackupFile.self, from: data) else { throw BackupError.unreadable }
        guard file.version <= BackupFile.currentVersion else { throw BackupError.newerVersion(file.version) }
        return file
    }

    // MARK: Restore

    /// Replaces everything with the contents of `file`. Built-in categories keep their identity and take the backup's
    /// budget amounts; custom budgets are replaced with the backup's.
    @MainActor
    static func restore(_ file: BackupFile, into context: ModelContext) throws {
        // Clear out the current data. Objects are deleted one at a time; a batch delete fails on the links between them.
        try context.deleteAllTransactions()
        for item in try context.fetch(FetchDescriptor<Account>()) { context.delete(item) }   // takes holdings with it
        for item in try context.fetch(FetchDescriptor<Payee>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Bill>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Goal>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<CustomPaymentMethod>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Category>()) where item.isCustom { context.delete(item) }
        try context.save()

        // Categories: built-in ones already exist, so only their budget settings are applied.
        Category.ensureSystemCategories(in: context)
        var byKey: [String: Category] = [:]
        for category in try context.fetch(FetchDescriptor<Category>()) {
            if let key = category.systemKey { byKey[key] = category }
        }
        for record in file.categories {
            if let key = record.key, let existing = byKey[key] {
                existing.monthlyLimit = decimal(record.monthlyLimit)
                existing.showOnBudgets = record.showOnBudgets
            } else if let key = record.key, key.hasPrefix(Category.customKeyPrefix) {
                let made = Category(name: record.name, colorHex: record.colorHex, symbol: record.symbol,
                                    monthlyLimit: decimal(record.monthlyLimit), isIncome: record.isIncome, systemKey: key)
                made.showOnBudgets = record.showOnBudgets
                context.insert(made)
                byKey[key] = made
            }
        }

        var accounts: [Int: Account] = [:]
        for record in file.accounts {
            guard let type = AccountType(rawValue: record.type) else { continue }
            let account = Account(name: record.name, type: type, openingBalance: decimal(record.openingBalance))
            account.isClosed = record.isClosed
            account.institution = record.institution
            account.accountNumber = record.accountNumber
            account.routingNumber = record.routingNumber
            account.loanPurpose = record.loanPurpose
            account.originalLoanAmount = decimal(record.originalLoanAmount)
            account.monthlyPayment = decimal(record.monthlyPayment)
            account.payoffDate = record.payoffDate
            account.loanStartDate = record.loanStartDate
            account.interestRate = record.interestRate
            account.isLease = record.isLease
            account.vin = record.vin
            account.notes = record.notes
            account.photoData = record.photoData
            account.creditLimit = record.creditLimit.map { decimal($0) } ?? 0
            account.isDefault = record.isDefault ?? false
            context.insert(account)
            accounts[record.id] = account
        }

        for record in file.payees {
            context.insert(Payee(name: record.name, lastCategory: record.lastCategoryKey.flatMap { byKey[$0] },
                                 lastAmount: decimal(record.lastAmount)))
        }

        var methods: [String: CustomPaymentMethod] = [:]
        for record in file.paymentMethods {
            let method = CustomPaymentMethod(name: record.name, symbol: record.symbol)
            context.insert(method)
            methods[record.name] = method
        }

        var restoredTransactions: [(Transaction, BackupFile.TransactionRecord)] = []
        for record in file.transactions {
            guard let account = accounts[record.accountID] else { continue }
            let t = Transaction(account: account, date: record.date, payee: record.payee,
                                category: record.categoryKey.flatMap { byKey[$0] }, memo: record.memo,
                                amount: decimal(record.amount),
                                paymentType: record.paymentType.flatMap { PaymentType(rawValue: $0) })
            t.status = ClearedStatus(rawValue: record.status) ?? .uncleared
            t.transferID = record.transferID.flatMap { UUID(uuidString: $0) }
            t.checkNumber = record.checkNumber
            if t.paymentType == nil, let name = record.customMethodName { t.customMethod = methods[name] }
            t.createdAt = record.createdAt
            t.receiptData = record.receiptData
            t.noReceipt = record.noReceipt ?? false
            t.isBillPayment = record.isBillPayment ?? false
            t.isAtmWithdrawal = record.isAtmWithdrawal ?? false
            t.paidDueDate = record.paidDueDate
            context.insert(t)
            restoredTransactions.append((t, record))
        }

        for record in file.holdings {
            guard let account = accounts[record.accountID] else { continue }
            let h = Holding(account: account, name: record.name, symbol: record.symbol, shares: decimal(record.shares),
                            price: decimal(record.price), costBasis: decimal(record.costBasis))
            h.priceDate = record.priceDate
            h.createdAt = record.createdAt
            context.insert(h)
            for e in record.events {
                let event = HoldingEvent(holding: h, date: e.date, shares: decimal(e.shares), price: decimal(e.price))
                event.createdAt = e.createdAt
                context.insert(event)
            }
        }

        var restoredBills: [Bill] = []
        for record in file.bills {
            let bill = Bill(name: record.name, amount: decimal(record.amount),
                            frequency: BillFrequency(rawValue: record.frequency) ?? .monthly, dueDate: record.dueDate,
                            remindDaysBefore: record.remindDaysBefore, remindersOn: record.remindersOn,
                            isImportant: record.isImportant, notes: record.notes)
            bill.paidDates = record.paidDates
            bill.createdAt = record.createdAt
            bill.loan = record.loanAccountID.flatMap { accounts[$0] }
            bill.photoData = record.photoData
            bill.category = record.categoryKey.flatMap { byKey[$0] }
            context.insert(bill)
            restoredBills.append(bill)
        }
        // Reconnect each bill payment to the bill it settled.
        for (transaction, record) in restoredTransactions {
            if let index = record.paidBillIndex, restoredBills.indices.contains(index) {
                transaction.paidBill = restoredBills[index]
            }
        }

        for record in file.goals {
            let goal = Goal(name: record.name, targetAmount: decimal(record.targetAmount), startingAmount: decimal(record.startingAmount),
                            targetDate: record.targetDate, symbol: record.symbol, colorHex: record.colorHex, notes: record.notes,
                            account: record.accountID.flatMap { accounts[$0] },
                            kind: record.kind.flatMap { GoalKind(rawValue: $0) } ?? .save,
                            goalBalance: record.goalBalance.map { decimal($0) } ?? 0,
                            categoryName: record.categoryName ?? "")
            goal.createdAt = record.createdAt
            goal.completedAt = record.completedAt
            goal.finalAmount = record.finalAmount.map { decimal($0) }
            context.insert(goal)
            for c in record.contributions {
                let item = GoalContribution(goal: goal, amount: decimal(c.amount), date: c.date, note: c.note)
                item.createdAt = c.createdAt
                context.insert(item)
            }
        }
        // Cash on Hand is always there, even when the backup came from before it existed.
        Account.ensureDefault(in: context)
        try context.save()

        // Preferences come back too, so the whole setup is recalled.
        if let settings = file.settings {
            AppSettings.shared.setCurrencyCode(settings.currencyCode)
            if let appearance = Appearance(rawValue: settings.appearance) { AppSettings.shared.setAppearance(appearance) }
            UserDefaults.standard.set(settings.billRemindersOn, forKey: BillNotifier.enabledKey)
        }
    }
}
