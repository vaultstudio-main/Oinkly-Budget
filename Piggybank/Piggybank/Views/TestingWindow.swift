#if DEBUG
import SwiftUI
import SwiftData

/// PigVault ▸ Testing… on the Mac. Fills the app with test data or wipes it.
/// Debug builds only, for testing: it replaces whatever is in the app, with no way back.
struct TestingWindow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var working = false
    @State private var message: String?
    @State private var confirming: Action?

    private enum Action: Identifiable {
        case load, wipe
        var id: Self { self }

        var title: String {
            switch self {
            case .load: "Fill with test data?"
            case .wipe: "Wipe everything?"
            }
        }

        var detail: String {
            switch self {
            case .load: "Everything currently in the app is replaced with made-up accounts, transactions, bills and goals."
            case .wipe: "Every account, transaction, bill, goal, custom category and payment method is removed. Cash on Hand and the built-in categories stay."
            }
        }
    }

    /// One account type for each drawn picture, plus the bill picture, so they can all be checked at a glance.
    private static let artworkSamples: [(title: String, type: AccountType?)] = [
        ("Bank", .checking), ("Savings", .savings), ("Wallet", .cash), ("Card", .creditCard), ("Medical", .healthSavings),
        ("House", .mortgage), ("Car", .autoLoan), ("Boat", .vehicleLoan), ("Graduation", .studentLoan), ("Loan", .personalLoan),
        ("Business", .businessLoan), ("Chart", .brokerage), ("Retirement", .retirement401k), ("Crypto", .crypto),
        ("Valuables", .valuables), ("Other asset", .asset), ("Bill", nil),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Testing").font(.title2.bold())
                Text("Debug builds only. This isn't in the version that ships.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                row("Fill with Test Data", "Made-up accounts, over two years of transactions (thousands of them), bills, goals, holdings and a receipt, so every screen has something to show.", .load)
                row("Wipe Everything", "Deletes the whole database, however big, and quits. Open the app again and it starts empty.", .wipe)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default pictures").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(Self.artworkSamples, id: \.title) { sample in
                        VStack(spacing: 3) {
                            Group {
                                if let type = sample.type { AccountArtwork(type: type) } else { AccountArtwork() }
                            }
                            .aspectRatio(3 / 2, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(sample.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }

            if let message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 560, height: 600)
        .disabled(working)
        .confirmationDialog(confirming?.title ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { action in
            Button(action == .wipe ? "Wipe" : "Fill", role: action == .wipe ? .destructive : nil) { run(action) }
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
                    try TestData.load(into: modelContext)
                    message = "Test data loaded."
                case .wipe:
                    // Removing the database files is instant; deleting 30,000 rows one by one is not.
                    StoreReset.requestAndQuit()
                    message = "Starting over. Open the app again."
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
