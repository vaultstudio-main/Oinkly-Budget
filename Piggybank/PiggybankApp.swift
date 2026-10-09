import SwiftUI
import SwiftData

@main
struct PiggybankApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Account.self, Category.self, Transaction.self, Payee.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            #if os(macOS)
            // Keep going with throwaway storage so the boot window can explain what went wrong.
            // The main window never opens in this state.
            StartupState.databaseError = error
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            #else
            fatalError("Could not create ModelContainer: \(error)")
            #endif
        }
        #if os(iOS)
        // On the Mac the boot window does this (and reports it).
        Category.ensureSystemCategories(in: container.mainContext)
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // The boot window is its own scene, shown once at launch. It opens the main window when the checks pass.
        Window("Piggybank", id: "boot") {
            BootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        #endif

        WindowGroup("Piggybank Financial", id: "main") {
            ContentView()
        }
        .modelContainer(container)
        .defaultSize(width: 1200, height: 800)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            FileNewCommands()
            SidebarCommands()
        }
        #endif

        #if os(macOS)
        WindowGroup("New Transaction", id: "new-transaction", for: NewTransactionRequest.self) { $request in
            NewTransactionWindow(accountID: request?.accountID)
                .savesChangesImmediately()
                .preferredColorScheme(.dark)
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
                .preferredColorScheme(.dark)
        }
        #endif
    }
}
