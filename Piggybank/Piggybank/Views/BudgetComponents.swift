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
