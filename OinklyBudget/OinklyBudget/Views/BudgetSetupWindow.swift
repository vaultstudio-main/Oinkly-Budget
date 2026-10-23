import SwiftUI

/// The window behind the Budgets page's Settings button, roomy and resizable, so the page stays open and in view behind it. It
/// holds everything that is set for the page: the month for the Monthly tab, the week for the Weekly tab, and the same budget
/// list as Settings ▸ Categories, where any category can be given a budget, shown or hidden, and made. Settings keeps its copy.
struct BudgetSetupWindow: View {
    static let id = "set-budgets"

    @AppStorage(BudgetsSettings.monthKey) private var monthStamp = 0.0
    @AppStorage(BudgetsSettings.weekKey) private var weekStamp = 0.0

    private var monthBinding: Binding<Date> {
        Binding(get: { BudgetsSettings.month(from: monthStamp) }, set: { monthStamp = $0.timeIntervalSinceReferenceDate })
    }

    private var weekBinding: Binding<Date> {
        Binding(get: { BudgetsSettings.week(from: weekStamp) }, set: { weekStamp = $0.timeIntervalSinceReferenceDate })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Budget Settings").font(.headline)
                SettingsSection(title: "Month", note: "The month the Monthly tab is showing. Each start of the app begins on this month.") {
                    MonthSelector(month: monthBinding, range: BudgetsSettings.monthRange)
                }
                SettingsSection(title: "Week", note: "The week the Weekly tab is showing. Each start of the app begins on this week.") {
                    WeekSelector(week: weekBinding, range: BudgetsSettings.weekRange)
                }
                SettingsSection(title: "Budgets", note: "Click a category to set its budget. The switch shows or hides it on Home, Budgets and the Summary. Add Custom Category makes budgets of your own.") {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()
            CategoriesSettingsView()
        }
        .frame(minWidth: 620, minHeight: 620)
    }
}
