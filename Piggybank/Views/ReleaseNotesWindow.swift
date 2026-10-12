import SwiftUI

/// Everything the Release Notes window says. Add a new release at the top of `releases` when you ship one.
enum ReleaseNotes {
    struct Release: Identifiable {
        let version: String
        let title: String
        let sections: [(heading: String, items: [String])]
        var id: String { version }
    }

    static let releases: [Release] = [
        Release(version: "1.0", title: "First release", sections: [
            ("Why it's different", [
                "Your money stays yours. Everything is kept on your own device, with no account to create and no sign-in.",
                "Paying a bill is one step that does everything: it comes out of your account, comes off what you owe, ticks the bill off, and files under the right category.",
                "Credit limits are real. A charge that would reach a card's limit is stopped before it's saved.",
                "Cash is part of the picture. Cash on Hand fills from ATM withdrawals, so what's in your wallet stays honest.",
                "Mistakes are hard to make. Dates, categories, methods and amounts are changed in one deliberate place, never by a stray click or scroll.",
                "Receipts and bills travel with the transaction: attach a photo or the PDF, or mark it as having none.",
                "Backups are one file. Save everything, including your custom categories and payment methods, and restore it whole.",
            ]),
            ("Accounts", [
                "Checking, savings, cash, credit cards, loans, mortgages, investments and assets, all in one place.",
                "New Cash Transaction records cash you spend or receive, and only affects Cash on Hand. ATM Withdrawal moves cash from a checking or savings account into Cash on Hand. Every withdrawal reads the same: payee ATM Withdrawal, category ATM, method Cash, memo Cash, no receipt, always reconciled.",
                "Cash on Hand is built in and can't be deleted: an account for the money you carry, with no bank details, always cash, with receipts like checking.",
                "Credit cards keep a card number, credit limit, APR, minimum payment and payment due date.",
                "New Credit Card Charge adds debt to a card, and refuses a charge that would reach its credit limit.",
                "New Transaction no longer lists loans or credit cards; loans take payments and cards take charges.",
                "Loans keep the amount borrowed, interest rate, start and maturity dates, and the payments left.",
                "Auto accounts can be a loan or a lease, with a photo and VIN.",
                "Account names are limited to 30 characters.",
            ]),
            ("Transactions", [
                "A register for every account, plus one page with every account's transactions together.",
                "Categories match the direction: expense categories for money out, income categories for money in.",
                "Payment methods, including your own, and a check number for checks.",
                "Pending, Unreconciled and Reconciled statuses.",
                "Receipt photos or PDF bills on checking accounts and credit card charges, or mark a transaction as having no receipt. Card payments never have one.",
            ]),
            ("Bills & Payments", [
                "A Bills page with a calendar, an Important list and a monthly view.",
                "Reminders before each bill is due, plus a priority alert for important bills.",
                "Loans and credit cards with a due date add their own bill.",
                "Pay a Bill records the payment on both sides, with a payment method and status.",
                "Bills can have a category. Paying one with Pay a Bill records it under that category, locked, so it shows in reports; with no category it is locked to Payment.",
                "Deleting a payment made with Pay a Bill marks that bill unpaid again.",
                "Attach the PDF bill or a photo when you pay, or mark it as having no receipt.",
                "Transfers between your own accounts, never touching debts or investments.",
                "Photos on bills, and a loan's photo is used for its bill.",
                "A menu bar item showing your upcoming bills. Closing the window keeps the app running so the item stays.",
            ]),
            ("Planning & Reports", [
                "Goals for saving up or paying off debt, independent of your accounts.",
                "Budgets for expense and income categories, with your own custom categories.",
                "Summary, Reports, Liabilities and Investments pages that show placeholders until there is data.",
                "Top income categories over the last three months.",
            ]),
            ("Around the App", [
                "A side panel with every page and account, and Manage Accounts always at the bottom.",
                "Backups saved as .pig files, with import and export in Settings.",
                "A reminder on the Summary to save a backup once you have two years of history, and a firmer one at three.",
                "Help and these release notes in the Help menu.",
                "Opens at full window size.",
            ]),
        ]),
    ]
}

/// Help ▸ Release Notes. Every release, newest first, as bullet points.
struct ReleaseNotesWindow: View {
    private var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Release Notes").font(.largeTitle.bold())
                    Text("You are running \(currentVersion)").foregroundStyle(.secondary)
                }

                // A look at the app, from the same screenshot the Help uses.
                if let image = NSImage(named: "Help-welcome") {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 560)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }

                ForEach(ReleaseNotes.releases) { release in
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Version \(release.version) · \(release.title)").font(.title2.bold())
                        ForEach(Array(release.sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.heading).font(.headline)
                                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("•")
                                        Text(item).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
