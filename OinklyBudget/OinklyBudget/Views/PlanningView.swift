import SwiftUI
import SwiftData

/// Planning: the savings goals you are working toward. Loans live in Bills & Recurring and Liabilities, and paying a debt down faster is
/// the Debt War Plan in the Planning War Room. The button opens the New Goal window. The Summary's Goals card opens this page.
struct PlanningView: View {
    /// Opens Planning, from anywhere in the app.
    static func open() {
        NotificationCenter.default.post(name: .piggybankOpenPage, object: nil, userInfo: ["page": "planning"])
    }

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeader("Planning") {
                HStack {
                    Text("Savings goals, and how far along each one is.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
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
            GoalsView(kind: .save)
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
