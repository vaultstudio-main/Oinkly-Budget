import SwiftUI
import SwiftData

/// Planning: a place for the things you do ahead of time. Goals is the first section; more can sit beside it.
struct PlanningView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case goals = "Goals"
        var id: Self { self }
    }

    @State private var tab = Tab.goals
    @State private var isAddingGoal = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Planning").font(.largeTitle.bold())
                Spacer()
                if Tab.allCases.count > 1 {
                    Picker("Planning", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
                Button { isAddingGoal = true } label: {
                    Label("New Goal", systemImage: "plus")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            switch tab {
            case .goals: GoalsView(isAdding: $isAddingGoal)
            }
        }
        .background(Theme.background)
    }
}
