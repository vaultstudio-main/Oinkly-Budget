#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Test data for trying every feature and taking screenshots. Debug builds only: none of this is in a release build.
/// Loading it replaces whatever is in the store. It is for testing only: nothing is saved first.
@MainActor
enum TestData {
    // MARK: Wipe

    /// Removes everything you added: accounts, transactions, bills, goals, payees, custom categories and payment methods.
    /// Cash on Hand and the built-in categories stay, emptied out.
    static func wipe(in context: ModelContext) throws {
        try context.deleteAllTransactions()
        for account in try context.fetch(FetchDescriptor<Account>()) {
            if account.isDefault {
                account.openingBalance = 0
                account.notes = ""
            } else {
                context.delete(account)
            }
        }
        for item in try context.fetch(FetchDescriptor<Payee>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Tag>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<RecurringTransaction>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Bill>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Goal>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<CustomPaymentMethod>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Category>()) where item.isCustom { context.delete(item) }
        try context.save()
        OutlookSettings.forgetData()
        Category.ensureSystemCategories(in: context)
        Account.ensureDefault(in: context)
        SchemaUpgrade.seedTaxFlags(in: context, force: true)
        try context.save()
    }

    // MARK: Fill

    /// How many months before this one the test data reaches back. 26 gives a little over two years of history.
    static let monthsOfHistory = 26

    /// Small everyday purchases added for every day of the history, to make the transaction count large.
    /// About 2 a day gives roughly 2,000 over two years, and keeps a month's spending below the pay.
    static var everydayPurchasesPerDay: Int {
        // For load testing: `open -n OinklyBudget.app --args -piggybank.testPurchasesPerDay 12`.
        let override = UserDefaults.standard.integer(forKey: "piggybank.testPurchasesPerDay")
        return override > 0 ? override : 2
    }

