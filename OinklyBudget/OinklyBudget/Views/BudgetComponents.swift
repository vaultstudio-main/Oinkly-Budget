import SwiftUI
import SwiftData

/// A category icon in a soft tinted circle.
struct CategoryBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    /// For a built-in category, whose icon and colour you may have chosen, kept apart from the category itself.
    var category: Category?

    @Query private var choices: [ArtworkChoice]

    init(symbol: String, color: Color, size: CGFloat = 40) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    /// The same small gradient square as the bill and account pictures, in the category's colour.
    var body: some View {
        let owner = category.flatMap { $0.isLive ? ItemIcons.key(for: $0) : nil }
        let chosenSymbol = owner.flatMap { ItemIcons.symbol(of: $0, in: choices) }
        let theme = owner.flatMap { key in choices.live.first { $0.key == key }?.theme } ?? 0
        ArtworkTile(symbol: chosenSymbol ?? symbol, theme: ArtworkTheme.resolved(theme, seed: category.flatMap { $0.isLive ? ItemIcons.seed(for: $0) : nil }), color: color)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(size * 0.22, 5), style: .continuous))
    }
}

extension CategoryBadge {
    init(category: Category?, size: CGFloat = 40) {
        self.init(
            symbol: category?.symbol ?? "questionmark",
            color: category.map { Color(hex: $0.colorHex) } ?? .gray,
            size: size
        )
        self.category = category
    }
}
