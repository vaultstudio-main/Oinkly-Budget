import SwiftUI
import SwiftData

/// Mac gets the dense Quicken-style layout; iPhone and iPad get the card-based one.
/// On iPhone and iPad a splash screen covers the first moments after launch; the Mac has its own boot window.
/// If there are no accounts yet, the account setup screen is shown instead of an empty app.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var allAccounts: [Account]
    @State private var hasChecked = false
    @State private var isSettingUp = false
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if !hasChecked {
                Color.clear
            } else if isSettingUp {
                AccountSetupView { withAnimation { isSettingUp = false } }
            } else {
                #if os(iOS)
                PhoneRootView()
                #else
                MacRootView()
                #endif
            }

            #if os(iOS)
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
                    .onTapGesture { dismissSplash() }
            }
            #endif
        }
        .savesChangesImmediately()
        .appAppearance()
        #if os(macOS)
        .opensMaximized()
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await BillNotifier.refresh(in: modelContext) } }
        }
        // Erasing or deleting the last account brings the setup screen back.
        .onChange(of: allAccounts.live.addedByUser.count) { _, count in
            if hasChecked && count == 0 { withAnimation { isSettingUp = true } }
        }
        .task {
            #if os(iOS)
            try? await Task.sleep(for: .seconds(2))
            #endif
            // Cash on Hand is always there, so only accounts you added count toward "set up".
            let accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
            isSettingUp = accounts.filter(\.isLive).addedByUser.isEmpty
            hasChecked = true
            GoalMigration.detachAccounts(in: modelContext)
            await BillNotifier.refresh(in: modelContext)
            GoalArchiver.archiveReached(in: modelContext)
            dismissSplash()
        }
    }

    private func dismissSplash() {
        withAnimation(.easeOut(duration: 0.5)) { showSplash = false }
    }
}
