#if DEBUG
import SwiftUI
import SwiftData

/// Piggybank ▸ Testing… on the Mac. Fills the app with test data, wipes it,
/// or brings your own data back.
/// Debug builds only. Every change saves a copy of what was there first.
struct TestingWindow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var working = false
    @State private var message: String?
    @State private var confirming: Action?

    private enum Action: Identifiable {
        case load, wipe, restore
        var id: Self { self }

        var title: String {
            switch self {
            case .load: "Fill with test data?"
            case .wipe: "Wipe everything?"
            case .restore: "Bring back your data?"
            }
        }

        var detail: String {
            switch self {
            case .load: "Everything currently in the app is replaced with made-up accounts, transactions, bills and goals. A copy of what's there now is saved first."
            case .wipe: "Every account, transaction, bill, goal, custom category and payment method is removed. Cash on Hand and the built-in categories stay. A copy of what's there now is saved first."
            case .restore: "Replaces what's in the app with the copy saved before test data was last loaded or wiped."
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Testing").font(.title2.bold())
                Text("Debug builds only. This isn't in the version that ships.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                row("Fill with Test Data", "Made-up accounts, four months of transactions, bills, goals, holdings and a receipt, so every screen has something to show.", .load)
                row("Wipe Everything", "Empties the app. Cash on Hand and built-in categories stay.", .wipe)
                row("Bring Back My Data", TestData.hasSavedCopy
                    ? "Restores the copy saved before test data was last loaded or wiped."
                    : "Nothing saved yet. A copy is saved the first time you fill or wipe.", .restore)
                    .disabled(!TestData.hasSavedCopy)
            }

            if let message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 520, height: 380)
        .disabled(working)
        .confirmationDialog(confirming?.title ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { action in
            Button(action == .restore ? "Restore" : (action == .wipe ? "Wipe" : "Fill"), role: action == .wipe ? .destructive : nil) { run(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.detail)
        }
    }

    private func row(_ title: String, _ detail: String, _ action: Action) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button(title) { confirming = action }
                .frame(width: 190, alignment: .leading)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func run(_ action: Action) {
        working = true
        message = nil
        // Leave account pages first, so nothing is showing something about to be deleted.
        DataDeletion.afterLeavingAccountPages {
            do {
                switch action {
                case .load:
                    try TestData.saveCopy(of: modelContext)
                    try TestData.load(into: modelContext)
                    message = "Test data loaded."
                case .wipe:
                    try TestData.saveCopy(of: modelContext)
                    try TestData.wipe(in: modelContext)
                    message = "Everything wiped."
                case .restore:
                    try TestData.restoreSavedCopy(into: modelContext)
                    message = "Your data is back."
                }
                modelContext.saveNow()
            } catch {
                modelContext.rollback()
                message = "That didn't work: \(error.localizedDescription)"
            }
            working = false
        }
    }
}
#endif
