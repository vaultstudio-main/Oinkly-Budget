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

#if os(macOS)
/// File > New Transaction opens its own window. Accounts are created in Settings.
struct FileNewCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.selectedAccountID) private var selectedAccountID

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Transaction…") {
                openWindow(id: "new-transaction", value: NewTransactionRequest(accountID: selectedAccountID))
            }
            .keyboardShortcut("n", modifiers: .command)

        }
    }
}

#endif
