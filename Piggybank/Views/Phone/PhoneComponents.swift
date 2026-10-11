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
        // The row can outlive its transaction for a moment after a delete.
        if transaction.isLive { row }
    }

    private var row: some View {
        HStack(spacing: 12) {
            if let type = investmentType {
                CategoryBadge(symbol: type.symbol, color: Color(hex: type.colorHex))
            } else {
                CategoryBadge(category: transaction.category)
            }
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

    /// Set for transactions in investment accounts, which show a type instead of a category.
    private var investmentType: InvestmentType? {
        transaction.account?.supportsHoldings == true ? InvestmentType.of(transaction) : nil
    }

    private var title: String {
        if !transaction.payee.isEmpty { return transaction.payee }
        return investmentType?.title ?? transaction.category?.name ?? "Transaction"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let type = investmentType {
            if !transaction.payee.isEmpty, transaction.payee != type.title { parts.append(type.title) }
        } else if let name = transaction.fixedCategoryTitle ?? transaction.category?.name, !transaction.payee.isEmpty {
            parts.append(name)
        }
        if showAccount, let account = transaction.account?.name { parts.append(account) }
        if !transaction.paymentTitle.isEmpty { parts.append(transaction.paymentTitle) }
        if transaction.state != .unreconciled { parts.append(transaction.state.title) }
        parts.append(transaction.date.formatted(.dateTime.month().day()))
        return parts.joined(separator: " · ")
    }
}
#endif
