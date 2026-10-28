import SwiftUI
import SwiftData

/// Planning, in two tabs: Goals, the savings goals you are working toward, and Archive, the old goals that were reached. Loans are not
/// here: they live in Bills & Recurring and Liabilities, and paying a debt down faster is the Debt War Plan in the Planning War Room.
/// The button opens the New Goal window. The Summary's Goals card opens this page.
struct PlanningView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case goals = "Goals"
        case archive = "Archive"
        var id: Self { self }
    }

    /// Opens Planning, from anywhere in the app.
    static func open() {
        NotificationCenter.default.post(name: .piggybankOpenPage, object: nil, userInfo: ["page": "planning"])
    }

    @State private var tab = Tab.goals
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            FolderTabbedHeader(title: "Planning", tabs: Tab.allCases, selection: $tab, label: { $0.rawValue }) {
                Text(tab == .goals ? "Savings goals, and how far along each one is." : "Savings goals you have reached.")
                    .font(.callout).foregroundStyle(.secondary)
            } centre: { EmptyView() } trailing: {
                if tab == .goals {
                    Button {
                        openWindow(id: "new-goal", value: NewGoalRequest())
                    } label: {
                        Label("New Savings Goal", systemImage: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Open a window to set up something to save toward")
                }
            }
            GoalsView(kind: .save, page: tab == .goals ? .goals : .archive)
        }
        .background(Theme.background)
    }
}

/// The window that makes a new savings goal.
struct NewGoalWindow: View {
    var body: some View {
        GoalEditView(goal: nil, newKind: .save, locksKind: true)
    }
}
