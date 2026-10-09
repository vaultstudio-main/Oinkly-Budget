import SwiftUI

/// A category icon in a soft tinted circle.
struct CategoryBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: Circle())
    }
}

extension CategoryBadge {
    init(category: Category?, size: CGFloat = 40) {
        self.init(
            symbol: category?.symbol ?? "questionmark",
            color: category.map { Color(hex: $0.colorHex) } ?? .gray,
            size: size
        )
    }
}

/// Category name, how much is left, and a progress bar.
struct BudgetProgressRow: View {
    let category: Category
    let spent: Decimal

    var body: some View {
        let limit = category.monthlyLimit
        let over = limit > 0 && spent > limit
        let tint = over ? Color.red : Color(hex: category.colorHex)

        HStack(spacing: 12) {
            CategoryBadge(category: category)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category.name).font(.headline)
                    Spacer()
                    Group {
                        if limit <= 0 {
                            Text("\(spent, format: .appCurrency) spent")
                        } else if over {
                            Text("\(spent - limit, format: .appCurrency) over")
                                .foregroundStyle(.red)
                        } else {
                            Text("\(limit - spent, format: .appCurrency) left")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                ProgressView(value: Budget.progress(spent: spent, limit: limit))
                    .tint(tint)
                    .animation(.smooth, value: spent)
            }
        }
    }
}
