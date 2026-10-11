import SwiftUI
import SwiftData

@main
struct PiggybankApp: App {
    let container: ModelContainer
    @NSApplicationDelegateAdaptor(PiggybankAppDelegate.self) private var appDelegate
    @AppStorage(BackgroundSettingsSection.showMenuBarKey) private var showInMenuBar = true

    init() {
        let schema = Schema([Account.self, Category.self, Transaction.self, Payee.self, Holding.self, HoldingEvent.self, Bill.self, Goal.self, GoalContribution.self, CustomPaymentMethod.self])
        do {
            // Kept on this device on purpose. The default would start syncing to iCloud as soon as a container is
            // added to the app, so turn sync on here, deliberately, when the time comes.
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        } catch {
            // Keep going with throwaway storage so the boot window can explain what went wrong.
            // The main window never opens in this state.
            StartupState.databaseError = error
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        PiggybankAppDelegate.container = container
    }

    var body: some Scene {
        // The boot window is its own scene, shown once at launch. It opens the main window when the checks pass.
        Window("Starting Piggybank Financial", id: "boot") {
            BootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        WindowGroup("Piggybank Financial", id: "main") {
            ContentView()
        }
        .modelContainer(container)
        .defaultSize(width: 1200, height: 800)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            FileNewCommands()
        }

        WindowGroup("New Transaction", id: "new-transaction", for: NewTransactionRequest.self) { $request in
            NewTransactionWindow(accountID: request?.accountID)
                .savesChangesImmediately()
                .appAppearance()
        }
        .modelContainer(container)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        WindowGroup("New Credit Card Charge", id: "credit-card-charge", for: NewTransactionRequest.self) { $request in
            CreditCardChargeWindow(accountID: request?.accountID)
                .savesChangesImmediately()
                .appAppearance()
        }
        .modelContainer(container)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        WindowGroup("Update Investment Price", id: "update-price", for: NewTransactionRequest.self) { $request in
            UpdatePriceWindow(accountID: request?.accountID)
                .savesChangesImmediately()
                .appAppearance()
        }
        .modelContainer(container)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("About Piggybank Financial", id: "about") {
            AboutWindow()
                .appAppearance()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        #if DEBUG
        Window("Testing", id: "testing") {
            TestingWindow()
                .savesChangesImmediately()
                .appAppearance()
        }
        .modelContainer(container)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif

        Window("Piggybank Financial Help", id: "help") {
            HelpWindow()
                .appAppearance()
        }
        .defaultSize(width: 820, height: 560)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Release Notes", id: "release-notes") {
            ReleaseNotesWindow()
                .appAppearance()
        }
        .defaultSize(width: 620, height: 600)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        // Upcoming bills, always one click away, even with no window open.
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarBills()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)

        WindowGroup("New Cash Transaction", id: "cash-transaction") {
            CashTransactionView()
                .savesChangesImmediately()
                .appAppearance()
        }
        .modelContainer(container)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        WindowGroup("ATM Withdrawal", id: "atm-withdrawal") {
            AtmWithdrawalView()
                .savesChangesImmediately()
                .appAppearance()
        }
        .modelContainer(container)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        WindowGroup("Transfer", id: "transfer") {
            TransferWindow()
                .savesChangesImmediately()
                .appAppearance()
        }
        .modelContainer(container)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        WindowGroup("Pay a Bill", id: "bill-pay") {
            BillPayWindow()
                .savesChangesImmediately()
                .appAppearance()
        }
        .modelContainer(container)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        // Adds Piggybank ▸ Settings… (⌘,) to the app menu.
        Settings {
            MacSettingsView()
                .savesChangesImmediately()
                .modelContainer(container)
                .appAppearance()
        }
    }
}
