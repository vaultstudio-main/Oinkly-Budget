import Foundation
import SwiftData

/// The one built-in category list. Every platform and every launch converges on exactly this set.
extension Category {
    struct Definition {
        let key: String
        let name: String
        let color: String
        let symbol: String
        let budget: Decimal
        let isIncome: Bool
    }

    private static func expense(_ key: String, _ name: String, _ color: String, _ symbol: String, _ budget: Decimal) -> Definition {
        Definition(key: key, name: name, color: color, symbol: symbol, budget: budget, isIncome: false)
    }

    private static func income(_ key: String, _ name: String, _ color: String, _ symbol: String) -> Definition {
        Definition(key: key, name: name, color: color, symbol: symbol, budget: 0, isIncome: true)
    }

    static let definitions: [Definition] = [
        // Housing
        expense("housing", "Housing", "AF52DE", "house", 1500),
        expense("property-tax", "Property Tax", "AF52DE", "doc.text", 200),
        expense("hoa-fees", "HOA & Condo Fees", "AF52DE", "building.2", 0),
        expense("utilities", "Utilities", "FFCC00", "bolt", 250),
        expense("phone-internet", "Phone & Internet", "5AC8FA", "wifi", 130),
        expense("home-maintenance", "Home Maintenance", "8E8E93", "hammer", 100),
        expense("home-improvement", "Home Improvement", "8E8E93", "paintbrush", 100),
        expense("furniture-appliances", "Furniture & Appliances", "8E8E93", "sofa", 75),
        expense("lawn-garden", "Lawn & Garden", "34C759", "leaf", 40),
        expense("household-supplies", "Household Supplies", "5AC8FA", "sparkles", 50),
        // Food
        expense("groceries", "Groceries", "34C759", "cart", 450),
        expense("dining-out", "Dining Out", "FF9500", "fork.knife", 200),
        expense("coffee-snacks", "Coffee & Snacks", "FF9500", "cup.and.saucer", 40),
        expense("alcohol-bars", "Alcohol & Bars", "FF9500", "wineglass", 60),
        // Transportation
        expense("gas-fuel", "Gas & Fuel", "007AFF", "fuelpump", 150),
        expense("auto-maintenance", "Auto & Maintenance", "8E8E93", "wrench.and.screwdriver", 100),
        expense("auto-payment", "Auto Loan & Lease", "007AFF", "car", 350),
        expense("parking-tolls", "Parking & Tolls", "007AFF", "parkingsign", 40),
        expense("public-transit", "Public Transit", "5AC8FA", "tram", 60),
        expense("rideshare-taxi", "Rideshare & Taxi", "5AC8FA", "location", 50),
        // Insurance
        expense("insurance", "Insurance", "007AFF", "checkmark.shield", 300),
        expense("auto-insurance", "Auto Insurance", "007AFF", "shield", 0),
        expense("health-insurance", "Health Insurance", "FF2D55", "heart.text.square", 0),
        expense("home-insurance", "Home & Renters Insurance", "AF52DE", "umbrella", 0),
        expense("life-insurance", "Life Insurance", "8E8E93", "person.crop.circle", 0),
        // Health & wellness
        expense("healthcare", "Healthcare", "FF2D55", "cross.case", 150),
        expense("dental", "Dental", "FF2D55", "mouth", 40),
        expense("vision", "Vision & Eye Care", "FF2D55", "eyeglasses", 20),
        expense("pharmacy", "Pharmacy", "FF2D55", "pills", 40),
        expense("mental-health", "Mental Health", "FF2D55", "brain.head.profile", 0),
        expense("fitness", "Fitness", "34C759", "figure.run", 50),
        // Personal
        expense("personal-care", "Personal Care", "FF2D55", "scissors", 60),
        expense("salon-barber", "Hair & Salon", "FF2D55", "comb", 40),
        expense("clothing", "Clothing", "AF52DE", "tshirt", 100),
        expense("shopping", "Shopping", "FF9500", "bag", 150),
        expense("electronics", "Electronics & Software", "007AFF", "desktopcomputer", 60),
        // Fun & travel
        expense("entertainment", "Entertainment", "FF2D55", "film", 100),
        expense("events-concerts", "Concerts & Events", "FF2D55", "ticket", 50),
        expense("hobbies", "Hobbies", "AF52DE", "paintpalette", 50),
        expense("books-media", "Books & Media", "007AFF", "books.vertical", 20),
        expense("games", "Games", "34C759", "gamecontroller", 30),
        expense("subscriptions", "Subscriptions", "AF52DE", "play.rectangle", 50),
        expense("travel", "Travel", "5AC8FA", "airplane", 150),
        expense("hotels-lodging", "Hotels & Lodging", "5AC8FA", "bed.double", 0),
        // Family, education & pets
        expense("kids-family", "Kids & Family", "FFCC00", "person.2", 150),
        expense("childcare", "Childcare", "FFCC00", "figure.and.child.holdinghands", 0),
        expense("kids-activities", "Kids Activities", "FFCC00", "soccerball", 50),
        expense("education", "Education", "007AFF", "book", 100),
        expense("student-loans", "Student Loans", "007AFF", "graduationcap", 0),
        expense("pets", "Pets", "FF9500", "pawprint", 80),
        expense("pet-care-vet", "Pet Care & Vet", "FF9500", "stethoscope", 40),
        // Giving
        expense("gifts-donations", "Gifts & Donations", "FF2D55", "gift", 75),
        expense("charity", "Charity", "FF2D55", "heart", 50),
        // Financial & other
        expense("fees-charges", "Fees & Charges", "8E8E93", "creditcard", 20),
        expense("bank-fees", "Bank Fees", "8E8E93", "building.columns", 10),
        expense("interest-paid", "Interest Paid", "8E8E93", "percent", 0),
        expense("investment-fees", "Investment Fees", "8E8E93", "minus.circle", 0),
        expense("taxes-income", "Income Taxes", "8E8E93", "doc.plaintext", 0),
        expense("taxes-other", "Other Taxes", "8E8E93", "seal", 0),
        expense("professional-services", "Professional Services", "8E8E93", "briefcase", 0),
        expense("postage-shipping", "Postage & Shipping", "8E8E93", "shippingbox", 20),
        expense("memberships-dues", "Memberships & Dues", "AF52DE", "person.crop.rectangle", 20),
        expense("cash-withdrawals", "Cash & ATM", "34C759", "banknote", 100),
        expense("business-expenses", "Business Expenses", "8E8E93", "briefcase.fill", 0),
        expense("miscellaneous", "Miscellaneous", "8E8E93", "ellipsis.circle", 100),
        // Income
        income("paycheck", "Paycheck", "34C759", "briefcase"),
        income("bonus", "Bonus", "FFCC00", "star"),
        income("freelance-income", "Freelance & Side Income", "34C759", "laptopcomputer"),
        income("business-income", "Business Income", "34C759", "storefront"),
        income("rental-income", "Rental Income", "5AC8FA", "key"),
        income("interest-dividends", "Interest & Dividends", "5AC8FA", "percent"),
        income("investment-gains", "Investment Gains", "007AFF", "chart.line.uptrend.xyaxis"),
        income("refunds", "Refunds", "007AFF", "arrow.uturn.backward"),
        income("tax-refund", "Tax Refund", "007AFF", "arrow.uturn.backward.circle"),
        income("reimbursements", "Reimbursements", "5AC8FA", "arrow.triangle.2.circlepath"),
        income("gifts-received", "Gifts Received", "FF2D55", "gift"),
        income("government-benefits", "Government Benefits", "8E8E93", "building.columns"),
        income("pension-retirement", "Pension & Retirement", "AF52DE", "hourglass"),
        income("support-received", "Alimony & Child Support", "FFCC00", "person.2"),
        income("cashback-rewards", "Cashback & Rewards", "34C759", "star.circle"),
        income("sale-of-items", "Sale of Items", "FF9500", "tag"),
        income("deposit", "Deposit", "34C759", "arrow.down.to.line"),
        income("other-income", "Other Income", "8E8E93", "dollarsign.circle"),
    ]

