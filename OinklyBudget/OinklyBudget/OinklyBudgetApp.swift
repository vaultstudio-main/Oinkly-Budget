import SwiftUI
import SwiftData

@main
struct OinklyBudgetApp: App {
    let container: ModelContainer
    @NSApplicationDelegateAdaptor(OinklyBudgetAppDelegate.self) private var appDelegate
    @AppStorage(BackgroundSettingsSection.showMenuBarKey) private var showInMenuBar = true

    init() {
        let schema = Schema(versionedSchema: OinklyBudgetSchemaV4.self)
        // Kept on this device on purpose. The default would start syncing to iCloud as soon as a container is
        // added to the app, so turn sync on here, deliberately, when the time comes.
        // The first time this version opens the data file, keep a copy of it as it was.
        #if DEBUG
        SharedFolderSelfTest.runIfRequested(localStore: AppStore.localStoreURL(for: schema))
        ClosingCountdown.runTestIfRequested()
        WidgetSnapshotWriter.runCheckIfRequested()
        ArtworkThemePicker.runCheckIfRequested()
        SharedHardeningTest.runIfRequested(localStore: AppStore.localStoreURL(for: schema))
        SharedTimingTest.runIfRequested(localStore: AppStore.localStoreURL(for: schema))
        #endif
        let configuration: ModelConfiguration
        if ScreenshotMode.isOn {
            // Taking screenshots: a throwaway data file, so no real data is shown or changed.
            configuration = ModelConfiguration(schema: schema, url: ScreenshotMode.storeURL, cloudKitDatabase: .none)
        } else {
        StoreSafetyCopy.makeIfNeeded(localStore: AppStore.localStoreURL(for: schema))
        #if DEBUG
        SharedDataSession.enableFromLaunchArgumentIfRequested(localStore: AppStore.localStoreURL(for: schema))
        #endif
        // With sharing on, the app opens a private working copy of the shared data instead of this Mac's own data. If
        // another login has it open, a waiting screen is shown and nothing is opened until it is free.
        switch SharedDataSession.shared.prepareAtLaunch() {
        case .shared(let workingStore):
            configuration = ModelConfiguration(schema: schema, url: workingStore, cloudKitDatabase: .none)
        case .waiting:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        case .local:
            // `groupContainer: .none` keeps the data file where 1.0 put it, in the app's own folder. Without it, the App Group
            // that the widgets need would move the default data file to the group folder, and an update would open empty.
            configuration = ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
        }
        }
        if SharedDataSession.shared.decision == nil && !ScreenshotMode.isOn { StoreReset.performIfRequested(for: configuration) }
        do {
            container = try ModelContainer(for: schema, migrationPlan: OinklyBudgetMigrationPlan.self, configurations: configuration)
        } catch {
            // Keep going with throwaway storage so the boot window can explain what went wrong.
            // The main window never opens in this state.
            StartupState.databaseError = error
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        // Anything the upgrade or the repeating transactions change at launch has to reach the shared data too.
        let launchSaves = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { SharedDataSession.shared.noteSaved() }
        }
        SchemaUpgrade.run(in: container.mainContext)
        // Repeating transactions that came due while the app was closed.
        Recurring.run(in: container.mainContext)
        NotificationCenter.default.removeObserver(launchSaves)
        OinklyBudgetAppDelegate.container = container
        BalanceCache.install()
        LedgerIndex.shared.start(container: container)
        #if DEBUG
        PermissionSpike.runFromLaunchArgumentsIfRequested()
        ScreenshotMode.startIfRequested(container: container)
        #endif
    }

    var body: some Scene {
        // The boot window is its own scene, shown once at launch. It opens the main window when the checks pass.
        Window("Starting Oinkly Budget", id: "boot") {
            BootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        WindowGroup("Oinkly Budget", id: "main") {
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

        Window("About Oinkly Budget", id: "about") {
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

        Window("Oinkly Budget Help", id: "help") {
            HelpWindow()
                .appAppearance()
        }
        .defaultSize(width: 1100, height: 780)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Release Notes", id: "release-notes") {
            ReleaseNotesWindow()
                .appAppearance()
        }
        .defaultSize(width: 860, height: 780)
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
