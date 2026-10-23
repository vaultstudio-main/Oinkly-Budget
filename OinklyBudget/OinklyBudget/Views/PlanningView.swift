import SwiftUI
import SwiftData

/// Planning, in two tabs: Goals, the savings goals you are working toward, and Loan Payoff Goals, the goals that pay a loan or card
/// down. Loans themselves live in Bills & Recurring and Liabilities. Each tab's button opens its own New Goal window. The Summary's
/// Goals card opens the Goals tab.
struct PlanningView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case goals = "Goals"
        case payoff = "Loan Payoff Goals"
        var id: Self { self }
    }

    /// The tab to show, kept in preferences so the Summary can choose it before it opens this page.
    static let tabKey = "planningTab"

    /// Opens Planning on the given tab, from anywhere in the app.
    static func open(_ tab: Tab) {
        UserDefaults.standard.set(tab.rawValue, forKey: tabKey)
        NotificationCenter.default.post(name: .piggybankOpenPage, object: nil, userInfo: ["page": "planning"])
    }

    @AppStorage(PlanningView.tabKey) private var tabName = Tab.goals.rawValue
    @Environment(\.openWindow) private var openWindow

    private var current: Tab { Tab(rawValue: tabName) ?? .goals }
    private var tabBinding: Binding<Tab> { Binding(get: { current }, set: { tabName = $0.rawValue }) }

    var body: some View {
        VStack(spacing: 0) {
            FolderTabbedHeader(title: "Planning", tabs: Tab.allCases, selection: tabBinding, label: { $0.rawValue }) {
                EmptyView()
            } centre: { EmptyView() } trailing: {
                Button {
                    openWindow(id: "new-goal", value: NewGoalRequest(payoff: current == .payoff))
                } label: {
                    Label(current == .goals ? "New Savings Goal" : "New Loan Payoff Goal", systemImage: "plus")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(current == .goals ? "Open a window to set up something to save toward" : "Open a window to set up paying a loan or card down")
            }

            switch current {
            case .goals: GoalsView(kind: .save)
            case .payoff: GoalsView(kind: .payoff)
            }
        }
        .background(Theme.background)
    }
}

/// The window that makes a new goal: a savings goal, or the payoff of a loan or card, chosen by the button that opened it.
struct NewGoalWindow: View {
    let payoff: Bool

    var body: some View {
        GoalEditView(goal: nil, newKind: payoff ? .payoff : .save, locksKind: true)
    }
}