    /// Names used by the very first version of the category list, and what each became.
    private static let legacyNames = ["Dining": "dining-out", "Transport": "gas-fuel", "Fun": "entertainment"]

    /// Brings the store in line with `definitions`. Safe to run on every launch:
    /// - missing categories are added with their default budget,
    /// - older categories without a key are adopted by name,
    /// - name, icon, color and type are reset to the built-in values (they are not editable),
    /// - duplicates (for example from two devices seeding independently) are merged into one.
    /// A category's budget amount is the only thing left as the user set it.
    @discardableResult
    static func ensureSystemCategories(in context: ModelContext) -> Report {
        var report = Report()
        var byKey: [String: Category] = [:]
        let all = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        for definition in definitions {
            var matches = all.filter { $0.systemKey == definition.key }
            if matches.isEmpty, let legacy = all.first(where: { $0.systemKey == nil && $0.name == definition.name }) {
                legacy.systemKey = definition.key
                matches = [legacy]
                report.adopted += 1
            }

            if let primary = matches.first {
                byKey[definition.key] = primary
                for duplicate in matches.dropFirst() {
                    for transaction in Array(duplicate.transactions) { transaction.category = primary }
                    for part in Array(duplicate.splits) { part.category = primary }
                    for payee in Array(duplicate.payees) { payee.lastCategory = primary }
                    context.delete(duplicate)
                    report.merged += 1
                }
                if primary.name != definition.name || primary.symbol != definition.symbol
                    || primary.colorHex != definition.color || primary.isIncome != definition.isIncome {
                    report.repaired += 1
                }
                primary.name = definition.name
                primary.symbol = definition.symbol
                primary.colorHex = definition.color
                primary.isIncome = definition.isIncome
            } else {
                let created = Category(
                    name: definition.name,
                    colorHex: definition.color,
                    symbol: definition.symbol,
                    monthlyLimit: definition.budget,
                    isIncome: definition.isIncome,
                    systemKey: definition.key
                )
                context.insert(created)
                byKey[definition.key] = created
                report.added += 1
            }
        }

        // Anything left without a key is a leftover from an earlier version. Fold known old names into the
        // built-in category they became, drop empty ones, and never touch a category that still has transactions.
        for stray in all where stray.systemKey == nil {
            if let key = legacyNames[stray.name], let target = byKey[key] {
                for transaction in Array(stray.transactions) { transaction.category = target }
                for part in Array(stray.splits) { part.category = target }
                for payee in Array(stray.payees) { payee.lastCategory = target }
                context.delete(stray)
                report.migrated += 1
            } else if stray.transactions.isEmpty {
                context.delete(stray)
                report.removed += 1
            }
        }
        return report
    }

    /// What `ensureSystemCategories` had to change.
    struct Report {
        var added = 0
        var adopted = 0
        var merged = 0
        var repaired = 0
        var migrated = 0
        var removed = 0

        var changes: Int { added + adopted + merged + repaired + migrated + removed }
    }
}
