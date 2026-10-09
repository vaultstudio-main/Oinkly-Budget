#if os(iOS)
import SwiftUI

/// A rounded card on a system material.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct TransactionRowView: View {
    let transaction: Transaction
    var showAccount = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: transaction.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ReconcileBadge(state: transaction.state, showsTitle: false)
            Text(transaction.amount, format: .appCurrency)
                .font(.body.weight(.semibold))
                .foregroundStyle(transaction.amount > 0 ? Color.green : (transaction.amount < 0 ? Color.red : Color.secondary))
        }
    }

    private var title: String {
        if !transaction.payee.isEmpty { return transaction.payee }
        return transaction.category?.name ?? "Transaction"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let name = transaction.category?.name, !transaction.payee.isEmpty { parts.append(name) }
        if showAccount, let account = transaction.account?.name { parts.append(account) }
        if let method = transaction.paymentType { parts.append(method.title) }
        if transaction.state != .unreconciled { parts.append(transaction.state.title) }
        parts.append(transaction.date.formatted(.dateTime.month().day()))
        return parts.joined(separator: " · ")
    }
}
#endif
