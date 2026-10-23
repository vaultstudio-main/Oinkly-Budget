import SwiftUI

/// The window behind the Budgets page's Set Budgets button: the same budget list as Settings ▸ Categories, in a roomy
/// window of its own that can be resized. Settings keeps its copy.
struct BudgetSetupWindow: View {
    static let id = "set-budgets"

    var body: some View {
        CategoriesSettingsView()
            .frame(minWidth: 560, minHeight: 480)
    }
}
