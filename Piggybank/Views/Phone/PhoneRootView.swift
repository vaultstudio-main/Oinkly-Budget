#if os(iOS)
import SwiftUI

/// The same app on iPhone and iPad. On a wide iPad screen it stays a centered, phone-width column
/// instead of stretching every card and button edge to edge.
struct PhoneRootView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            TabView {
                Tab("Home", systemImage: "house.fill") { HomeView() }
                Tab("Budgets", systemImage: "chart.pie.fill") { BudgetsView() }
                Tab("Accounts", systemImage: "wallet.pass.fill") { AccountsView() }
                Tab("Reports", systemImage: "chart.bar.xaxis") {
                    NavigationStack { ReportsView().navigationTitle("Reports") }
                }
                Tab("Settings", systemImage: "gearshape.fill") { PhoneSettingsView() }
            }
            .frame(maxWidth: 640)
            .environment(\.horizontalSizeClass, .compact)
        }
    }
}
#endif
