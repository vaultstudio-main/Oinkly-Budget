#if os(iOS)
import SwiftUI
import SwiftData

private enum PhoneSection: String, CaseIterable, Identifiable {
    case home = "Home", budgets = "Budgets", transactions = "Transactions", bills = "Bills", planning = "Planning", reports = "Reports", settings = "Settings"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .budgets: "chart.pie.fill"
        case .transactions: "list.bullet.rectangle"
        case .bills: "calendar"
        case .planning: "target"
        case .reports: "chart.bar.xaxis"
        case .settings: "gearshape.fill"
        }
    }
}

private struct OpenMenuKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private struct ShowsMenuButtonKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False where a sidebar replaces the hamburger menu (iPad).
    var showsMenuButton: Bool {
        get { self[ShowsMenuButtonKey.self] }
        set { self[ShowsMenuButtonKey.self] = newValue }
    }

    /// Opens the side menu. Every screen's menu button calls it.
    var openMenu: () -> Void {
        get { self[OpenMenuKey.self] }
        set { self[OpenMenuKey.self] = newValue }
    }
}

extension View {
    /// Adds the hamburger button to the top left of a screen's navigation bar.
    func menuButton() -> some View { modifier(MenuButtonModifier()) }
}

private struct MenuButtonModifier: ViewModifier {
    @Environment(\.openMenu) private var openMenu
    @Environment(\.showsMenuButton) private var showsMenuButton

    func body(content: Content) -> some View {
        content.toolbar {
            if showsMenuButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Menu", systemImage: "line.3.horizontal", action: openMenu)
                }
            }
        }
    }
}

/// The same app on iPhone and iPad, navigated with a slide-out side menu. On a wide iPad screen it stays a
/// centered, phone-width column instead of stretching every card and button edge to edge.
struct PhoneRootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // iPad full screen gets a Mac-style sidebar. iPhone, and iPad in Split View or Slide Over, get the slide-out menu.
        if sizeClass == .regular { PadRootView() } else { PhoneMenuRootView() }
    }
}

/// Something the sidebar can show: one of the sections, or a single account's register.
private enum PhoneDestination: Hashable {
    case section(PhoneSection)
    case account(Account.ID)
    case manageAccounts
}

/// Where each destination's screen comes from, shared by the slide-out menu and the iPad sidebar.
private struct DestinationScreen: View {
    let destination: PhoneDestination
    @Query private var allAccounts: [Account]

    var body: some View {
        switch destination {
        case .section(let section):
            switch section {
            case .home: HomeView()
            case .budgets: BudgetsView()
            case .transactions: TransactionsView()
            case .bills: PhoneBillsHost()
            case .planning: PhonePlanningHost()
            case .reports: PhoneReportsHost()
            case .settings: PhoneSettingsView()
            }
        case .manageAccounts:
            NavigationStack {
                AccountsSettingsView()
                    .navigationTitle("Manage Accounts")
                    .menuButton()
            }
        case .account(let id):
            if let account = allAccounts.live.first(where: { $0.id == id }) {
                NavigationStack {
                    PhoneAccountView(account: account)
                        .menuButton()
                }
                .id(id)
            } else {
                HomeView()
            }
        }
    }
}

