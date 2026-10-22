import SwiftUI
import SwiftData
import AppKit

/// The second step of first-run setup, after the accounts: give each category a monthly budget, or leave it at zero for none.
/// The built-in categories are already there, so this only sets their amounts and lets you add your own.
struct CategorySetupView: View {
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var allCategories: [Category]
    @State private var addingOwn = false

    /// Your own first, then the built-in ones in their usual order (housing, food, transport and so on).
    private var expenses: [Category] {
        let order = Dictionary(uniqueKeysWithValues: Category.definitions.enumerated().map { ($1.key, $0) })
        let list = allCategories.live.filter { !$0.isIncome }
        return list.filter(\.isCustom) + list.filter { !$0.isCustom }.sorted { (order[$0.systemKey ?? ""] ?? .max) < (order[$1.systemKey ?? ""] ?? .max) }
    }

    var body: some View {
        let list = expenses
        let budgeted = list.filter { $0.monthlyLimit > 0 }
        let total = budgeted.reduce(Decimal(0)) { $0 + $1.monthlyLimit }

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set up your budgets")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Give each category a monthly amount, or leave it at zero if you don't want a budget for it. You can change any of these later on the Budgets page or in Settings ▸ Categories.")
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 14, alignment: .top)], alignment: .leading, spacing: 10) {
                        ForEach(list) { category in row(category) }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("YOUR BUDGETS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(total, format: .appCurrency).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("a month across \(budgeted.count) budget\(budgeted.count == 1 ? "" : "s")")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("Month Outlook counts these as money set aside each month, so keep only the ones you really want.")
                    .font(.caption).foregroundStyle(.secondary)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button(action: useSuggested) {
                        Label("Suggested Amounts", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .help("Fill in the amounts the app suggests, which you can then change")

                    Button(action: clearAll) {
                        Label("Clear All", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .help("Set every budget to zero, so you choose which ones to have")

                    Button { addingOwn = true } label: {
                        Label("Add Your Own…", systemImage: "plus.circle").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .help("Make a category of your own with its own budget")

                    Divider().padding(.vertical, 4)

                    Button {
                        modelContext.saveNow()
                        onFinish()
                    } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 300)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.background)
        .sheet(isPresented: $addingOwn) { CustomBudgetEditView(category: nil) }
    }

    private func row(_ category: Category) -> some View {
        HStack(spacing: 10) {
            CategoryBadge(category: category, size: 28)
            Text(category.name).lineLimit(1)
            Spacer(minLength: 4)
            BudgetAmountField(category: category)
                .frame(width: 110)
        }
        .padding(10)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The amounts the app suggests for the built-in categories. Your own keep what they have.
    private func useSuggested() {
        let suggested = Dictionary(Category.definitions.map { ($0.key, $0.budget) }, uniquingKeysWith: { first, _ in first })
        for category in allCategories.live where !category.isIncome && !category.isCustom {
            if let key = category.systemKey, let amount = suggested[key] { category.monthlyLimit = amount }
        }
        modelContext.saveNow()
    }

    private func clearAll() {
        for category in allCategories.live where !category.isIncome { category.monthlyLimit = 0 }
        modelContext.saveNow()
    }
}

/// A budget box that gets out of the way: type any number you like and nothing is rewritten under your fingers. The amount is kept as
/// you type, and the box is tidied into currency (such as $1,500.00) only once you leave it.
private struct BudgetAmountField: View {
    let category: Category
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Monthly budget", text: $text, prompt: Text(Decimal(0), format: .appCurrency))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onAppear { text = BudgetAmountText.shown(category.monthlyLimit, editing: false) }
            .onChange(of: text) { _, new in
                // Keep the amount up to date while typing, without touching what is in the box.
                guard focused else { return }
                category.monthlyLimit = BudgetAmountText.parse(new)
            }
            .onChange(of: focused) { _, isFocused in
                text = BudgetAmountText.shown(category.monthlyLimit, editing: isFocused)
            }
            // Suggested Amounts, Clear All and the like change the amount from outside.
            .onChange(of: category.monthlyLimit) { _, new in
                if !focused { text = BudgetAmountText.shown(new, editing: false) }
            }
    }
}

enum BudgetAmountText {
    /// Reads whatever was typed: digits and one decimal point, ignoring currency signs, commas, spaces and letters. Nothing
    /// readable is zero. Never negative.
    static func parse(_ text: String, decimalSeparator: String = Locale.current.decimalSeparator ?? ".") -> Decimal {
        var number = ""
        var seenPoint = false
        for character in text {
            if character.isASCII, character.isNumber {
                number.append(character)
            } else if String(character) == decimalSeparator || character == ".", !seenPoint {
                seenPoint = true
                number.append(".")
            }
        }
        return Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// What the box shows: empty for zero, the plain number while editing, and tidy currency otherwise.
    static func shown(_ value: Decimal, editing: Bool) -> String {
        guard value != 0 else { return "" }
        return editing ? "\(value)" : value.formatted(.appCurrency)
    }
}

#if DEBUG
extension CategorySetupView {
    /// `-categorySetupCheck <folder>` draws this step in a real window, with the built-in categories, and saves a picture.
    @MainActor
    static func runCheckIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "-categorySetupCheck"), flag + 1 < arguments.count else { return }
        let folder = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: OinklyBudgetSchemaV6.self)
        guard let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)) else { exit(1) }
        Category.ensureSystemCategories(in: container.mainContext)
        NSApplication.shared.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: CategorySetupView(onFinish: {}).modelContainer(container))
        window.setFrame(NSRect(x: 100, y: 0, width: 1400, height: 900), display: true)
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        if let content = window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: folder.appendingPathComponent("category-setup.png")) }
        }
        exit(0)
    }
}
#endif
