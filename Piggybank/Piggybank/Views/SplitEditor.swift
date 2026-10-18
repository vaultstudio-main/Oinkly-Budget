import SwiftUI

/// The rows of a split: a category and an amount for each part, with what is left to give a category underneath.
/// Used inside a form section by New Transaction and Edit Transaction.
struct SplitEditor: View {
    @Binding var parts: [SplitDraft]
    /// The transaction's full amount, positive.
    let total: Decimal
    let categories: [Category]
    let isPayment: Bool

    private var remaining: Decimal { Splits.remaining(parts, of: total) }

    var body: some View {
        ForEach($parts) { $part in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Picker("Category", selection: $part.category) {
                        CategoryOptions(categories: categories, only: isPayment ? .expense : .income, keeping: part.category)
                    }
                    .labelsHidden()
                    CurrencyField("Amount", value: $part.amount)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                    Button {
                        parts.removeAll { $0.id == part.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(parts.count <= Splits.minimumParts)
                    .help("Remove this part")
                }
                FormTextField("Memo", text: $part.memo, hint: "Memo for this part (optional)", showsLabel: false)
                    .font(.callout)
            }
        }

        HStack {
            Button {
                parts.append(SplitDraft(amount: remaining > 0 ? remaining : nil))
            } label: {
                Label("Add Part", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            Spacer()
            summary
        }
    }

    @ViewBuilder
    private var summary: some View {
        if total <= 0 {
            Text("Enter the amount above first.").font(.callout).foregroundStyle(.secondary)
        } else if remaining == 0, parts.contains(where: { $0.category == nil || ($0.amount ?? 0) <= 0 }) {
            Label("Give every part a category and an amount", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
        } else if remaining == 0 {
            Label("Adds up to \(total.formatted(.appCurrency))", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(Theme.green)
        } else if remaining > 0 {
            Label("\(remaining.formatted(.appCurrency)) left to assign", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
        } else {
            Label("\((-remaining).formatted(.appCurrency)) over", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(Theme.red)
        }
    }
}
