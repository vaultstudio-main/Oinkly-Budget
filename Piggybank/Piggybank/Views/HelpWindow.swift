import SwiftUI
import AppKit

/// Everything the Help window says. Add or edit a topic here; the window picks it up.
///
/// Text lines: start with "## " for a subheading and "• " for a bullet. Anything else is a paragraph.
/// Screenshots: each topic can list shots by asset name. Add an image set with that exact name to
/// Assets.xcassets and it appears under the text; a shot with no image yet simply doesn't show.
/// The list of shots to take is in help-screenshots.md, in the docs folder next to the project folder.
enum HelpContent {
    struct Shot: Hashable {
        /// Asset catalog name, such as "Help-summary".
        let asset: String
        let caption: String
    }

    struct Topic: Identifiable, Hashable {
        let title: String
        let symbol: String
        let lines: [String]
        var shots: [Shot] = []
        var id: String { title }
    }

    struct Group: Identifiable {
        let title: String
        let topics: [Topic]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Start Here", topics: [
            Topic(title: "Welcome", symbol: "hand.wave", lines: [
                "OinklyBudget keeps your accounts, bills, budgets, goals and investments on your own Mac. There is no account to create and nothing is sent anywhere.",
                "## Your first few minutes",
                "• Add your accounts. The setup screen walks you through it, and Manage Accounts at the bottom of the side panel lets you add more any time.",
                "• Record what happens: File ▸ New Transaction for everyday money in and out, New Credit Card Charge for cards, ATM Withdrawal for cash.",
                "• Add your bills on the Bills page so they show on the calendar and remind you.",
                "• Open Summary for the big picture and Reports to see where your money goes.",
                "## Help any time",
                "Press ⇧⌘/ or choose Help ▸ OinklyBudget Help. Search this window with the field at the top of the list.",
            ], shots: [Shot(asset: "Help-welcome", caption: "The Summary page, with the side panel on the left.")]),

