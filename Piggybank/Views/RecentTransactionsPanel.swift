import SwiftUI

/// The last 15 transactions across all accounts, with each one's status.
struct RecentTransactionsPanel: View {
    let transactions: [Transaction]

    var body: some View {
        let recent = RecentActivity.latest(transactions)
        VStack(alignment: .leading, spacing: 0) {
            if recent.isEmpty {
                Text("No transactions yet. Use File ▸ New Transaction to add one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
                    GridRow {
                        header("Date"); header("Account"); header("Payee"); header("Category"); header("Status")
                        header("Amount").gridColumnAlignment(.trailing)
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(recent) { transaction in
                        GridRow {
                            Text(transaction.date, format: .dateTime.month(.abbreviated).day().year())
                                .foregroundStyle(.secondary)
                            Text(transaction.account?.name ?? "")
                            HStack(spacing: 6) {
                                if transaction.isTransfer { Image(systemName: "arrow.left.arrow.right").font(.caption).foregroundStyle(.secondary) }
                                Text(transaction.payee.isEmpty ? "—" : transaction.payee)
                            }
                            Text(transaction.isTransfer ? "Transfer" : (transaction.category?.name ?? "—"))
                                .foregroundStyle(.secondary)
                            ReconcileBadge(state: transaction.state)
                            Text(transaction.amount, format: .appCurrency)
                                .foregroundStyle(transaction.amount > 0 ? Theme.green : (transaction.amount < 0 ? Theme.red : Color.secondary))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
    }
}
