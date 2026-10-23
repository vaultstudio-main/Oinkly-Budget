import SwiftUI
import SwiftData

/// Planning, in two tabs: Goals, the things you save up for or pay down, and Loans, each loan with how much is paid off and when it
/// will be done. The Summary's Goals and Loans cards open the matching tab.
struct PlanningView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case goals = "Goals"
        case loans = "Loans"
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
    @State private var isAddingGoal = false

    private var current: Tab { Tab(rawValue: tabName) ?? .goals }
    private var tabBinding: Binding<Tab> { Binding(get: { current }, set: { tabName = $0.rawValue }) }

    var body: some View {
        VStack(spacing: 0) {
            FolderTabbedHeader(title: "Planning", tabs: Tab.allCases, selection: tabBinding, label: { $0.rawValue }) {
                EmptyView()
            } centre: { EmptyView() } trailing: {
                if current == .goals {
                    Button { isAddingGoal = true } label: {
                        Label("New Goal", systemImage: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            switch current {
            case .goals: GoalsView(isAdding: $isAddingGoal)
            case .loans: LoansView()
            }
        }
        .background(Theme.background)
    }
}
