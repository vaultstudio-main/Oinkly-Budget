import SwiftUI
import SwiftData

/// The icons for bills and repeating transactions. By default one takes the icon and colour of its category, so Auto Insurance looks like
/// Auto Insurance without anyone choosing anything. The Icon choice in each form picks another from the built-in symbols instead.
enum SymbolChoices {
    /// What the picker offers for a category: only symbols and colours that suit its group, so the choice is short and the squares can be
    /// big. Colours are the numbers of `ArtworkTheme`; Automatic is always there as well.
    struct Offer {
        let symbols: [String]
        let themes: [Int]
    }

    static func offer(for category: Category?, picked: [String: CategoryGroup] = [:]) -> Offer {
        guard let category, category.isLive else { return general }
        return offer(for: CategoryGroup.of(category, picked: picked))
    }

    /// What a group offers. Custom is the general set.
    static func offer(for group: CategoryGroup) -> Offer {
        switch group {
        case .housing:
            return Offer(symbols: ["house", "building.2", "bolt", "drop", "flame", "wifi", "phone", "hammer", "paintbrush", "sofa", "leaf", "sparkles"], themes: [5, 1, 3, 6, 8])
        case .food:
            return Offer(symbols: ["cart", "fork.knife", "cup.and.saucer", "wineglass", "bag", "gift"], themes: [4, 3, 6, 7, 1])
        case .transport:
            return Offer(symbols: ["car", "fuelpump", "parkingsign", "tram", "bus", "airplane", "location", "wrench.and.screwdriver"], themes: [1, 5, 3, 8, 4])
        case .insurance:
            return Offer(symbols: ["checkmark.shield", "shield", "umbrella", "heart.text.square", "car", "house", "cross.case", "person.crop.circle"], themes: [5, 1, 4, 8, 2])
        case .health:
            return Offer(symbols: ["cross.case", "pills", "stethoscope", "heart.text.square", "figure.run", "dumbbell", "eyeglasses", "mouth", "brain.head.profile"], themes: [7, 4, 1, 2, 5])
        case .personal:
            return Offer(symbols: ["scissors", "tshirt", "bag", "sparkles", "desktopcomputer", "gift"], themes: [2, 7, 3, 6, 5])
        case .fun:
            return Offer(symbols: ["film", "play.rectangle", "music.note", "gamecontroller", "ticket", "camera", "paintpalette", "books.vertical", "airplane", "bed.double"], themes: [2, 3, 6, 1, 7])
        case .family:
            return Offer(symbols: ["person.2", "figure.and.child.holdinghands", "graduationcap", "book", "pawprint", "soccerball", "stethoscope", "heart"], themes: [6, 4, 7, 1, 3])
        case .giving:
            return Offer(symbols: ["gift", "heart", "star", "person.2"], themes: [7, 2, 6, 4, 3])
        case .financial:
            return Offer(symbols: ["creditcard", "banknote", "dollarsign.circle", "percent", "building.columns", "briefcase", "doc.text", "shippingbox"], themes: [1, 4, 8, 5, 6])
        case .income:
            return Offer(symbols: ["banknote", "dollarsign.circle", "briefcase", "building.columns", "chart.line.uptrend.xyaxis", "gift", "star"], themes: [4, 1, 6, 5, 8])
        case .custom:
            return general
        }
    }

