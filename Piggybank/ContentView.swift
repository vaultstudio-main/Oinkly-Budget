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
        #if os(macOS)
        .preferredColorScheme(.dark)
        #endif
        // Erasing or deleting the last account brings the setup screen back.
        .onChange(of: allAccounts.live.count) { _, count in
            if hasChecked && count == 0 { withAnimation { isSettingUp = true } }
        }
        .task {
            #if os(iOS)
            try? await Task.sleep(for: .seconds(2))
            #endif
            let count = (try? modelContext.fetchCount(FetchDescriptor<Account>())) ?? 0
            isSettingUp = count == 0
            hasChecked = true
            dismissSplash()
        }
    }

    private func dismissSplash() {
        withAnimation(.easeOut(duration: 0.5)) { showSplash = false }
    }
}
