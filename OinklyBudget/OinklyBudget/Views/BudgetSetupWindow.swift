import SwiftUI

/// The window behind the Budgets page's Settings button, roomy and resizable, so the page stays open and in view behind it. It
/// follows the tab: on the Monthly tab it offers the month, on the Weekly tab (the cash budgets are often weekly ones) the week,
/// centred under the title. Below is the whole budget list, a tab for each group of categories (Housing, Food, Transport and so on,
/// then Income and your own), where any category can be given a budget, shown or hidden, and made. Settings ▸ Categories keeps its
/// own plain list.
struct BudgetSetupWindow: View {
    static let id = "set-budgets"

    @AppStorage(BudgetsSettings.monthKey) private var monthStamp = 0.0
    @AppStorage(BudgetsSettings.weekKey) private var weekStamp = 0.0
    @AppStorage(BudgetsSettings.tabKey) private var tab = "monthly"

    private var monthBinding: Binding<Date> {
        Binding(get: { BudgetsSettings.month(from: monthStamp) }, set: { monthStamp = $0.timeIntervalSinceReferenceDate })
    }

    private var weekBinding: Binding<Date> {
        Binding(get: { BudgetsSettings.week(from: weekStamp) }, set: { weekStamp = $0.timeIntervalSinceReferenceDate })
    }

    private func centred<Content: View>(_ title: String, note: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
            Text(note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(tab == "weekly" ? "Weekly Budget Settings" : "Monthly Budget Settings").font(.headline)
                if tab == "weekly" {
                    centred("Week", note: "The week the Weekly tab is showing. Each start of the app begins on this week.") {
                        WeekSelector(week: weekBinding, range: BudgetsSettings.weekRange)
                    }
                } else {
                    centred("Month", note: "The month the Monthly tab is showing. Each start of the app begins on this month.") {
                        MonthSelector(month: monthBinding, range: BudgetsSettings.monthRange)
                    }
                }
                Text("Every budget is listed below, whichever tab you are on. Click a category to set its budget, use the switch to show or hide it on Home, Budgets and the Summary, and Add Custom Category to make budgets of your own.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            Divider()
            BudgetTabsView {}
        }
        .frame(minWidth: 1200, minHeight: 640)
    }
}