    /// What each symbol is called in the menu.
    static let names: [String: String] = [
        "house": "House", "building.2": "Building", "bolt": "Electric", "drop": "Water", "flame": "Gas", "wifi": "Internet", "phone": "Phone",
        "hammer": "Repairs", "paintbrush": "Paint", "sofa": "Furniture", "leaf": "Garden", "sparkles": "Cleaning", "cart": "Groceries",
        "fork.knife": "Dining", "cup.and.saucer": "Coffee", "wineglass": "Drinks", "bag": "Shopping", "gift": "Gift", "car": "Car",
        "fuelpump": "Fuel", "parkingsign": "Parking", "tram": "Transit", "bus": "Bus", "airplane": "Travel", "location": "Rideshare",
        "wrench.and.screwdriver": "Maintenance", "checkmark.shield": "Protection", "shield": "Shield", "umbrella": "Umbrella",
        "heart.text.square": "Health plan", "cross.case": "Medical", "person.crop.circle": "Person", "pills": "Pharmacy", "stethoscope": "Doctor",
        "figure.run": "Fitness", "dumbbell": "Gym", "eyeglasses": "Vision", "mouth": "Dental", "brain.head.profile": "Mental health",
        "scissors": "Hair", "tshirt": "Clothing", "desktopcomputer": "Electronics", "film": "Movies", "play.rectangle": "Streaming",
        "music.note": "Music", "gamecontroller": "Games", "ticket": "Events", "camera": "Photos", "paintpalette": "Hobbies",
        "books.vertical": "Books", "bed.double": "Lodging", "person.2": "Family", "figure.and.child.holdinghands": "Childcare",
        "graduationcap": "School", "book": "Education", "pawprint": "Pets", "soccerball": "Sports", "heart": "Heart", "star": "Star",
        "creditcard": "Card", "banknote": "Cash", "dollarsign.circle": "Money", "percent": "Interest", "building.columns": "Bank",
        "briefcase": "Business", "doc.text": "Document", "shippingbox": "Shipping", "chart.line.uptrend.xyaxis": "Investments",
        "calendar": "Calendar", "tag": "Tag",
    ]

    static func name(_ symbol: String) -> String { names[symbol] ?? goalNames[symbol] ?? symbol }

    /// For a bill with no category yet, or one of your own.
    static let general = Offer(symbols: ["calendar", "tag", "star", "heart", "house", "car", "creditcard", "bolt", "phone", "cart", "doc.text", "briefcase"], themes: [1, 2, 3, 4, 5, 6])
}

/// The key a bill or a repeating rule's icon choice is kept under: "icon|" and the item's own key and then the symbol, in the same
/// small table as the picture colours, so no model changes.
enum ItemIcons {
    static let prefix = "icon|"

    static func key(for bill: Bill) -> String { ArtworkChoices.key(for: bill) }
    /// A built-in category's icon and colour are kept the same way, since the category itself is reset to the built-in look at every launch.
    static func key(for category: Category) -> String { "cat|" + (category.systemKey ?? category.name) }
    static func key(for rule: RecurringTransaction) -> String { "rule|" + String(format: "%.6f", rule.createdAt.timeIntervalSinceReferenceDate) }

    /// Where a category sits in the rainbow: built-in ones in their built-in order, so a tab of them runs through the colours, and your own by name.
    static func seed(for category: Category) -> Int {
        if let key = category.systemKey, let index = Category.definitions.firstIndex(where: { $0.key == key }) { return index }
        return ArtworkTheme.seed(category.name)
    }

    static func symbol(of owner: String, in choices: [ArtworkChoice]) -> String? {
        let head = prefix + owner + "|"
        return choices.live.first { $0.key.hasPrefix(head) }.map { String($0.key.dropFirst(head.count)) }
    }