            Topic(title: "Finding Your Way", symbol: "sidebar.left", lines: [
                "The side panel stays open on the left. It has two parts.",
                "## Overview",
                "• Summary: your net worth, this month's income and spending, and quick cards for liabilities, investments, goals and recent transactions.",
                "• Transactions: every account's transactions together, with a search field.",
                "• Reports: income and spending by period and by category.",
                "• Liabilities: everything you owe, how much is paid off, and your leverage.",
                "• Investments: value, growth and contributions across your investment accounts.",
                "• Bills: the calendar, what's coming up, and Add a Bill.",
                "• Planning: your goals.",
                "## Accounts",
                "Cash on Hand sits at the top by itself. The rest are grouped in folders by type: Checking & Savings, Credit Cards, Mortgages & Loans, Investments and Assets. Click an account to open its register. The side panel shows each account's name and type, never its balance, so nothing private is on show until you open it.",
                "Manage Accounts is pinned at the bottom of the panel.",
            ], shots: [Shot(asset: "Help-sidebar", caption: "The side panel: Overview, Cash on Hand and account folders.")]),
        ]),

        Group(title: "Accounts", topics: [
            Topic(title: "Adding & Managing Accounts", symbol: "building.columns", lines: [
                "Choose Manage Accounts at the bottom of the side panel (or OinklyBudget ▸ Settings ▸ Accounts) to add, edit or delete an account.",
                "## What each kind keeps",
                "• Checking, savings and the like: institution, account number, routing number and an opening balance.",
                "• Credit cards: card number, credit limit, APR, minimum payment, payment due date and the balance you owe.",
                "• Loans and mortgages: what it's for, amount borrowed, monthly payment, interest rate, start and maturity dates, and what you owe now.",
                "• Auto accounts can be a loan or a lease, with a photo and VIN.",
                "• Investments: holdings with shares and prices.",
                "• Assets (house, car, valuables): a value and a photo.",
                "## Good to know",
                "• Account names can be up to 30 characters.",
                "• Account and card numbers show masked (•••• 1234) until you press Show.",
                "• Deleting an account also deletes its transactions and can't be undone. Cash on Hand can't be deleted.",
                "• You can edit a single account from its page with Edit Details, or right-click it in the side panel.",
            ], shots: [Shot(asset: "Help-manage-accounts", caption: "Settings ▸ Accounts, with Add Account at the top.")]),

            Topic(title: "Cash on Hand", symbol: "dollarsign.circle", lines: [
                "Cash on Hand is built in. It is for the cash you carry, so it has no bank details and no opening balance. It starts at $0.00 and is filled by ATM withdrawals.",
                "## ATM Withdrawal",
                "Choose File ▸ ATM Withdrawal… (⇧⌘A). Pick the checking or savings account the cash comes from, the amount and the date. OinklyBudget takes it out of that account and adds it to Cash on Hand as one linked pair, so it never counts as income or spending.",
                "• Every withdrawal reads the same: payee ATM Withdrawal, category ATM, method Cash, memo Cash, no receipt, always reconciled.",
                "• Those fields are locked on purpose, because that's what cash from an ATM always is.",
                "## Spending and receiving cash",
                "Choose File ▸ New Cash Transaction… (⇧⌘N). It only ever affects Cash on Hand, and the method is always Cash. Pick Spent or Received, then the amount, date, payee, category and memo, and attach a receipt if you have one.",
                "• Cash on Hand isn't offered in New Transaction. Use New Cash Transaction for cash you spend or receive, and ATM Withdrawal for cash you take out of a bank account.",
            ], shots: [Shot(asset: "Help-atm-withdrawal", caption: "The ATM Withdrawal window.")]),

            Topic(title: "Credit Cards", symbol: "creditcard", lines: [
                "Credit cards keep a card number (up to 19 digits), a credit limit, an APR, a minimum payment and a payment due date.",
                "## Charging a card",
                "Choose File ▸ New Credit Card Charge… (⌥⌘N). Pick the card, enter the amount, payee and category. Available credit shows as you type.",
                "• A charge that would reach or pass the credit limit is refused with \"Exceeds Credit Limit\".",
                "• The method is always Credit Card, and you can attach a receipt.",
                "• Credit cards don't appear in New Transaction. Charges go through this form.",
                "## Paying a card",
                "Use Pay a Bill and choose the card under Loans & Cards. The payment comes off the card's balance and out of the account you pay from. A payment on a card never has a receipt.",
                "## Due date",
                "Turn on Set a payment due date when you edit the card, and it appears on the Bills page every month for the minimum payment.",
            ], shots: [Shot(asset: "Help-card-charge", caption: "New Credit Card Charge, showing available credit."),
                       Shot(asset: "Help-card-details", caption: "A card's page with limit, available credit and APR.")]),

            Topic(title: "Loans & Mortgages", symbol: "banknote", lines: [
                "Loans keep what you borrowed, the interest rate, the monthly payment, a start date and a maturity date. OinklyBudget estimates the payments left until maturity.",
                "• Turn on Set a payment due date and the loan adds its own bill to the Bills page, repeating monthly.",
                "• Mark it paid on Bills, or pay it with Pay a Bill, and the loan's page shows this month as Paid.",
                "• A loan's photo is used as the picture on its bill.",
                "• Loans don't appear in New Transaction. They only take payments, through Pay a Bill.",
                "## Auto lease vs loan",
                "On an Auto account choose Loan or Lease. A lease shows the leasing company and lease end date instead of an interest rate.",
            ], shots: [Shot(asset: "Help-loan-details", caption: "A loan's page: progress, payment due and payments left.")]),
        ]),

        Group(title: "Everyday Money", topics: [
            Topic(title: "Transactions & Registers", symbol: "list.bullet.rectangle", lines: [
                "Each account has a register: every transaction with a running balance, one month at a time. The month picker at the top moves between months. Loans show everything at once.",
                "## Adding a transaction",
                "Choose File ▸ New Transaction… (⌘N). Pick Payment for money out or Deposit for money in, then the account, amount, date, payee, category, payment method and status. The categories offered match the direction you chose.",
                "• Payee suggestions appear as you type, and fill in the usual category and amount.",
                "• New Transaction offers checking, savings and similar accounts. Loans, credit cards and Cash on Hand have their own forms.",
                "## Taking a closer look",
                "Double-click a transaction, in a register or on the Transactions page, to open it in its own window with everything about it, including the receipt at a larger size. Nothing can change from there. Close it when you're done, or press Edit… to change it. You can keep several open side by side.",
                "## Changing a transaction",
                "The register is read-only so nothing changes by accident. Right-click a transaction and choose Edit Transaction… to change its date, payee, category, method, memo or amount, then Save.",
                "• The Status column is a click menu: Pending (not final at the bank), Unreconciled (not yet matched to a statement) or Reconciled (matched).",
                "• Right-click ▸ Delete removes a transaction. Deleting one half of a payment or transfer removes the other half too.",
                "## Locked items",
                "Some things can't be changed, because they're always the same:",
                "• Payments to loans and cards show the category Payment, transfers show Transfer, and ATM withdrawals show ATM.",
                "• A bill paid with Pay a Bill is locked to the bill's category (or Payment when the bill has none).",
                "• The method on a card is always Credit Card, and on Cash on Hand always Cash.",
                "• The amount of a payment or transfer can't be edited, since it's shared with the other account. Delete it and enter it again.",
            ], shots: [Shot(asset: "Help-register", caption: "An account register with the Receipt column."),
                       Shot(asset: "Help-edit-transaction", caption: "Right-click ▸ Edit Transaction…")]),

            Topic(title: "Receipts & PDF Bills", symbol: "doc.text.viewfinder", lines: [
                "Checking accounts, credit card charges and Cash on Hand can keep a receipt or a PDF of the bill with the transaction.",
                "• In the register, the Receipt column shows Add Receipt, View Receipt or No Receipt.",
                "• Add a photo, or attach a PDF bill. PDFs open in a scrollable viewer.",
                "• Tick No receipt for this transaction when there isn't one, so the register stops asking.",
                "• Pay a Bill has a Receipt or Bill section, so you can attach the PDF as you pay.",
                "• ATM withdrawals and payments to cards never have a receipt.",
            ], shots: [Shot(asset: "Help-receipt", caption: "A receipt open from the register.")]),

            Topic(title: "Transfers", symbol: "arrow.left.arrow.right", lines: [
                "Move money between your own accounts with File ▸ Transfer… (⇧⌘T). A transfer is one event with two linked entries, so it is never income or spending and doesn't change your reports.",
                "• Credit cards and loans can't be the source or destination. To pay one, use Pay a Bill.",
                "• Moving cash out of a bank account into Cash on Hand is usually an ATM Withdrawal.",
                "• Deleting one half of a transfer deletes the other.",
            ]),
        ]),

        Group(title: "Bills", topics: [
            Topic(title: "The Bills Page", symbol: "calendar", lines: [
                "Bills shows a calendar, what's due this month, and an Important · Next 30 Days list in the side area.",
                "## Adding a bill",
                "Press Add a Bill at the bottom of the side area (or the + beside the calendar). Give it a name, amount, how often it repeats (once, weekly, every two weeks, monthly, every three months, yearly) and the first due date.",
                "• Category: choose where the bill's payments appear in your reports, such as Phone & Internet.",
                "• Important: marks it so it's listed first and raises a priority alert as it gets close.",
                "• Reminders: pick how many days before it's due. Reminders arrive at 9 AM.",
                "• Photo: attach a picture of the bill. A loan's bill uses the loan's photo.",
                "• Notes: anything else you want to remember.",
                "## Ticking bills off",
                "Click the circle beside a bill to mark that date paid, and again to undo. To record the actual payment, use Pay a Bill instead.",
            ], shots: [Shot(asset: "Help-bills", caption: "The Bills page with the calendar and Add a Bill."),
                       Shot(asset: "Help-new-bill", caption: "The New Bill form.")]),

            Topic(title: "Paying a Bill", symbol: "creditcard.fill", lines: [
                "Choose File ▸ Pay a Bill… (⇧⌘B). One payment does everything at once.",
                "## What to fill in",
                "• From: one of your own money accounts, such as checking, savings or Cash on Hand. Investment accounts are never used to pay bills.",
                "• To: a bill, or a loan or credit card.",
                "• Amount: filled in from the bill or the loan's monthly payment, and you can change it.",
                "• Date, payment method and status. Status starts as Reconciled, because a bill you pay has usually already gone through. Choose Pending if it hasn't.",
                "• Memo starts as \"Monthly payment\" and you can change it.",
                "• Receipt or Bill: attach the PDF or a photo, or tick No receipt.",
                "## What it does",
                "• Takes the money out of the account you chose.",
                "• For a loan or card, takes the same amount off what you owe, and records the payment on both sides with the same method.",
                "• Ticks the bill off for the due date it settles.",
                "• Files a bill under its category so it shows in Reports and budgets.",
                "## Deleting a payment",
                "If you delete a payment that settled a bill, that due date goes back to unpaid.",
            ], shots: [Shot(asset: "Help-pay-bill", caption: "The Pay a Bill window.")]),
        ]),

        Group(title: "Planning & Reports", topics: [
            Topic(title: "Categories & Budgets", symbol: "tag", lines: [
                "Categories are split into Expenses and Income. Built-in categories are the same everywhere and can't be renamed or deleted.",
                "• Set a monthly budget on an expense category in Settings ▸ Categories, and it appears on Summary and Budgets.",
                "• Add Custom Category lets you create your own, as an Expense or as Income. You can rename and delete your own.",
                "• Payment methods work the same way: add your own in Settings ▸ Payment Methods.",
                "• A transaction only offers categories that fit its direction: expense categories for money out, income categories for money in.",
            ], shots: [Shot(asset: "Help-categories", caption: "Settings ▸ Categories with budgets.")]),

            Topic(title: "Summary & Reports", symbol: "chart.bar.xaxis", lines: [
                "## Summary",
                "Your net worth over time, this month's income and spending, and cards for liabilities, loan progress, goals and your last 15 transactions. A payment or transfer shows once, on the paying side.",
                "## Reports",
                "Income and spending by month, quarter, six months or year, with spending broken down by category and compared with the previous period.",
                "• Payments to loans and cards, transfers and ATM withdrawals aren't counted as spending.",
                "• Reports, Liabilities and Investments show every card with \"No data\" until there's something to show.",
                "## Liabilities & Investments",
                "Liabilities lists everything you owe, how much of each loan is paid off, and your leverage. Investments shows value, growth, contributions and where it's held.",
            ], shots: [Shot(asset: "Help-reports", caption: "Reports with spending by category.")]),

            Topic(title: "Goals", symbol: "target", lines: [
                "Planning ▸ Goals tracks saving up for something or paying a debt down. Goals are independent of your accounts.",
                "• Pick Save up or Pay off a debt, choose from the list of categories, and set a target amount and date.",
                "• Press Make Progress on a goal's card to add what you set aside or paid.",
                "• The card shows whether you're on track, how much is needed per month, and a projected date.",
                "• A goal moves to the archive when you reach it. You can edit or delete a goal at any time.",
                "• Summary shows your goals as a read-only card.",
            ], shots: [Shot(asset: "Help-goals", caption: "The Goals page.")]),

            Topic(title: "Investments", symbol: "chart.line.uptrend.xyaxis", lines: [
                "Investment accounts (401(k), IRA, brokerage, 529, crypto and more) hold positions instead of categories.",
                "• Add holdings in the account's Holdings panel with shares and price.",
                "• Keep prices current with File ▸ Update Investment Price… (⌥⌘U).",
                "• Record deposits, withdrawals, gains and fees with a Type instead of a category.",
                "• The Investments page shows value, growth and contributions for the period.",
            ]),
        ]),

        Group(title: "Data & Settings", topics: [
            Topic(title: "Backup & Restore", symbol: "externaldrive", lines: [
                "Settings ▸ Data & Backup saves everything to one .pig file and restores it.",
                "## What's in a backup",
                "Accounts, transactions, receipts and photos, bills, goals, holdings, budgets, your custom categories and payment methods, and your preferences.",
                "## Restoring",
                "• Choose Restore from Backup…, or double-click a .pig file, or use Restore from a Backup on the setup screen.",
                "• Restoring replaces everything currently in the app.",
                "## Bank files and PDF statements",
                "Open an account and choose Import… to add a bank's CSV file, with a preview first and Undo if it's wrong. Choose Export CSV… to save its transactions as a spreadsheet. The printer button saves a PDF statement for a month, a year or any dates; open the PDF and print it from Preview.",
                "## Erase All Data",
                "Settings ▸ Data & Backup ▸ Erase All Data deletes your accounts, transactions, bills, goals, custom categories and payment methods, then quits. Open the app again to start fresh. Built-in categories and their budgets stay.",
                "Take a backup before anything you can't undo.",
            ], shots: [Shot(asset: "Help-backup", caption: "Settings ▸ Data & Backup.")]),

            Topic(title: "Menu Bar & Reminders", symbol: "menubar.rectangle", lines: [
                "The pig in the menu bar shows your next bills at a glance, with a number when something is due within three days.",
                "• Click it for priority bills, what's coming up in the next 14 days, and a total. Click a circle to mark a bill paid.",
                "• Closing the main window leaves the app running so the pig stays. Click the app in the Dock to open the window again, and press ⌘Q to quit.",
                "• Settings ▸ General ▸ Background turns the menu bar item on or off and opens the app when you log in.",
                "• Bill reminders are notifications sent the number of days you chose before a bill is due. Turn them off in Settings ▸ Reminders.",
                "## Your own reminders",
                "Settings ▸ Reminders ▸ Add a Reminder sets up a notification to do something in the app, such as reviewing your budget on the 1st, checking bills every Monday or backing up each month.",
                "• Choose a ready-made one or write your own, with a message, how often (every day, week, month or once) and the time.",
                "• Choose a page to open when you click the notification.",
                "• Switch a reminder off without deleting it, or delete it when you no longer need it.",
            ], shots: [Shot(asset: "Help-menu-bar", caption: "The menu bar pop-up.")]),

            Topic(title: "Settings", symbol: "gearshape", lines: [
                "Open Settings with OinklyBudget ▸ Settings… (⌘,).",
                "• General: menu bar and login options, appearance (light, dark or system) and currency.",
                "• Reminders: bill reminders and your own custom reminders.",
                "• Accounts: add, edit and delete accounts.",
                "• Categories: budgets and custom categories.",
                "• Payment Methods: your own methods.",
                "• Data & Backup: your counts, backups and restore, Erase All Data, and the version.",
            ]),
        ]),

        Group(title: "Reference", topics: [
            Topic(title: "Keyboard Shortcuts", symbol: "keyboard", lines: [
                "• ⌘N  New Transaction",
                "• ⇧⌘N  New Cash Transaction",
                "• ⌥⌘N  New Credit Card Charge",
                "• ⇧⌘A  ATM Withdrawal",
                "• ⇧⌘T  Transfer",
                "• ⇧⌘B  Pay a Bill",
                "• ⌥⌘U  Update Investment Price",
                "• ⌘,  Settings",
                "• ⇧⌘/  This help",
                "• ⌘Q  Quit",
            ]),

            Topic(title: "Why Can't I Change That?", symbol: "lock", lines: [
                "A few things are locked so the numbers stay right. Here's why.",
                "• Category on a payment, transfer or ATM withdrawal: they aren't spending, so they have a fixed label.",
                "• Category on a bill payment: it follows the bill. Change it by editing the bill.",
                "• Method on a card or Cash on Hand: every charge on a card is a card charge, and every entry in Cash on Hand is cash.",
                "• Amount of a payment or transfer: it's shared with the other account. Delete it and enter it again.",
                "• Status of an ATM withdrawal: cash comes out at once, so it's always reconciled.",
                "• Receipts on payments to cards and on ATM withdrawals: there isn't one.",
                "• Type of Cash on Hand, and deleting it: it's built in.",
                "• Date in the register: change it from Edit Transaction… so a stray click can't move it.",
            ]),

            Topic(title: "Your Data & Privacy", symbol: "lock.shield", lines: [
                "Everything stays on your Mac. OinklyBudget has no account, no sign-in and no online sync.",
                "• Account and card numbers show masked until you press Show.",
                "• The side panel never shows balances. They appear once you open an account.",
                "• Backups are plain files you keep. Store them somewhere safe, since anyone with a .pig file can read it.",
            ]),
        ]),
    ]

    static var topics: [Topic] { groups.flatMap(\.topics) }
}

