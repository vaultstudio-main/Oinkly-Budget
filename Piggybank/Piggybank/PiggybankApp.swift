import SwiftUI
import SwiftData

@main
struct PiggybankApp: App {
    let container: ModelContainer
    @NSApplicationDelegateAdaptor(PiggybankAppDelegate.self) private var appDelegate
    @AppStorage(BackgroundSettingsSection.showMenuBarKey) private var showInMenuBar = true

    init() {
        let schema = Schema(versionedSchema: PiggybankSchemaV2.self)
        // Kept on this device on purpose. The default would start syncing to iCloud as soon as a container is
        // added to the app, so turn sync on here, deliberately, when the time comes.
        // With encryption on, the app runs on a working copy opened from the encrypted vault instead of this Mac's
        // own data file. See VaultSession.
        // The first time this version opens the data file, keep a copy of it as it was.
        StoreSafetyCopy.makeIfNeeded(localStore: VaultSession.localStoreURL(for: schema))
        let configuration: ModelConfiguration
        switch VaultSession.shared.prepareAtLaunch(localStore: VaultSession.localStoreURL(for: schema)) {
        case .local:
            // `groupContainer: .none` keeps the data file where 1.0 put it, in the app's own folder. Without it, the App Group
            // that the widgets need would move the default data file to the group folder, and an update would open empty.
            configuration = ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
        case .open(let workingStore):
            configuration = ModelConfiguration(schema: schema, url: workingStore, cloudKitDatabase: .none)
        case .quit:
            exit(0)
        }
        StoreReset.performIfRequested(for: configuration)
        do {
            container = try ModelContainer(for: schema, migrationPlan: PiggybankMigrationPlan.self, configurations: configuration)
        } catch {
            // Keep going with throwaway storage so the boot window can explain what went wrong.
            // The main window never opens in this state.
            StartupState.databaseError = error
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        SchemaUpgrade.run(in: container.mainContext)
        PiggybankAppDelegate.container = container
        BalanceCache.install()
        LedgerIndex.shared.start(container: container)
    }

    var body: some Scene {
        // The boot window is its own scene, shown once at launch. It opens the main window when the checks pass.
        Window("Starting OinklyBudget", id: "boot") {
            BootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        WindowGroup("OinklyBudget", id: "main") {
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

        WindowGroup("Transaction", id: "transaction-detail", for: TransactionDetailRequest.self) { $request in
            TransactionDetailWindow(id: request?.id)
                .savesChangesImmediately()
                .appAppearance()
        }
        .modelContainer(container)
        .defaultSize(width: 520, height: 640)
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

        Window("About OinklyBudget", id: "about") {
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

        Window("OinklyBudget Help", id: "help") {
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

        // Adds OinklyBudget ▸ Settings… (⌘,) to the app menu.
        Settings {
            MacSettingsView()
                .savesChangesImmediately()
                .modelContainer(container)
                .appAppearance()
        }
    }
}
