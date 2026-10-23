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

    /// A symbol's menu name: the one given above, or its own name made readable ("figure.run" is "Run").
    static func name(_ symbol: String) -> String {
        if let known = names[symbol] ?? goalNames[symbol] { return known }
        let last = symbol.split(separator: ".").first { !["fill", "circle", "square"].contains($0) } ?? Substring(symbol)
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    /// What suits one built-in budget category, so the menu holds what fits it and little else. Nil for one with no list of its own.
    static func symbols(forCategoryKey key: String) -> [String]? { byCategory[key] }

    private static let byCategory: [String: [String]] = [
        "housing": ["house", "building.2", "key", "door.left.hand.open", "bed.double", "sofa", "lightbulb", "shield"],
        "property-tax": ["doc.text", "building.columns", "house", "seal", "percent", "doc.plaintext"],
        "hoa-fees": ["building.2", "person.3", "house", "key", "leaf"],
        "utilities": ["bolt", "drop", "flame", "lightbulb", "powerplug", "trash", "thermometer.medium", "wifi"],
        "phone-internet": ["wifi", "phone", "iphone", "antenna.radiowaves.left.and.right", "network", "tv"],
        "home-maintenance": ["hammer", "wrench.and.screwdriver", "screwdriver", "wrench", "paintbrush", "house"],
        "home-improvement": ["paintbrush", "hammer", "ruler", "paintbrush.pointed", "house", "lightbulb", "square.split.2x2"],
        "furniture-appliances": ["sofa", "bed.double", "chair.lounge", "refrigerator", "washer", "lamp.desk", "tv"],
        "lawn-garden": ["leaf", "tree", "sun.max", "drop", "pawprint", "camera.macro", "scissors"],
        "household-supplies": ["sparkles", "cart", "basket", "trash", "bubbles.and.sparkles", "shippingbox", "bag"],
        "groceries": ["cart", "basket", "bag", "carrot", "fork.knife", "takeoutbag.and.cup.and.straw", "leaf", "birthday.cake"],
        "dining-out": ["fork.knife", "takeoutbag.and.cup.and.straw", "cup.and.saucer", "wineglass", "birthday.cake", "fork.knife.circle", "star"],
        "coffee-snacks": ["cup.and.saucer", "mug", "birthday.cake", "takeoutbag.and.cup.and.straw", "carrot", "leaf"],
        "alcohol-bars": ["wineglass", "mug", "party.popper", "music.note", "moon.stars", "takeoutbag.and.cup.and.straw"],
        "gas-fuel": ["fuelpump", "car", "bolt.car", "gauge", "drop", "flame", "location"],
        "auto-maintenance": ["wrench.and.screwdriver", "car", "gearshape", "wrench", "battery.100", "gauge", "fuelpump"],
        "auto-payment": ["car", "key", "doc.text", "creditcard", "bolt.car", "banknote", "calendar"],
        "parking-tolls": ["parkingsign", "car", "road.lanes", "creditcard", "location", "ticket", "mappin"],
        "public-transit": ["tram", "bus", "train.side.front.car", "ferry", "bicycle", "ticket", "figure.walk"],
        "rideshare-taxi": ["location", "car", "car.2", "mappin.and.ellipse", "bicycle", "scooter", "figure.walk"],
        "insurance": ["checkmark.shield", "shield", "umbrella", "doc.text", "lock", "person.2", "heart.text.square"],
        "auto-insurance": ["shield", "car", "checkmark.shield", "doc.text", "lock", "wrench.and.screwdriver"],
        "health-insurance": ["heart.text.square", "cross.case", "stethoscope", "checkmark.shield", "pills", "heart"],
        "home-insurance": ["umbrella", "house", "checkmark.shield", "lock", "flame", "cloud.bolt", "drop"],
        "life-insurance": ["person.crop.circle", "heart", "person.2", "checkmark.shield", "leaf", "star"],
        "healthcare": ["cross.case", "stethoscope", "heart.text.square", "cross", "bandage", "waveform.path.ecg", "pills"],
        "dental": ["mouth", "cross.case", "stethoscope", "sparkles", "checkmark.circle"],
        "vision": ["eyeglasses", "eye", "sun.max", "cross.case", "stethoscope"],
        "pharmacy": ["pills", "cross.case", "syringe", "bandage", "drop", "cart"],
        "mental-health": ["brain.head.profile", "heart", "leaf", "bubble.left.and.bubble.right", "moon.stars", "sparkles"],
        "fitness": ["figure.run", "dumbbell", "figure.walk", "bicycle", "figure.yoga", "figure.pool.swim", "heart", "trophy"],
        "personal-care": ["scissors", "comb", "sparkles", "drop", "face.smiling", "bubbles.and.sparkles", "heart"],
        "salon-barber": ["comb", "scissors", "sparkles", "face.smiling", "paintbrush", "star"],
        "clothing": ["tshirt", "bag", "shoeprints.fill", "eyeglasses", "sparkles", "hanger", "gift"],
        "shopping": ["bag", "cart", "gift", "creditcard", "tag", "shippingbox", "basket"],
        "electronics": ["desktopcomputer", "laptopcomputer", "iphone", "headphones", "keyboard", "tv", "gamecontroller", "externaldrive"],
        "entertainment": ["film", "play.rectangle", "popcorn", "tv", "music.note", "ticket", "theatermasks", "party.popper"],
        "events-concerts": ["ticket", "music.note", "guitars", "party.popper", "theatermasks", "mic", "star"],
        "hobbies": ["paintpalette", "camera", "guitars", "puzzlepiece", "scissors", "books.vertical", "hammer", "fish"],
        "books-media": ["books.vertical", "book", "newspaper", "headphones", "film", "play.rectangle", "music.note"],
        "games": ["gamecontroller", "dice", "puzzlepiece", "trophy", "desktopcomputer", "party.popper"],
        "subscriptions": ["play.rectangle", "tv", "music.note", "newspaper", "icloud", "repeat", "headphones", "star"],
        "travel": ["airplane", "suitcase", "globe.americas", "map", "camera", "sailboat", "ticket", "mappin.and.ellipse"],
        "hotels-lodging": ["bed.double", "building.2", "key", "suitcase", "moon.stars", "house"],
        "kids-family": ["person.2", "figure.and.child.holdinghands", "teddybear", "balloon", "heart", "house", "birthday.cake"],
        "childcare": ["figure.and.child.holdinghands", "teddybear", "figure.2.and.child.holdinghands", "heart", "clock", "house"],
        "kids-activities": ["soccerball", "basketball", "tennis.racket", "figure.run", "music.note", "paintpalette", "trophy", "teddybear"],
        "education": ["book", "graduationcap", "pencil", "backpack", "books.vertical", "laptopcomputer", "studentdesk"],
        "student-loans": ["graduationcap", "book", "banknote", "doc.text", "building.columns", "percent"],
        "pets": ["pawprint", "dog", "cat", "bird", "fish", "teddybear"],
        "pet-care-vet": ["stethoscope", "pawprint", "cross.case", "pills", "dog", "cat"],
        "gifts-donations": ["gift", "heart", "balloon", "party.popper", "birthday.cake", "star", "envelope"],
        "charity": ["heart", "hands.sparkles", "person.2", "gift", "globe.americas", "leaf", "star"],
        "fees-charges": ["creditcard", "exclamationmark.circle", "doc.text", "percent", "minus.circle", "banknote"],
        "bank-fees": ["building.columns", "creditcard", "minus.circle", "banknote", "doc.text", "percent"],
        "interest-paid": ["percent", "chart.line.downtrend.xyaxis", "creditcard", "banknote", "building.columns", "arrow.down.circle"],
        "investment-fees": ["minus.circle", "chart.line.uptrend.xyaxis", "chart.pie", "percent", "doc.text", "building.columns"],
        "taxes-income": ["doc.plaintext", "building.columns", "percent", "doc.text", "seal", "banknote"],
        "taxes-other": ["seal", "doc.text", "building.columns", "house", "car", "percent"],
        "professional-services": ["briefcase", "person.crop.rectangle", "doc.text", "scalemass", "chart.bar", "phone", "envelope"],
        "postage-shipping": ["shippingbox", "envelope", "box.truck", "tray", "airplane", "doc.text"],
        "memberships-dues": ["person.crop.rectangle", "person.2", "star", "ticket", "dumbbell", "building.columns", "creditcard"],
        "cash-withdrawals": ["banknote", "dollarsign.circle", "building.columns", "creditcard", "wallet.pass", "arrow.down.to.line"],
        "business-expenses": ["briefcase", "doc.text", "laptopcomputer", "chart.bar", "building.2", "creditcard", "shippingbox"],
        "miscellaneous": ["ellipsis.circle", "tag", "star", "questionmark.circle", "shippingbox", "square.grid.2x2", "bag"],
        "paycheck": ["briefcase", "banknote", "building.2", "dollarsign.circle", "calendar", "creditcard"],
        "bonus": ["star", "gift", "trophy", "banknote", "party.popper", "sparkles"],
        "freelance-income": ["laptopcomputer", "pencil", "briefcase", "paintpalette", "camera", "dollarsign.circle", "hammer"],
        "business-income": ["storefront", "briefcase", "building.2", "chart.bar", "cart", "banknote"],
        "rental-income": ["key", "house", "building.2", "banknote", "door.left.hand.open", "calendar"],
        "interest-dividends": ["percent", "chart.pie", "banknote", "building.columns", "chart.line.uptrend.xyaxis", "dollarsign.circle"],
        "investment-gains": ["chart.line.uptrend.xyaxis", "chart.bar", "chart.pie", "arrow.up.right", "bitcoinsign.circle", "dollarsign.circle"],
        "refunds": ["arrow.uturn.backward", "creditcard", "bag", "shippingbox", "banknote", "arrow.counterclockwise"],
        "tax-refund": ["arrow.uturn.backward.circle", "doc.plaintext", "building.columns", "banknote", "seal", "percent"],
        "reimbursements": ["arrow.triangle.2.circlepath", "doc.text", "briefcase", "banknote", "creditcard", "arrow.uturn.backward"],
        "gifts-received": ["gift", "heart", "balloon", "envelope", "party.popper", "star"],
        "government-benefits": ["building.columns", "doc.text", "person.2", "shield", "star", "banknote"],
        "pension-retirement": ["hourglass", "figure.walk", "building.columns", "banknote", "chart.pie", "sun.max"],
        "support-received": ["person.2", "heart", "figure.and.child.holdinghands", "banknote", "house", "calendar"],
        "cashback-rewards": ["star.circle", "creditcard", "gift", "percent", "star", "banknote"],
        "sale-of-items": ["tag", "bag", "cart", "shippingbox", "dollarsign.circle", "car"],
        "deposit": ["arrow.down.to.line", "building.columns", "banknote", "dollarsign.circle", "creditcard", "tray"],
        "other-income": ["dollarsign.circle", "banknote", "star", "plus.circle", "gift", "tag"],
    ]

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
    /// When the category itself says what fits (a goal's, a budget's), this is the whole menu and the set menu is not shown.
    var fitting: [String]?

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
        let list = (fitting ?? (offer.symbols + extra)).filter { $0 != automatic && seen.insert($0).inserted }
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
    /// What suits one kind of goal, by the category picked for it ("Vacation & Travel", "Student Loan").
    static func goalOffer(category title: String?, kind: GoalKind) -> [String] {
        guard let title, let list = goalByTitle[title] else { return goalSymbols(for: kind) }
        return list
    }

    private static let goalByTitle: [String: [String]] = [
        "Emergency Fund": ["shield.lefthalf.filled", "checkmark.shield", "lifepreserver", "lock", "banknote", "umbrella", "cross.case", "bolt"],
        "Vacation & Travel": ["airplane", "suitcase", "globe.americas", "map", "camera", "sailboat", "beach.umbrella", "tent", "mountain.2"],
        "Home Down Payment": ["house", "key", "building.2", "door.left.hand.open", "banknote", "doc.text", "sofa"],
        "Car": ["car", "key", "bolt.car", "fuelpump", "steeringwheel", "wrench.and.screwdriver", "car.2"],
        "Wedding": ["heart", "party.popper", "gift", "balloon", "sparkles", "birthday.cake", "camera", "wineglass"],
        "Education": ["graduationcap", "book", "pencil", "backpack", "books.vertical", "laptopcomputer", "studentdesk"],
        "Retirement": ["figure.walk", "sun.max", "beach.umbrella", "hourglass", "chart.pie", "banknote", "house", "leaf"],
        "Investing": ["chart.line.uptrend.xyaxis", "chart.pie", "chart.bar", "bitcoinsign.circle", "banknote", "building.columns", "arrow.up.right"],
        "Home Improvement": ["hammer", "paintbrush", "wrench.and.screwdriver", "ruler", "house", "sofa", "lightbulb", "leaf"],
        "Medical & Health": ["cross.case", "heart.text.square", "stethoscope", "pills", "bandage", "figure.run", "waveform.path.ecg"],
        "New Baby & Family": ["figure.and.child.holdinghands", "teddybear", "balloon", "heart", "person.2", "house", "stroller"],
        "Holidays & Gifts": ["gift", "heart", "snowflake", "party.popper", "balloon", "star", "tree", "birthday.cake"],
        "Gadgets & Tech": ["laptopcomputer", "iphone", "headphones", "desktopcomputer", "gamecontroller", "tv", "camera", "keyboard"],
        "Big Purchase": ["bag", "cart", "shippingbox", "creditcard", "tag", "sofa", "star", "gift"],
        "Rainy Day Cushion": ["umbrella", "cloud.rain", "shield", "lifepreserver", "banknote", "lock"],
        "Other Savings": ["banknote", "star", "dollarsign.circle", "target", "flag", "heart", "sparkles"],
        "Credit Card": ["creditcard", "banknote", "percent", "calendar", "arrow.down.circle", "lock", "star"],
        "Store Card": ["bag", "creditcard", "tag", "cart", "storefront", "gift", "percent"],
        "Auto Loan": ["car", "key", "banknote", "doc.text", "calendar", "percent", "wrench.and.screwdriver"],
        "Mortgage": ["house", "key", "building.2", "doc.text", "banknote", "calendar", "percent"],
        "Home Equity / HELOC": ["building.2", "house", "key", "banknote", "percent", "doc.text", "hammer"],
        "Student Loan": ["graduationcap", "book", "backpack", "banknote", "doc.text", "percent", "building.columns"],
        "Personal Loan": ["person.crop.circle", "banknote", "doc.text", "calendar", "percent", "creditcard"],
        "Line of Credit": ["arrow.triangle.2.circlepath", "creditcard", "banknote", "building.columns", "percent", "calendar"],
        "Business Loan": ["briefcase", "building.2", "storefront", "chart.bar", "banknote", "doc.text", "laptopcomputer"],
        "Medical Debt": ["cross.case", "heart.text.square", "stethoscope", "pills", "doc.text", "banknote", "bandage"],
        "Tax Debt": ["doc.text", "doc.plaintext", "building.columns", "seal", "percent", "banknote", "calendar"],
        "Buy Now Pay Later": ["calendar", "bag", "creditcard", "cart", "clock", "tag", "shippingbox"],
        "Boat / RV / Motorcycle Loan": ["sailboat", "ferry", "bicycle", "car", "tent", "fuelpump", "key"],
        "Loan from Family or Friend": ["person.2", "heart", "banknote", "house", "gift", "figure.and.child.holdinghands"],
        "Other Debt": ["arrow.down.circle", "banknote", "doc.text", "calendar", "creditcard", "percent", "minus.circle"],
    ]

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