/// Help ▸ OinklyBudget Help. Topics on the left, the text and screenshots on the right.
struct HelpWindow: View {
    @State private var selection: HelpContent.Topic? = HelpContent.topics.first
    @State private var search = ""

    private var groups: [HelpContent.Group] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return HelpContent.groups }
        return HelpContent.groups.compactMap { group in
            let matches = group.topics.filter {
                $0.title.lowercased().contains(query) || $0.lines.contains { $0.lowercased().contains(query) }
            }
            return matches.isEmpty ? nil : HelpContent.Group(title: group.title, topics: matches)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.topics) { topic in
                            Label(topic.title, systemImage: topic.symbol).tag(topic)
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search Help")
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            if let topic = selection ?? groups.first?.topics.first {
                ScrollView {
                    TopicView(topic: topic)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
                .id(topic.id)
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
    }
}

private struct TopicView: View {
    let topic: HelpContent.Topic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: topic.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(topic.title).font(.largeTitle.bold())
            }
            .padding(.bottom, 4)

            ForEach(Array(topic.lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }

            ForEach(topic.shots, id: \.asset) { shot in
                if let image = NSImage(named: shot.asset) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 640)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        Text(shot.caption).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("## ") {
            Text(String(line.dropFirst(3)))
                .font(.title3.weight(.semibold))
                .padding(.top, 10)
        } else if line.hasPrefix("• ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(String(line.dropFirst(2)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textSelection(.enabled)
            .padding(.leading, 6)
        } else {
            Text(line)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