/// iPad: the same sidebar the Mac has, with the sections and then every account. Works with a keyboard too:
/// arrow keys move through the sidebar and ⌘1 to ⌘6 jump to a section.
private struct PadRootView: View {
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @State private var destination: PhoneDestination? = .section(.home)
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $destination) {
                Section {
                    ForEach(PhoneSection.allCases) { item in
                        Label(item.rawValue, systemImage: item.symbol)
                            .tag(PhoneDestination.section(item))
                    }
                }
                let accounts = allAccounts.live
                if !accounts.isEmpty {
                    Section("Accounts") {
                        ForEach(accounts) { account in
                            if account.isLive {
                                Label {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(account.name)
                                        Text(account.typeTitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: account.type.symbol)
                                }
                                .tag(PhoneDestination.account(account.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Piggybank Financial")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        destination = .manageAccounts
                    } label: {
                        Label("Manage Accounts", systemImage: "gearshape.2")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(destination == .manageAccounts ? Color.accentColor.opacity(0.15) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
        } detail: {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                DestinationScreen(destination: destination ?? .section(.home))
                    .id(destination)
                    .frame(maxWidth: 820)
                    .environment(\.horizontalSizeClass, .compact)
                    .environment(\.showsMenuButton, false)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background {
            // Invisible buttons that give each section a ⌘ shortcut.
            ForEach(Array(PhoneSection.allCases.enumerated()), id: \.element) { index, item in
                Button(item.rawValue) { destination = .section(item) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .hidden()
            }
        }
    }
}

private struct PhoneMenuRootView: View {
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @State private var destination = PhoneDestination.section(.home)
    @State private var menuOpen = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ZStack(alignment: .leading) {
                DestinationScreen(destination: destination)
                    .environment(\.openMenu, { withAnimation(.smooth(duration: 0.25)) { menuOpen = true } })
                    .id(destination)
                    .disabled(menuOpen)

                if menuOpen {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { closeMenu() }
                        .transition(.opacity)
                    menu
                        .transition(.move(edge: .leading))
                        .zIndex(1)
                }
            }
            .frame(maxWidth: 640)
            .environment(\.horizontalSizeClass, .compact)
        }
    }

    private func closeMenu() {
        withAnimation(.smooth(duration: 0.25)) { menuOpen = false }
    }

    private func row(_ title: String, subtitle: String? = nil, symbol: String, to target: PhoneDestination) -> some View {
        Button {
            destination = target
            closeMenu()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.caption).fontWeight(.regular).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
            }
            .font(.headline)
            .padding(12)
            .foregroundStyle(target == destination ? Color.accentColor : Color.primary)
            .background(target == destination ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var menu: some View {
        let accounts = allAccounts.live
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Piggybank Financial").lineLimit(1).minimumScaleFactor(0.6)
                        .font(.title2.bold())
                        .padding(.horizontal, 12)
                        .padding(.bottom, 16)
                    ForEach(PhoneSection.allCases) { item in
                        row(item.rawValue, symbol: item.symbol, to: .section(item))
                    }
                    if !accounts.isEmpty {
                        Text("ACCOUNTS")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 20)
                            .padding(.bottom, 4)
                        ForEach(accounts) { account in
                            if account.isLive {
                                row(account.name, subtitle: account.typeTitle, symbol: account.type.symbol, to: .account(account.id))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 60)
                .padding(.bottom, 20)
            }

            // Always on screen at the bottom of the menu, however many accounts there are.
            Divider()
            row("Manage Accounts", symbol: "gearshape.2", to: .manageAccounts)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground).ignoresSafeArea())
        .gesture(DragGesture().onEnded { if $0.translation.width < -40 { closeMenu() } })
    }
}

/// The Planning section: goals, and whatever planning tabs come next.
private struct PhonePlanningHost: View {
    var body: some View {
        NavigationStack {
            PlanningView()
                .navigationTitle("Planning")
                .menuButton()
        }
    }
}

/// The Bills tab.
private struct PhoneBillsHost: View {
    @State private var isPayingBill = false

    var body: some View {
        NavigationStack {
            BillsView()
                .navigationTitle("Bills")
                .menuButton()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Pay a Bill", systemImage: "creditcard") { isPayingBill = true }
                    }
                }
                .sheet(isPresented: $isPayingBill) { BillPayWindow() }
        }
    }
}

/// The Reports tab: income and spending reports, the liabilities overview, or investments.
private struct PhoneReportsHost: View {
    private enum Page: String, CaseIterable, Identifiable {
        case spending = "Spending", liabilities = "Liabilities", investments = "Investments"
        var id: Self { self }
    }

    @State private var page = Page.spending

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Report", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                switch page {
                case .spending: ReportsView()
                case .liabilities: LiabilitiesView()
                case .investments: InvestmentsView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
            .menuButton()
        }
    }
}
#endif
