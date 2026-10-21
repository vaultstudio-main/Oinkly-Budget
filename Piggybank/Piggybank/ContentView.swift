import SwiftUI
import SwiftData

/// The Mac app's root: the Quicken-style layout, after the boot window.
/// If there are no accounts yet, the account setup screen is shown instead of an empty app.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var allAccounts: [Account]
    @State private var hasChecked = false
    @State private var isSettingUp = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // While the shared data can't be opened, this window can only say why. It can show up even when the boot window
        // is shown too (macOS brings back the windows of a session that ended unexpectedly), and it must never show an
        // empty app that someone could start adding data to.
        if let decision = SharedDataSession.shared.decision {
            SharedWaitingView(decision: decision)
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            if !hasChecked {
                Color.clear
            } else if isSettingUp {
                AccountSetupView { withAnimation { isSettingUp = false } }
            } else {
                MacRootView()
            }

        }
        .savesChangesImmediately()
        .appAppearance()
        .opensMaximized()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await BillNotifier.refresh(in: modelContext) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .piggybankDataLoaded)) { _ in
            isSettingUp = false
        }
        // Erasing or deleting the last account brings the setup screen back.
        .onChange(of: allAccounts.live.addedByUser.count) { _, count in
            if hasChecked && count == 0 { withAnimation { isSettingUp = true } }
        }
        .task {
            // Cash on Hand is always there, so only accounts you added count toward "set up".
            let accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
            isSettingUp = accounts.filter(\.isLive).addedByUser.isEmpty
            hasChecked = true
            await BillNotifier.refresh(in: modelContext)
            GoalArchiver.archiveReached(in: modelContext)
        }
    }

}