    /// A believable two-plus years of everything the app does. Dates are relative to today, so it always looks current.
    static func load(into context: ModelContext) throws {
        try wipe(in: context)

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
        /// A day of the month, some months back. Clamped so it exists in every month.
        func monthDay(_ back: Int, _ d: Int) -> Date {
            let base = cal.date(byAdding: .month, value: -back, to: today)!
            var c = cal.dateComponents([.year, .month], from: base)
            c.day = min(d, 28)
            return cal.date(from: c)!
        }

        let categories = try context.fetch(FetchDescriptor<Category>())
        func cat(_ key: String) -> Category? { categories.first { $0.systemKey == key } }

        // Budgets on the built-in categories.
        for (key, limit) in [("groceries", 520), ("dining-out", 220), ("gas-fuel", 160), ("entertainment", 100),
                             ("utilities", 260), ("phone-internet", 140), ("shopping", 180), ("subscriptions", 45),
                             ("fitness", 45), ("pets", 80), ("healthcare", 120), ("charity", 60), ("clothing", 90),
                             ("home-improvement", 150), ("books-media", 35), ("salon-barber", 40)] as [(String, Decimal)] {
            cat(key)?.monthlyLimit = limit
        }
        // Only the budgets above are in use. The starter limits on the other categories would add up to thousands a month.
        let inUse = Set(["groceries", "dining-out", "gas-fuel", "entertainment", "utilities", "phone-internet", "shopping", "subscriptions",
                         "fitness", "pets", "healthcare", "charity", "clothing", "home-improvement", "books-media", "salon-barber"])
        for category in categories where !category.isIncome && !category.isCustom && !inUse.contains(category.systemKey ?? "") { category.monthlyLimit = 0 }

        // Custom categories and payment methods.
        let coffee = Category(name: "Coffee Runs", colorHex: "A2845E", symbol: "cup.and.saucer", monthlyLimit: 40,
                              isIncome: false, systemKey: Category.customKeyPrefix + "coffee-runs")
        let sitter = Category(name: "House Sitting", colorHex: "30B0C7", symbol: "house.and.flag", monthlyLimit: 0,
                              isIncome: true, systemKey: Category.customKeyPrefix + "house-sitting")
        context.insert(coffee)
        context.insert(sitter)
        // A few weekly and cash budgets, so those parts of the Budgets page have something to show.
        BudgetPeriods.set(amount: 60, weekly: true, for: cat("dining-out") ?? coffee, in: context)
        BudgetPeriods.set(amount: 15, weekly: true, for: coffee, in: context)
        CashBudgets.set(true, for: coffee, in: context)
        if let barber = cat("salon-barber") { CashBudgets.set(true, for: barber, in: context) }
        context.insert(CustomPaymentMethod(name: "Company Card", symbol: "creditcard"))
        context.insert(CustomPaymentMethod(name: "Tap to Pay", symbol: "wave.3.right"))

        // Accounts.
        func account(_ name: String, _ type: AccountType, _ opening: Decimal) -> Account {
            // Bank and investment accounts start with a real, locked Deposit, the way the app now makes them.
            let deposits = OpeningDeposit.applies(to: type) && opening > 0
            let made = Account(name: name, type: type, openingBalance: deposits ? 0 : opening)
            context.insert(made)
            if deposits { OpeningDeposit.set(opening, for: made, date: monthDay(monthsOfHistory, 1), in: context) }
            return made
        }
        let cash = Account.ensureDefault(in: context)
        let checking = account("Everyday Checking", .checking, 35_000)
        checking.institution = "Harbor Credit Union"
        checking.accountNumber = "004821907365"
        checking.achRouting = "021000021"
        checking.wireRouting = "HARBUS33X"
        checking.digitalRouting = "084009519"
        checking.notes = "Main account for pay and bills."
        let savings = account("Rainy Day Savings", .savings, 7_800)
        savings.institution = "Harbor Credit Union"
        savings.accountNumber = "004821907412"
        // Savings set aside for goals. Each started with a deposit, and each has a goal that follows it.
        let tripFund = account("Japan Trip Fund", .savings, 300)
        tripFund.institution = "Harbor Credit Union"
        tripFund.accountNumber = "004821907455"
        let downFund = account("House Down Payment", .savings, 6_000)
        downFund.institution = "Summit Online Bank"
        downFund.accountNumber = "770014420981"

        let card = account("Sapphire Card", .creditCard, -1_150)
        card.institution = "Northgate Bank"
        card.accountNumber = "4111111111111111"
        card.creditLimit = 5_000
        card.interestRate = 21.99
        card.monthlyPayment = 35
        let storeCard = account("Home Store Card", .storeCard, -1_190)
        storeCard.institution = "Home Store"
        storeCard.accountNumber = "6011000990139424"
        storeCard.creditLimit = 1_500
        storeCard.interestRate = 26.99
        storeCard.monthlyPayment = 40

        let auto = account("Honda Civic Loan", .autoLoan, -15_800)
        auto.institution = "Northgate Auto Finance"
        auto.loanPurpose = "2022 Honda Civic"
        auto.vin = "2HGFC2F59NH512345"
        auto.originalLoanAmount = 24_000
        auto.monthlyPayment = 412
        auto.interestRate = 5.9
        auto.loanStartDate = cal.date(byAdding: .year, value: -3, to: today)
        auto.payoffDate = cal.date(byAdding: .year, value: 2, to: today)
        let mortgage = account("Home Mortgage", .mortgage, -241_000)
        mortgage.institution = "Lakeside Mortgage"
        mortgage.loanPurpose = "123 Maple Street"
        mortgage.originalLoanAmount = 280_000
        mortgage.monthlyPayment = 1_640
        mortgage.interestRate = 6.1
        mortgage.loanStartDate = cal.date(byAdding: .year, value: -4, to: today)
        mortgage.payoffDate = cal.date(byAdding: .year, value: 26, to: today)
        let student = account("Student Loan", .studentLoan, -11_200)
        student.institution = "EdFund"
        student.loanPurpose = "Bachelor's degree"
        student.originalLoanAmount = 18_000
        student.monthlyPayment = 190
        student.interestRate = 4.5
        student.loanStartDate = cal.date(byAdding: .year, value: -5, to: today)
        student.payoffDate = cal.date(byAdding: .year, value: 5, to: today)

        let brokerage = account("Brokerage", .brokerage, 9_500)
        brokerage.institution = "Summit Invest"
        let retirement = account("401(k)", .retirement401k, 28_000)
        retirement.institution = "Acme Corp Plan"
        let roth = account("Roth IRA", .rothIRA, 11_000)
        roth.institution = "Summit Invest"
        let college = account("College 529", .education529, 6_200)
        college.institution = "State 529 Plan"
        let crypto = account("Crypto Wallet", .crypto, 1_500)
        crypto.institution = "CoinBase Exchange"
        let house = account("Family Home", .realEstate, 410_000)
        house.notes = "Estimated value."
        let car = account("Honda Civic", .vehicle, 17_500)
        car.vin = "2HGFC2F59NH512345"

        // Holdings.
        let holdingList = [
            Holding(account: brokerage, name: "Total Market Index Fund", symbol: "VTI", shares: 24.5, price: 268.40, costBasis: 5_900),
            Holding(account: brokerage, name: "Apple Inc.", symbol: "AAPL", shares: 10, price: 227.10, costBasis: 1_700),
            Holding(account: brokerage, name: "NVIDIA Corp.", symbol: "NVDA", shares: 18, price: 131.60, costBasis: 1_450),
            Holding(account: retirement, name: "Target Date 2055 Fund", symbol: "TDFXX", shares: 410, price: 38.20, costBasis: 13_800),
            Holding(account: retirement, name: "Total Bond Index Fund", symbol: "VBTLX", shares: 520, price: 9.62, costBasis: 5_400),
            Holding(account: roth, name: "S&P 500 Index Fund", symbol: "VFIAX", shares: 31, price: 521.30, costBasis: 13_200),
            Holding(account: roth, name: "International Stock Index", symbol: "VXUS", shares: 120, price: 64.80, costBasis: 7_100),
            Holding(account: college, name: "Age-Based 529 Portfolio", symbol: "529AB", shares: 310, price: 24.90, costBasis: 7_000),
            Holding(account: crypto, name: "Bitcoin", symbol: "BTC", shares: 0.02, price: 67_000, costBasis: 1_200),
            Holding(account: crypto, name: "Ethereum", symbol: "ETH", shares: 0.35, price: 2_600, costBasis: 1_000),
        ]
        for holding in holdingList { context.insert(holding) }
        // A year of prices for each holding, drifting up with some dips, so returns by holding have something to show.
        let drift: [Double] = [0, 0.012, 0.031, 0.02, 0.045, 0.06, 0.052, 0.078, 0.095, 0.083, 0.11, 0.124, 0.139]
        for holding in holdingList {
            let now = holding.price
            let shares = holding.shares
            for back in 0...12 {
                let price = now * Decimal(1 + drift[12 - back] - drift[12])
                context.insert(HoldingEvent(holding: holding, date: monthDay(back, 1), shares: back > 8 ? shares * Decimal(0.9) : shares,
                                            price: back == 0 ? now : price))
            }
        }

        // Everyday transactions.
        @discardableResult
        func tx(_ account: Account, _ date: Date, _ payee: String, _ key: String?, _ amount: Decimal,
                method: PaymentType? = nil, state: ReconcileState = .reconciled, memo: String = "") -> Transaction? {
            guard date <= today else { return nil }
            let made = Transaction(account: account, date: date, payee: payee, category: key.flatMap { cat($0) }, memo: memo,
                                   amount: amount, paymentType: method)
            made.state = state
            context.insert(made)
            if amount < 0, key != nil { PayeeMemory.record(name: payee, category: made.category, amount: amount, in: context) }
            return made
        }

        let grocers = ["Fresh Market", "Corner Grocery", "Green Basket"]
        let diners = ["Taco Corner", "Luigi's Pizza", "Blue Door Cafe", "Harvest Kitchen"]
        for back in 0...monthsOfHistory {
            // Amounts drift a little from month to month without growing forever.
            let drift = back % 4
            // Pay and savings.
            tx(checking, monthDay(back, 1), "Acme Corp Payroll", "paycheck", 4_500, method: .directDeposit)
            tx(checking, monthDay(back, 15), "Acme Corp Payroll", "paycheck", 4_500, method: .directDeposit)
            tx(savings, monthDay(back, 28), "Interest", "interest-dividends", 11.80)
            if back == 1 { tx(checking, monthDay(back, 9), "Weekend House Sit", "custom-house-sitting", 180, method: .venmo) }

            // Groceries and food.
            for (index, d) in [3, 10, 17, 24].enumerated() {
                tx(checking, monthDay(back, d), grocers[(index + back) % grocers.count], "groceries",
                   -Decimal(62 + (index * 17 + back * 9) % 70), method: .debitCard)
                tx(card, monthDay(back, d + 2), diners[(index + back) % diners.count], "dining-out",
                   -Decimal(18 + (index * 11 + back * 7) % 34), method: .creditCard)
            }
            tx(card, monthDay(back, 6), "Speedy Fuel", "gas-fuel", -Decimal(41 + drift * 3), method: .creditCard)
            tx(card, monthDay(back, 20), "Speedy Fuel", "gas-fuel", -Decimal(46 - drift), method: .creditCard)
            tx(card, monthDay(back, 5), "Streamly", "subscriptions", -15.99, method: .creditCard)
            tx(card, monthDay(back, 14), "Cinema 8", "entertainment", -Decimal(26 + drift * 2), method: .creditCard)
            tx(card, monthDay(back, 22), "Paw Pals Vet", "pets", -Decimal(38 + drift * 5), method: .creditCard)
            if back != 2 { tx(card, monthDay(back, 18), "Maple Outfitters", "shopping", -Decimal(54 + drift * 12), method: .creditCard) }
            tx(cash, monthDay(back, 8), "Farmers Market", "groceries", -Decimal(24 + drift * 3), method: .cash)
            tx(cash, monthDay(back, 16), "Bean There Coffee", "custom-coffee-runs", -Decimal(9 + drift), method: .cash)
            tx(cash, monthDay(back, 25), "Corner Barber", "salon-barber", -28, method: .cash)

            // Tags on a few kinds of spending.
            if back % 2 == 0 { tx(card, monthDay(back, 3), "Trail Shoes Co", "shopping", -Decimal(64 + drift * 4), method: .creditCard).map { Tags.apply(["Gifts"], to: $0, in: context) } }
            if back < 3 { tx(checking, monthDay(back, 21), "Hardware Depot", "home-improvement", -Decimal(86 + drift * 9), method: .debitCard).map { Tags.apply(["Home Projects", "Tax Receipts"], to: $0, in: context) } }

            // One shop split across three categories.
            if let split = tx(checking, monthDay(back, 12), "Big Box Store", nil, -120, method: .debitCard) {
                Splits.apply([SplitDraft(category: cat("groceries"), amount: 70),
                              SplitDraft(category: cat("shopping"), amount: 30),
                              SplitDraft(category: cat("pets"), amount: 20)], to: split, isPayment: true, in: context)
            }

            // Moving money.
            if let date = Optional(monthDay(back, 2)), date <= today {
                let move = Transfers.move(from: checking, to: savings, amount: 400, date: date, state: .reconciled,
                                          payeeOut: "Transfer to Rainy Day Savings", payeeIn: "Transfer from Everyday Checking", in: context)
                _ = move
            }
            let atmDate = monthDay(back, 7)
            if atmDate <= today {
                let moved = Transfers.move(from: checking, to: cash, amount: 300, date: atmDate, memo: "Cash", state: .reconciled,
                                           paymentType: .atm, checkNumber: "", payeeOut: "ATM Withdrawal", payeeIn: "ATM Withdrawal", in: context)
                moved.into.paymentChoice = .type(.cash)
                for leg in [moved.out, moved.into] { leg.isAtmWithdrawal = true; leg.noReceipt = true }
            }

            // Card payments.
            if back >= 1 {
                let pay = Transfers.pay(from: checking, toward: card, amount: 1_550, date: monthDay(back, 26), memo: "Statement payment",
                                        state: .reconciled, paymentType: nil, checkNumber: "", in: context)
                pay.out.paymentChoice = .type(.bankTransfer)
                pay.into.paymentChoice = .type(.bankTransfer)
                pay.into.noReceipt = true

                let storePay = Transfers.pay(from: checking, toward: storeCard, amount: 280, date: monthDay(back, 27), memo: "Statement payment",
                                             state: .reconciled, paymentType: nil, checkNumber: "", in: context)
                storePay.out.paymentChoice = .type(.bankTransfer)
                storePay.into.paymentChoice = .type(.bankTransfer)
                storePay.into.noReceipt = true
            }

            // Investments.
            tx(retirement, monthDay(back, 2), "Payroll contribution", nil, 500).map { InvestmentType.contribution.apply(to: $0, categories: categories) }
            if back == 0 || back == 2 {
                tx(brokerage, monthDay(back, 12), "Market gain", nil, 184).map { InvestmentType.gain.apply(to: $0, categories: categories) }
            }
            tx(brokerage, monthDay(back, 12), "Dividend", nil, 21.40).map { InvestmentType.dividend.apply(to: $0, categories: categories) }
            // Growth every month, with the odd loss, and money going into the other investment accounts.
            let gain = Decimal(95 + (back * 41) % 240)
            if back % 6 == 5 {
                tx(brokerage, monthDay(back, 20), "Market loss", nil, 210).map { InvestmentType.loss.apply(to: $0, categories: categories) }
            } else if back != 0 && back != 2 {
                tx(brokerage, monthDay(back, 20), "Market gain", nil, gain).map { InvestmentType.gain.apply(to: $0, categories: categories) }
            }
            tx(retirement, monthDay(back, 22), "Fund growth", nil, Decimal(210 + (back * 29) % 160)).map { InvestmentType.gain.apply(to: $0, categories: categories) }
            tx(roth, monthDay(back, 5), "IRA contribution", nil, 250).map { InvestmentType.contribution.apply(to: $0, categories: categories) }
            tx(roth, monthDay(back, 22), "Fund growth", nil, Decimal(70 + (back * 31) % 110)).map { InvestmentType.gain.apply(to: $0, categories: categories) }
            tx(college, monthDay(back, 6), "529 contribution", nil, 200).map { InvestmentType.contribution.apply(to: $0, categories: categories) }
            tx(college, monthDay(back, 23), "Fund growth", nil, Decimal(28 + (back * 17) % 60)).map { InvestmentType.gain.apply(to: $0, categories: categories) }
            if back <= 12 { tx(crypto, monthDay(back, 8), "Exchange deposit", nil, 100).map { InvestmentType.contribution.apply(to: $0, categories: categories) } }
            if back % 4 == 3 {
                tx(crypto, monthDay(back, 21), "Market loss", nil, Decimal(60 + (back * 7) % 90)).map { InvestmentType.loss.apply(to: $0, categories: categories) }
            } else {
                tx(crypto, monthDay(back, 21), "Market gain", nil, Decimal(40 + (back * 53) % 180)).map { InvestmentType.gain.apply(to: $0, categories: categories) }
            }

            // Money set aside for goals: a trip started nine months ago, a down payment fourteen months ago.
            if back <= 8, monthDay(back, 3) <= today {
                _ = Transfers.move(from: checking, to: tripFund, amount: 300, date: monthDay(back, 3), state: .reconciled,
                                   payeeOut: "Transfer to Japan Trip Fund", payeeIn: "Transfer from Everyday Checking", in: context)
            }
            if back <= 14, monthDay(back, 4) <= today {
                _ = Transfers.move(from: checking, to: downFund, amount: 500, date: monthDay(back, 4), state: .reconciled,
                                   payeeOut: "Transfer to House Down Payment", payeeIn: "Transfer from Everyday Checking", in: context)
            }
            tx(downFund, monthDay(back, 28), "Interest", "interest-dividends", 19.40)
            tx(tripFund, monthDay(back, 28), "Interest", "interest-dividends", 2.10)

            // The same shops written different ways, for the duplicate payee report and Clean Up.
            if back <= 5 {
                let whole = ["Whole Foods Market", "WHOLE FOODS MKT", "Whole Foods #102"]
                let star = ["Starbucks", "Starbucks #1234", "STARBUCKS COFFEE"]
                tx(checking, monthDay(back, 11), whole[back % 3], "groceries", -Decimal(54 + back * 6), method: .debitCard)
                tx(card, monthDay(back, 13), star[back % 3], "coffee-snacks", -Decimal(6 + back), method: .creditCard)
                tx(card, monthDay(back, 19), star[(back + 1) % 3], "coffee-snacks", -Decimal(7 + back), method: .creditCard)
            }

            // Spending people claim at tax time, and more kinds of income.
            tx(checking, monthDay(back, 12), "Hope Food Bank", "charity", -50, method: .debitCard)
            if back % 3 == 0 { tx(checking, monthDay(back, 17), "Family Clinic", "healthcare", -Decimal(40 + (back * 3) % 60), method: .debitCard) }
            if back % 6 == 0 { tx(checking, monthDay(back, 21), "Bright Smiles Dental", "dental", -180, method: .debitCard) }
            if back % 6 == 2 { tx(checking, monthDay(back, 10), "County Treasurer", "property-tax", -1_850, method: .bankTransfer) }
            if back % 12 == 5 { tx(checking, monthDay(back, 14), "Community College", "education", -420, method: .debitCard) }
            let month = cal.component(.month, from: monthDay(back, 1))
            if month == 12 { tx(checking, monthDay(back, 20), "Acme Corp Bonus", "bonus", 2_000, method: .directDeposit) }
            if month == 3 { tx(checking, monthDay(back, 18), "IRS Refund", "tax-refund", 1_240, method: .directDeposit) }
            if back % 3 == 1 { tx(checking, monthDay(back, 24), "Side Gig Client", "freelance-income", Decimal(450 + (back * 13) % 300), method: .bankTransfer) }
        }

        // Everyday purchases, every day of the history, to put real volume in the store.
        addEverydayPurchases(today: today, context: context, categories: categories,
                             targets: [(checking, .debitCard, 55), (card, .creditCard, 25), (cash, .cash, 5),
                                       (storeCard, .storeCard, 5), (savings, .bankTransfer, 10)])

        // A few pending and unreconciled entries, a check with a number, and a receipt.
        if let pending = tx(card, day(-1), "Bookshop on Elm", "books-media", -34.20, method: .creditCard, state: .pending) {
            pending.memo = "Birthday gift"
        }
        tx(checking, day(-2), "City Water Dept", "utilities", -48.60, method: .check, state: .unreconciled)?.checkNumber = "1042"
        if let withReceipt = tx(checking, day(-4), "Hardware Depot", "home-improvement", -86.35, method: .debitCard) {
            withReceipt.receiptData = receiptPDF(store: "Hardware Depot", lines: [("Paint, 1 gal", 38.99), ("Brushes", 14.50), ("Tape", 6.25), ("Tax", 26.61)], total: 86.35)
        }
        tx(card, day(-3), "Trail Shoes Co", "clothing", -128.00, method: .creditCard)?.noReceipt = true
        // The store card is close to its limit.
        tx(storeCard, day(-20), "Home Store", "furniture-appliances", -210, method: .storeCard)

        // Bills.
        func bill(_ name: String, _ amount: Decimal, _ frequency: BillFrequency, dueIn offset: Int, key: String?,
                  important: Bool = false, remind: Int = 3, note: String = "") -> Bill {
            // The first due date sits at the start of the history so there are plenty of past payments.
            let first = cal.date(byAdding: .month, value: -monthsOfHistory, to: day(offset))!
            let made = Bill(name: name, amount: amount, frequency: frequency, dueDate: first, remindDaysBefore: remind,
                            isImportant: important, notes: note)
            made.category = key.flatMap { cat($0) }
            context.insert(made)
            return made
        }
        let phone = bill("Cell Phone", 85, .monthly, dueIn: 3, key: "phone-internet", important: true, note: "Family plan, 3 lines.")
        let internet = bill("Internet", 69.99, .monthly, dueIn: -5, key: "phone-internet")
        let electric = bill("Electric", 96, .monthly, dueIn: 16, key: "utilities")
        let insurance = bill("Auto Insurance", 142, .monthly, dueIn: 9, key: "auto-insurance", important: true)
        let gym = bill("Gym", 39, .monthly, dueIn: -10, key: "fitness")
        let registration = bill("Car Registration", 168, .yearly, dueIn: -12, key: "auto-maintenance", important: true,
                                note: "Renew online. Overdue for the demo.")
        // Past occurrences of each bill were paid from checking. The registration's latest one is left open.
        for item in [phone, internet, electric, insurance, gym, registration] {
            let dates = Bills.dates(of: item, from: item.dueDate, through: today)
            for (index, date) in dates.enumerated() {
                if item === registration && index == dates.count - 1 { continue }
                BillPayment.record(from: checking, debt: nil, bill: item, amount: item.amount, date: date,
                                   state: .reconciled, paymentChoice: .type(.autoPay), in: context)
            }
        }

        // Loan and card due dates make their own bills, and the past months of payments.
        LoanBill.sync(card, dueDate: day(11), in: context)
        LoanBill.sync(storeCard, dueDate: day(21), in: context)
        LoanBill.sync(auto, dueDate: day(6), in: context)
        LoanBill.sync(mortgage, dueDate: day(-2), in: context)
        LoanBill.sync(student, dueDate: day(24), in: context)
        for (loan, amount) in [(auto, Decimal(412)), (mortgage, Decimal(1_640)), (student, Decimal(190))] {
            for back in 1...monthsOfHistory {
                let date = monthDay(back, cal.component(.day, from: loan.loanBill?.dueDate ?? today))
                let paid = BillPayment.record(from: checking, debt: loan, bill: loan.loanBill, amount: amount, date: date,
                                              state: .reconciled, paymentChoice: .type(.bankTransfer), in: context)
                // The bill starts this cycle, so an earlier month's payment isn't one of its due dates: leave it unlinked.
                if let paid, let first = loan.loanBill?.dueDate, date < (cal.date(byAdding: .day, value: -20, to: first) ?? first) {
                    BillLink.unlink(paid)
                }
            }
        }
        // This month's mortgage was paid on time.
        BillPayment.record(from: checking, debt: mortgage, bill: mortgage.loanBill, amount: 1_640, date: day(-2),
                           state: .reconciled, paymentChoice: .type(.bankTransfer), in: context)

        try context.save()

        // The last three weeks are mostly not matched to a statement yet, so reconciliation has something to show.
        var counter = 0
        for item in try context.fetch(FetchDescriptor<Transaction>()) where item.date >= day(-21) && !item.isTransfer && item.status == .reconciled {
            counter += 1
            if counter % 3 == 0 { item.state = .unreconciled }
        }

        // Goals. Most follow an account, so their progress moves on its own as you add transactions. Two don't, and
        // one is already reached.
        func owed(_ account: Account) -> Decimal { max(-account.balance, 0) }
        let emergency = Goal(name: "Emergency Fund", targetAmount: 30_000, startingAmount: 0, targetDate: cal.date(byAdding: .month, value: 14, to: today),
                             symbol: "shield.lefthalf.filled", colorHex: "34C759", notes: "Six months of spending.", account: savings,
                             categoryName: "Emergency Fund")
        let trip = Goal(name: "Japan Trip", targetAmount: 4_000, startingAmount: 0, targetDate: cal.date(byAdding: .month, value: 9, to: today),
                        symbol: "airplane", colorHex: "FF9500", notes: "Flights plus two weeks.", account: tripFund,
                        categoryName: "Vacation & Travel")
        // Counts only what has been added since three months ago.
        let downPayment = Goal(name: "House Down Payment", targetAmount: 40_000, startingAmount: max(downFund.balance(asOf: day(-90)), 0),
                         targetDate: cal.date(byAdding: .year, value: 3, to: today), symbol: "house", colorHex: "AF52DE",
                         account: downFund, categoryName: "Home Down Payment")
        let cardStart = owed(card) + 900
        let payoffCard = Goal(name: "Pay Off Sapphire Card", targetAmount: cardStart, startingAmount: cardStart,
                              targetDate: cal.date(byAdding: .month, value: 8, to: today), symbol: "creditcard", colorHex: "FF2D55",
                              account: card, kind: .payoff, goalBalance: 0, categoryName: "Credit Card")
        let studentStart = owed(student) + 2_200
        let payoffStudent = Goal(name: "Student Loan Gone", targetAmount: studentStart, startingAmount: studentStart,
                                 targetDate: cal.date(byAdding: .year, value: 4, to: today), symbol: "graduationcap", colorHex: "5AC8FA",
                                 account: student, kind: .payoff, goalBalance: 0, categoryName: "Student Loan")
        let wedding = Goal(name: "Anniversary Gift", targetAmount: 1_200, startingAmount: 150, targetDate: cal.date(byAdding: .month, value: 5, to: today),
                           symbol: "heart", colorHex: "FF2D55", notes: "Added by hand, no account.", categoryName: "Holidays & Gifts")
        let laptop = Goal(name: "New Laptop", targetAmount: 1_500, startingAmount: 0, targetDate: cal.date(byAdding: .month, value: -1, to: today),
                          symbol: "laptopcomputer", colorHex: "007AFF", categoryName: "Gadgets & Tech")
        for goal in [emergency, trip, downPayment, payoffCard, payoffStudent, wedding, laptop] { context.insert(goal) }

        // Repeating transactions: one that has come due (so it makes a pending entry), one coming up, a deposit and a reminder.
        let calendar = Calendar.current
        func inDays(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: today)) ?? today }
        let streaming = RecurringTransaction(payee: "Streamly Family Plan", account: checking, category: cat("subscriptions"), amount: -22.99,
                                             frequency: .monthly, startDate: inDays(-2))
        streaming.paymentTypeRaw = PaymentType.debitCard.rawValue
        let sideGig = RecurringTransaction(payee: "Side Gig Retainer", account: checking, category: cat("freelance-income"), amount: 250,
                                           frequency: .everyTwoWeeks, startDate: inDays(5))
        sideGig.paymentTypeRaw = PaymentType.bankTransfer.rawValue
        let taxReserve = RecurringTransaction(payee: "Quarterly Tax Reserve", account: savings, category: nil, amount: -500,
                                              frequency: .everyThreeMonths, startDate: inDays(-1))
        taxReserve.autoEnter = false
        for rule in [streaming, sideGig, taxReserve] { context.insert(rule) }
        // The two paydays each month are repeating income, and this month's paycheques already belong to them.
        let paychecks = ((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).filter { $0.payee == "Acme Corp Payroll" }
        for dayOfMonth in [1, 15] {
            let start = monthDay(0, dayOfMonth)
            let pay = RecurringTransaction(payee: "Acme Corp Payroll", account: checking, category: cat("paycheck"), amount: 4_500,
                                           frequency: .monthly, startDate: start)
            pay.paymentTypeRaw = PaymentType.directDeposit.rawValue
            context.insert(pay)
            if start <= today { pay.nextDate = cal.date(byAdding: .month, value: 1, to: start) ?? start }
            for entry in paychecks where cal.isDate(entry.date, inSameDayAs: start) { entry.recurring = pay }
        }
        Recurring.run(in: context)
        for back in 0...2 {
            context.insert(GoalContribution(goal: wedding, amount: 140, date: monthDay(back, 6), note: "Monthly set aside"))
        }
        for (index, amount) in [500, 500, 500].enumerated() {
            context.insert(GoalContribution(goal: laptop, amount: Decimal(amount), date: monthDay(index + 2, 10), note: "Saved up"))
        }

        try context.save()
        GoalArchiver.archiveReached(in: context)
        try context.save()

        // Things new since the early builds, so they have something to show: a primary checking account (a setting on this Mac) and a
        // few reminders for the Reminders widget.
        let primary = ((try? context.fetch(FetchDescriptor<Account>())) ?? []).live
            .filter { $0.type == .checking }
            .sorted { $0.name < $1.name }
            .first
        PrimaryChecking.set(primary, in: context)
        MainActor.assumeIsolated {
            if CustomReminders.shared.items.isEmpty {
                CustomReminders.shared.items = CustomReminder.presets.prefix(3).map(\.reminder)
            }
        }
        NotificationCenter.default.post(name: .piggybankDataLoaded, object: nil)
    }

    // MARK: Volume

    private struct Purchase {
        let payee: String
        let key: String
        let low: Int      // cents
        let high: Int     // cents
    }

    private static let everydayPool: [Purchase] = [
        Purchase(payee: "Fresh Market", key: "groceries", low: 1_800, high: 9_500),
        Purchase(payee: "Corner Grocery", key: "groceries", low: 600, high: 3_200),
        Purchase(payee: "Green Basket", key: "groceries", low: 2_500, high: 11_000),
        Purchase(payee: "Bean There Coffee", key: "custom-coffee-runs", low: 350, high: 950),
        Purchase(payee: "Taco Corner", key: "dining-out", low: 900, high: 2_400),
        Purchase(payee: "Luigi's Pizza", key: "dining-out", low: 1_400, high: 4_200),
        Purchase(payee: "Blue Door Cafe", key: "dining-out", low: 800, high: 2_800),
        Purchase(payee: "Harvest Kitchen", key: "dining-out", low: 1_800, high: 5_500),
        Purchase(payee: "Speedy Fuel", key: "gas-fuel", low: 2_800, high: 5_800),
        Purchase(payee: "Maple Outfitters", key: "shopping", low: 1_500, high: 9_000),
        Purchase(payee: "Cinema 8", key: "entertainment", low: 1_200, high: 3_600),
        Purchase(payee: "Paw Pals Vet", key: "pets", low: 1_500, high: 8_000),
        Purchase(payee: "Bookshop on Elm", key: "books-media", low: 900, high: 3_400),
        Purchase(payee: "Trail Shoes Co", key: "clothing", low: 2_500, high: 12_000),
        Purchase(payee: "Hardware Depot", key: "home-improvement", low: 700, high: 14_000),
        Purchase(payee: "Corner Barber", key: "salon-barber", low: 2_200, high: 3_500),
    ]

    /// Adds `everydayPurchasesPerDay` small purchases for each day back to the start of the history, spread over the
    /// accounts in `targets` by weight. Repeatable: the same data every time.
    private static func addEverydayPurchases(today: Date, context: ModelContext, categories: [Category],
                                             targets: [(account: Account, method: PaymentType, weight: Int)]) {
        let cal = Calendar.current
        let start = cal.date(byAdding: .month, value: -monthsOfHistory, to: today)!
        let days = cal.dateComponents([.day], from: start, to: today).day ?? 0
        let totalWeight = targets.reduce(0) { $0 + $1.weight }
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let byKey = Dictionary(uniqueKeysWithValues: categories.compactMap { c in c.systemKey.map { ($0, c) } })
        var lastForPayee: [String: (Category?, Decimal)] = [:]

        for offset in 0...days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            for _ in 0..<everydayPurchasesPerDay {
                let pick = everydayPool[next(everydayPool.count)]
                let raw = pick.low + next(pick.high - pick.low + 1)
                let amount = -(Decimal(raw) / 100)
                var roll = next(totalWeight)
                var target = targets[0]
                for candidate in targets {
                    if roll < candidate.weight { target = candidate; break }
                    roll -= candidate.weight
                }
                let category = byKey[pick.key]
                let made = Transaction(account: target.account, date: date, payee: pick.payee, category: category, memo: "",
                                       amount: amount, paymentType: target.method)
                made.state = offset < 3 ? .pending : .reconciled
                context.insert(made)
                lastForPayee[pick.payee] = (category, amount)
            }
        }
        // Remember each payee once, not once per purchase.
        for (name, last) in lastForPayee {
            PayeeMemory.record(name: name, category: last.0, amount: last.1, in: context)
        }
    }

    // MARK: Attachments

    /// A one-page PDF receipt.
    private static func receiptPDF(store: String, lines: [(String, Double)], total: Double) -> Data? {
        let page = VStack(alignment: .leading, spacing: 8) {
            Text(store.uppercased()).font(.system(size: 16, weight: .bold, design: .monospaced))
            Text("Receipt 4821").font(.system(size: 10, design: .monospaced))
            Spacer().frame(height: 12)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.0)
                    Spacer()
                    Text(String(format: "%.2f", line.1))
                }
                .font(.system(size: 12, design: .monospaced))
            }
            Divider()
            HStack {
                Text("TOTAL")
                Spacer()
                Text(String(format: "%.2f", total))
            }
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            Spacer()
            Text("Thank you!").font(.system(size: 11, design: .monospaced))
        }
        .foregroundStyle(.black)
        .padding(24)
        .frame(width: 320, height: 420, alignment: .topLeading)
        .background(Color.white)

        let renderer = ImageRenderer(content: page)
        let data = NSMutableData()
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return data.length > 0 ? data as Data : nil
    }
}
#endif
