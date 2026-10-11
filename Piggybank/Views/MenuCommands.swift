import SwiftUI
import SwiftData

extension FocusedValues {
    /// The account whose register is showing in the front window, if any.
    @Entry var selectedAccountID: PersistentIdentifier?
}

/// What the New Transaction window opens with.
struct NewTransactionRequest: Codable, Hashable {
    var accountID: PersistentIdentifier?
}

/// File > New Transaction opens its own window. Accounts are created in Settings.
struct FileNewCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.selectedAccountID) private var selectedAccountID

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Piggybank Financial") {
                openWindow(id: "about")
            }
        }

        CommandGroup(replacing: .help) {
            Button("Piggybank Financial Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])

            Button("Release Notes") {
                openWindow(id: "release-notes")
            }
        }

        #if DEBUG
        // In the Piggybank menu, below About. Debug builds only.
        CommandGroup(after: .appInfo) {
            Button("Testing…") {
                openWindow(id: "testing")
            }
        }
        #endif

        CommandGroup(replacing: .newItem) {
            Button("New Transaction…") {
                openWindow(id: "new-transaction", value: NewTransactionRequest(accountID: selectedAccountID))
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Cash Transaction…") {
                openWindow(id: "cash-transaction")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

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
    }
}

