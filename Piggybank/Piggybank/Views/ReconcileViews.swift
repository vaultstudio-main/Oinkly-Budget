import SwiftUI
import SwiftData

extension ReconcileState {
    var color: Color {
        switch self {
        case .pending: .yellow
        case .unreconciled: .red
        case .reconciled: Theme.green
        }
    }
}

/// Small colored label for a transaction's state.
struct ReconcileBadge: View {
    let state: ReconcileState
    var showsTitle = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.symbol)
            if showsTitle { Text(state.title).font(.caption) }
        }
        .foregroundStyle(state.color)
        .accessibilityLabel(state.title)
    }
}

/// Click to choose Pending, Unreconciled or Reconciled.
struct ReconcileMenu: View {
    @Bindable var transaction: Transaction
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if transaction.isLive && transaction.isAtmWithdrawal {
            // Cash comes out of the ATM at once, so a withdrawal is always reconciled.
            ReconcileBadge(state: .reconciled)
                .help("ATM withdrawals are always reconciled.")
        } else {
            menu
        }
    }

    private var menu: some View {
        Menu {
            ForEach(ReconcileState.allCases) { state in
                Button {
                    withAnimation(.snappy) {
                        transaction.state = state
                        // Both sides of a transfer share one status.
                        if transaction.isTransfer { Transfers.syncPeer(of: transaction, in: modelContext) }
                        modelContext.saveNow()
                    }
                } label: {
                    Label(state.title, systemImage: transaction.state == state ? "checkmark" : state.symbol)
                }
            }
        } label: {
            ReconcileBadge(state: transaction.state)
        }
        // A plain button style keeps the label's own colour. The borderless menu style paints it grey.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Pending: not final at the bank yet. Unreconciled: not matched to a statement. Reconciled: matched to a statement.")
    }
}
