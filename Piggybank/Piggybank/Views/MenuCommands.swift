import SwiftUI
import SwiftData

extension FocusedValues {
    /// The account whose register is showing in the front window, if any.
    @Entry var selectedAccountID: PersistentIdentifier?
}

/// What the menu bar can do in the register that is showing: edit or look at the selected transaction, make it
/// recurring, and import, export or print the account. Set by the register; nil when no register is open.
struct RegisterActions {
    var hasSelection: Bool
    var canMakeRecurring: Bool
    var canImport: Bool
    var edit: () -> Void
    var details: () -> Void
    var makeRecurring: () -> Void
    var importStatement: () -> Void
    var exportCSV: () -> Void
    var printPDF: () -> Void
}

extension FocusedValues {
    @Entry var registerActions: RegisterActions?
}

/// What the New Transaction window opens with.
struct NewTransactionRequest: Codable, Hashable {
    var accountID: PersistentIdentifier?
}

/// Which transaction the read-only detail window shows.
struct TransactionDetailRequest: Codable, Hashable {
    var id: PersistentIdentifier
}

/// File > New Transaction opens its own window. Accounts are created in Settings.
struct FileNewCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.selectedAccountID) private var selectedAccountID
    @FocusedValue(\.registerActions) private var register

    private static let pages: [(title: String, key: String)] = [
        ("Summary", "summary"), ("Transactions", "transactions"), ("Reports", "reports"), ("Liabilities", "liabilities"),
        ("Investments", "investments"), ("Bills & Recurring", "bills"), ("Planning", "planning"), ("Budgets", "budgets"),
    ]

    var body: some Commands {
        // The side panel always stays open, so there is no Hide Sidebar command.
        CommandGroup(replacing: .sidebar) {}

        CommandGroup(replacing: .appInfo) {
            Button("About OinklyBudget") {
                openWindow(id: "about")
            }
        }

        CommandGroup(replacing: .help) {
            Button("OinklyBudget Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])

            Button("Release Notes") {
                openWindow(id: "release-notes")
            }
        }

        // Debug builds only: OinklyBudget ▸ Testing opens the window that fills the app with test data or wipes it.
        #if DEBUG
        CommandGroup(after: .appInfo) {
            Button("Testing") { openWindow(id: "testing") }
        }
        #endif

        CommandGroup(replacing: .newItem) {
            Button("New Transaction…") {
                openWindow(id: "new-transaction", value: NewTransactionRequest(accountID: selectedAccountID))
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Credit Card Charge…") {
                openWindow(id: "credit-card-charge", value: NewTransactionRequest(accountID: selectedAccountID))
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("ATM Withdrawal…") {
                openWindow(id: "atm-withdrawal")
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button("Update Investment Price…") {
                openWindow(id: "update-price", value: NewTransactionRequest(accountID: selectedAccountID))
            }
            .keyboardShortcut("u", modifiers: [.command, .option])

            Button("Transfer…") {
                openWindow(id: "transfer")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("Pay a Bill…") {
                openWindow(id: "bill-pay")
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        // The account on screen: bring statements in and send them out.
        CommandGroup(replacing: .importExport) {
            Button("Import Statement…") { register?.importStatement() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(register?.canImport != true)
            Button("Export CSV…") { register?.exportCSV() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(register == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print PDF…") { register?.printPDF() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(register == nil)
        }

        // Everything the right-click menu does on a transaction, for the keyboard and VoiceOver.
        CommandMenu("Transaction") {
            Button("Edit Transaction…") { register?.edit() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(register?.hasSelection != true)
            Button("View Details") { register?.details() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(register?.hasSelection != true)
            Button("Make Recurring…") { register?.makeRecurring() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(register?.canMakeRecurring != true)
        }

        // Pages, in the order of the side panel.
        CommandMenu("Go") {
            ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
                Button(page.title) {
                    NotificationCenter.default.post(name: .piggybankOpenPage, object: nil, userInfo: ["page": page.key])
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