    /// Remembers the icon, or forgets it when `symbol` is nil (the category's own icon again). Does not save.
    static func set(_ symbol: String?, owner: String, in context: ModelContext) {
        let head = prefix + owner + "|"
        let all = ((try? context.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).live
        for old in all where old.key.hasPrefix(head) { context.delete(old) }
        if let symbol, !symbol.isEmpty { context.insert(ArtworkChoice(key: head + symbol, theme: 1)) }
    }

    static func symbol(of owner: String, in context: ModelContext) -> String? {
        symbol(of: owner, in: ((try? context.fetch(FetchDescriptor<ArtworkChoice>())) ?? []))
    }

    /// Icon choices whose bill or rule is gone.
    static func removeOrphans(in context: ModelContext) {
        let bills = Set(((try? context.fetch(FetchDescriptor<Bill>())) ?? []).live.map { key(for: $0) })
        let rules = Set(((try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []).live.map { key(for: $0) })
        let categories = Set(((try? context.fetch(FetchDescriptor<Category>())) ?? []).live.map { key(for: $0) })
        for choice in ((try? context.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).live where choice.key.hasPrefix("cat|") && !categories.contains(choice.key) {
            context.delete(choice)
        }
        for choice in ((try? context.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).live where choice.key.hasPrefix("rule|") && !rules.contains(choice.key) {
            context.delete(choice)
        }
        for choice in ((try? context.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).live where choice.key.hasPrefix(prefix) {
            let rest = choice.key.dropFirst(prefix.count)
            let owner = rest.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).prefix(2).joined(separator: "|")
            if !bills.contains(owner) && !rules.contains(owner) && !categories.contains(owner) { context.delete(choice) }
        }
    }
}

/// A small square in the same style as the account pictures: a gradient, soft circles for depth, and the symbol in white with a soft
/// shadow. Its colour is one of the artwork colours, or, on Automatic, a gradient of its category's colour.
struct ArtworkTile: View {
    let symbol: String
    var theme = 0
    var category: Category?
    /// A colour to build the gradient from, for the places that already know one (a budget's, a goal's).
    var color: Color?

    private var colors: (top: Color, bottom: Color) {
        if let chosen = ArtworkTheme.colors(theme) { return chosen }
        if let color { return Self.gradient(from: color) }
        if let category, category.isLive { return Self.gradient(from: Color(hex: category.colorHex)) }
        return (Color(red: 0.98, green: 0.69, blue: 0.25), Color(red: 0.93, green: 0.40, blue: 0.20))
    }

    /// Lighter at the top and a touch deeper at the bottom, so any single colour reads like the artwork colours.
    static func gradient(from color: Color) -> (top: Color, bottom: Color) {
        (color.mix(with: .white, by: 0.30), color.mix(with: .black, by: 0.12))
    }

    var body: some View {
        GeometryReader { geo in
            let m = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [colors.top, colors.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.13)).frame(width: m * 0.9, height: m * 0.9).offset(x: -m * 0.30, y: -m * 0.34)
                Circle().fill(.white.opacity(0.10)).frame(width: m, height: m).offset(x: m * 0.30, y: m * 0.32)
                Image(systemName: symbol)
                    .font(.system(size: m * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: m * 0.04, y: m * 0.03)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// The icon for a bill or a repeating rule: the symbol chosen, or its category's, in the colour chosen.
struct ItemIconBadge: View {
    let owner: String
    let category: Category?
    /// The name its default colour comes from.
    var seed: String = ""
    var size: CGFloat = 36

    @Query private var choices: [ArtworkChoice]

    var body: some View {
        let chosen = ItemIcons.symbol(of: owner, in: choices)
        let theme = choices.live.first { $0.key == owner }?.theme ?? 0
        ArtworkTile(symbol: chosen ?? (category?.isLive == true ? category?.symbol : nil) ?? "calendar",
                    theme: ArtworkTheme.resolved(theme, seed: ArtworkTheme.seed(seed.isEmpty ? owner : seed)), category: category)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(size * 0.2, 6), style: .continuous))
    }
}

/// A bill's icon: its photo or its loan's picture when it has one, otherwise its icon.
struct BillIconView: View {
    let bill: Bill
    var size: CGFloat = 36

    var body: some View {
        if bill.displayPhotoData != nil || bill.loan?.isLive == true {
            AccountPicture(data: bill.displayPhotoData, type: bill.loan?.isLive == true ? bill.loan?.type : nil, bill: bill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            ItemIconBadge(owner: ItemIcons.key(for: bill), category: bill.category, seed: bill.name, size: size)
        }
    }
}

/// A repeating rule's icon.
struct RuleIconView: View {
    let rule: RecurringTransaction
    var size: CGFloat = 36

    var body: some View {
        ItemIconBadge(owner: ItemIcons.key(for: rule), category: rule.category, seed: rule.payee, size: size)
    }
}

/// The choice in a form: a menu of the icons that suit the bill's category, and a row of colours. The category decides what is in the
/// menu; Automatic, first, is the category's own symbol. The row shows the chosen icon in each colour.
struct IconPicker: View {
    @Binding var symbol: String?
    @Binding var theme: Int
    let category: Category?
    /// For a budget: the symbol and colour it has when you choose Automatic, and a menu to choose the set of icons from.
    var automaticSymbol: String?
    var automaticColor: Color?
    var setChoice: Binding<CategoryGroup>?
    /// Where Automatic sits in the rainbow, so its tile shows the colour the item really gets.
    var rainbowSeed: Int?
    /// More icons for the menu after the set's own, such as a goal's.
    var extra: [String] = []

    @Query private var marks: [CashBudgetMark]

    private var group: CategoryGroup {
        if let setChoice { return setChoice.wrappedValue }
        guard let category, category.isLive else { return .custom }
        return CategoryGroup.of(category, picked: CashBudgets.groups(from: marks.live.map(\.key)))
    }

    private var offer: SymbolChoices.Offer { SymbolChoices.offer(for: group) }
    private var automatic: String { automaticSymbol ?? (category?.isLive == true ? (category?.symbol ?? "calendar") : "calendar") }
    private var current: String { symbol ?? automatic }

    /// A choice made earlier, or under another category, is still in the menu so it can be seen and kept.
    private var symbols: [String] {
        var seen = Set<String>()
        let list = (offer.symbols + extra).filter { $0 != automatic && seen.insert($0).inserted }
        if let symbol, symbol != automatic, !list.contains(symbol) { return [symbol] + list }
        return list
    }

    /// Every colour there is, so the whole space is used.
    private var themes: [Int] { Array(1...ArtworkTheme.options.count) }

    private func tile(_ name: String, theme: Int, size: CGFloat) -> some View {
        ArtworkTile(symbol: name, theme: ArtworkTheme.resolved(theme, seed: rainbowSeed), category: category, color: theme == 0 ? automaticColor : nil)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let setChoice {
                Picker("Icon set", selection: setChoice) {
                    ForEach(CategoryGroup.allCases) { Text($0 == .custom ? "General" : $0.title).tag($0) }
                }
            }
            Picker("Icon", selection: $symbol) {
                Label("Automatic", systemImage: automatic).tag(String?.none)
                Divider()
                ForEach(symbols, id: \.self) { name in
                    Label(SymbolChoices.name(name), systemImage: name).tag(Optional(name))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Colour").font(.callout)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42, maximum: 46), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach([0] + themes, id: \.self) { number in
                        Button { theme = number } label: {
                            tile(current, theme: number, size: 42)
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(theme == number ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: theme == number ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                        .help(ArtworkTheme.name(number))
                        .accessibilityLabel(ArtworkTheme.name(number))
                        .accessibilityAddTraits(theme == number ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// A goal's icon, in the longer rectangle the account pictures use, so the Planning pages look alike.
struct GoalIcon: View {
    let symbol: String
    let colorHex: String
    /// The goal's name. A colour that is none of the artwork colours is the plain default, which takes its place in the rainbow by this.
    var seed: String = ""
    var width: CGFloat = 64
    var height: CGFloat = 44

    var body: some View {
        let theme = ArtworkTheme.theme(forHex: colorHex)
        ArtworkTile(symbol: symbol, theme: ArtworkTheme.resolved(theme, seed: ArtworkTheme.seed(seed)), color: Color(hex: colorHex))
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension SymbolChoices {
    /// The icons a goal can have, besides its category's own.
    static func goalSymbols(for kind: GoalKind) -> [String] {
        kind == .save
            ? ["shield.lefthalf.filled", "airplane", "house", "car", "heart", "graduationcap", "hammer", "gift", "laptopcomputer", "bag", "umbrella",
               "banknote", "cross.case", "figure.and.child.holdinghands", "chart.line.uptrend.xyaxis", "figure.walk"]
            : ["creditcard", "bag", "car", "house", "building.2", "graduationcap", "person.crop.circle", "briefcase", "cross.case", "doc.text",
               "calendar", "person.2", "sailboat", "arrow.down.circle"]
    }

    static let goalNames: [String: String] = [
        "shield.lefthalf.filled": "Emergency", "laptopcomputer": "Laptop", "figure.walk": "Retirement", "sailboat": "Boat", "arrow.down.circle": "Payoff",
        "person.crop.circle": "Personal", "building.2": "Building",
    ]
}
