import SwiftUI
import SwiftData

extension FocusedValues {
    /// The account whose register is showing in the front window, if any.
    @Entry var selectedAccountID: PersistentIdentifier?
}

/// What the menu bar can do in the register that is showing: edit or look at the selected transaction, or make it
/// recurring. Set by the register; nil when no register is open.
struct RegisterActions {
    var hasSelection: Bool
    var canMakeRecurring: Bool
    var edit: () -> Void
    var details: () -> Void
    var makeRecurring: () -> Void
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
        ("Summary", "summary"), ("Transactions", "transactions"), ("Reports", "reports"), ("Monthly Outlook", "outlook"), ("Liabilities", "liabilities"),
        ("Investments", "investments"), ("Bills & Recurring", "bills"), ("Planning", "planning"), ("Budgets", "budgets"),
    ]

    var body: some Commands {
        // The side panel always stays open, so there is no Hide Sidebar command.
        CommandGroup(replacing: .sidebar) {}

        // The menu bar is kept small: no Services, Hide, Hide Others or Show All in the app menu, and nothing for Close, Edit,
        // View or Window to hold. Replacing a group with nothing means SwiftUI never makes those rows, so nothing has to be
        // taken out of a menu afterwards.
        CommandGroup(replacing: .systemServices) {}
        CommandGroup(replacing: .appVisibility) {}
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .pasteboard) {}
        CommandGroup(replacing: .textEditing) {}
        CommandGroup(replacing: .textFormatting) {}
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .windowSize) {}
        CommandGroup(replacing: .windowList) {}
        CommandGroup(replacing: .singleWindowList) {}
        CommandGroup(replacing: .windowArrangement) {}

        CommandGroup(replacing: .appInfo) {
            Button("About Oinkly Budget") {
                openWindow(id: "about")
            }
        }

        CommandGroup(replacing: .help) {
            Button("Oinkly Budget Help") {
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
            // Left out of screenshots, so they show only what the app has.
            if !ScreenshotMode.isOn { Button("Testing") { openWindow(id: "testing") } }
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

        // Importing, exporting and printing live on each page's own buttons, so the File menu doesn't repeat them.
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}

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

