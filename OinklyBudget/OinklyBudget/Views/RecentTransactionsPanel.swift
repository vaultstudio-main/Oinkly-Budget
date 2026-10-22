import SwiftUI
import SwiftData

/// The last 15 transactions across all accounts: what it was, where, when and how much, with each one's status.
struct RecentTransactionsPanel: View {
    let transactions: [Transaction]

    var body: some View {
        let recent = RecentActivity.latest(transactions)
        if recent.isEmpty {
            ReportEmpty(message: "Transactions show up here as you add them. Use File ▸ New Transaction to add one.", height: 260, shape: .table)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.persistentModelID) { index, transaction in
                    row(transaction)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(index.isMultiple(of: 2) ? Color.secondary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func row(_ transaction: Transaction) -> some View {
        HStack(spacing: 12) {
            badge(transaction)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.payee.isEmpty ? "—" : transaction.payee).fontWeight(.medium).lineLimit(1)
                Text([transaction.account?.name, transaction.fixedCategoryTitle ?? transaction.splitTitle ?? transaction.category?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(transaction.date, format: .dateTime.month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            ReconcileBadge(state: transaction.state, showsTitle: false)
                .frame(width: 22)
            Text(transaction.amount, format: .appCurrency)
                .fontWeight(.medium)
                .foregroundStyle(transaction.amount > 0 ? Theme.green : (transaction.amount < 0 ? Theme.red : Color.secondary))
                .frame(width: 110, alignment: .trailing)
        }
        .font(.callout)
    }

    @ViewBuilder
    private func badge(_ transaction: Transaction) -> some View {
        if transaction.isTransfer {
            CategoryBadge(symbol: "arrow.left.arrow.right", color: .gray, size: 30)
        } else if let category = transaction.category {
            CategoryBadge(category: category, size: 30)
        } else {
            CategoryBadge(symbol: "questionmark", color: .gray, size: 30)
        }
    }
}
