import SwiftUI
import SwiftData

private enum SidebarItem: Hashable {
    case summary
    case reports
    case liabilities
    case investments
    case bills
    case planning
    case budgets
    case manageAccounts
    case transactions
    case account(Account.ID)
}

struct MacRootView: View {
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    @State private var selection: SidebarItem? = .summary
    @State private var collapsed = Set<AccountGroup>()
    @State private var editingAccount: Account?
    @State private var askingForShadowCopy = false
    @Environment(\.modelContext) private var modelContext

    private var selectedAccountID: Account.ID? {
        if case .account(let id) = selection { id } else { nil }
    }

    var body: some View {
        // A plain row, not a split view: a split view's side panel can be hidden, and a hidden panel left people with no
        // way to reach their accounts. This one has nothing to collapse.
        HStack(spacing: 0) {
            List(selection: $selection) {
                Section("Overview") {
                    SidebarLabel(title: "Summary", symbol: "building.columns", color: .blue)
                        .tag(SidebarItem.summary)
                    SidebarLabel(title: "Transactions", symbol: "list.bullet.rectangle", color: .teal)
                        .tag(SidebarItem.transactions)
                    SidebarLabel(title: "Reports", symbol: "chart.bar.xaxis", color: .indigo)
                        .tag(SidebarItem.reports)
                    SidebarLabel(title: "Liabilities", symbol: "scalemass", color: Theme.red)
                        .tag(SidebarItem.liabilities)
                    SidebarLabel(title: "Investments", symbol: "chart.line.uptrend.xyaxis", color: .purple)
                        .tag(SidebarItem.investments)
                    SidebarLabel(title: "Bills & Recurring", symbol: "calendar", color: .orange)
                        .tag(SidebarItem.bills)
                    SidebarLabel(title: "Planning", symbol: "target", color: Theme.green)
                        .tag(SidebarItem.planning)
                    SidebarLabel(title: "Budgets", symbol: "chart.pie", color: .pink)
                        .tag(SidebarItem.budgets)
                }
                Section("Accounts") {
                    // Cash on hand sits at the top by itself, not inside a folder, and the primary checking account
                    // is pinned right under it.
                    ForEach(accounts.filter(\.isCashOnHand)) { sidebarRow($0) }
                    ForEach(accounts.filter { PrimaryChecking.isPrimary($0) && !$0.isCashOnHand }) { sidebarRow($0) }
                    ForEach(AccountGroup.allCases) { group in
                        let members = accounts.filter {
                            $0.type.group == group && !$0.isCashOnHand && !PrimaryChecking.isPrimary($0)
                        }
                        if !members.isEmpty {
                            DisclosureGroup(isExpanded: expansion(of: group)) {
                                ForEach(members) { sidebarRow($0) }
                            } label: {
                                SidebarLabel(title: group.title, symbol: "folder", color: group.sidebarColor)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            // Always visible at the bottom of the side panel, however long the account list gets.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        selection = .manageAccounts
                    } label: {
                        Label("Manage Accounts", systemImage: "gearshape.2")
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(selection == .manageAccounts ? Color.accentColor.opacity(0.2) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .background(.bar)
            }
            .frame(width: 300)

            Divider()

            StatusBarHost(fallback: pageName, page: detailPage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 600)
        .navigationTitle("Oinkly Budget")
        // The name sits in the middle of the top bar, matching the bar along the bottom.
        .toolbar(removing: .title)
        // A solid bar, so nothing scrolls under it and shows through.
        .toolbarBackground(Theme.background, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar { AppNameToolbarItem() }
        .onReceive(NotificationCenter.default.publisher(for: .piggybankOpenPage)) { note in
            if let name = note.userInfo?["account"] as? String, let account = accounts.first(where: { $0.name == name }) {
                selection = .account(account.id)
                return
            }
            switch note.userInfo?["page"] as? String {
            case "summary": selection = .summary
            case "transactions": selection = .transactions
            case "reports": selection = .reports
            case "bills": selection = .bills
            case "planning": selection = .planning
            case "budgets": selection = .budgets
            case "liabilities": selection = .liabilities
            case "investments": selection = .investments
            case "manageAccounts": selection = .manageAccounts
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .piggybankWillDeleteAccounts)) { _ in selection = .summary }
        .onAppear {
            // A reminder or widget was clicked while there was no window: go where it pointed.
            if let page = StartupState.pendingPage {
                StartupState.pendingPage = nil
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .piggybankOpenPage, object: nil, userInfo: ["page": page])
                }
            }
        }
        // Coming back to the app after a day or more adds anything that has come due.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Recurring.run(in: modelContext)
        }
        .focusedSceneValue(\.selectedAccountID, selectedAccountID)
        .appAppearance()
        .sheet(item: $editingAccount) { AccountEditView(account: $0) }
        .sheet(isPresented: $askingForShadowCopy) { ShadowSetupSheet() }
        .task {
            // Once there is some data in, offer a backup copy. Waits so it doesn't land on top of the start-up.
            try? await Task.sleep(for: .seconds(8))
            if ShadowCopyManager.shared.shouldAsk(hasData: !accounts.live.addedByUser.isEmpty) {
                ShadowCopyManager.shared.markAsked()
                askingForShadowCopy = true
            }
        }
    }

    @ViewBuilder
    private var detailPage: some View {
        switch selection {
        case .account(let id):
            if let account = accounts.first(where: { $0.id == id }) {
                RegisterView(account: account).id(id)
            } else {
                SummaryView()
            }
        case .reports:
            ReportsView()
        case .liabilities:
            LiabilitiesView()
        case .investments:
            InvestmentsView()
        case .bills:
            BillsView()
        case .planning:
            PlanningView()
        case .budgets:
            BudgetsView()
        case .manageAccounts:
            VStack(alignment: .leading, spacing: 0) {
                PinnedHeader("Manage Accounts")
                AccountsSettingsView()
            }
            .background(Theme.background)
        case .transactions:
            TransactionsView()
        case .summary, nil:
            if accounts.isEmpty {
                ContentUnavailableView("No Accounts", systemImage: "building.columns", description: Text("Open Settings (⌘,) ▸ Accounts to add one."))
            } else {
                SummaryView()
            }
        }
    
    }

    @ViewBuilder
    private func sidebarRow(_ account: Account) -> some View {
        if account.isLive {
            let isPrimary = PrimaryChecking.isPrimary(account)
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name)
                    Text(isPrimary ? "Primary Checking" : account.typeTitle)
                        .font(.caption.weight(isPrimary ? .semibold : .regular))
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: account.type.symbol).foregroundStyle(account.type.group.sidebarColor)
            }
            .tag(SidebarItem.account(account.id))
            .contextMenu {
                Button("Edit Details") { editingAccount = account }
                if account.type == .checking {
                    if isPrimary {
                        Button("Remove Primary Checking") { PrimaryChecking.set(nil, in: modelContext); modelContext.saveNow() }
                    } else {
                        Button("Make Primary Checking") { PrimaryChecking.set(account, in: modelContext); modelContext.saveNow() }
                    }
                }
            }
        }
    }

    private var pageName: String {
        switch selection {
        case .account(let id): accounts.first { $0.id == id }?.name ?? "Summary"
        case .reports: "Reports"
        case .liabilities: "Liabilities"
        case .investments: "Investments"
        case .bills: "Bills & Recurring"
        case .planning: "Planning"
        case .budgets: "Budgets"
        case .manageAccounts: "Manage Accounts"
        case .transactions: "Transactions"
        case .summary, nil: "Summary"
        }
    }

    private func expansion(of group: AccountGroup) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(group) },
            set: { if $0 { collapsed.remove(group) } else { collapsed.insert(group) } }
        )
    }
}

#Preview {
    MacRootView()
        .modelContainer(for: [Account.self, Category.self, Transaction.self, Payee.self], inMemory: true)
}

/// The app's name in the middle of the top bar. Newer macOS puts toolbar items in a glass capsule, which would make
/// a plain name look like a button, so the capsule is turned off there.
private struct AppNameToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) { name }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { name }
        }
    }

    private var name: some View {
        Text("Oinkly Budget").font(.headline).foregroundStyle(.secondary)
    }
}

/// A side panel row with a coloured icon.
private struct SidebarLabel: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
    }
}

extension AccountGroup {
    /// The colour of this kind of account in the side panel: money you have is green, debts are red.
    var sidebarColor: Color {
        switch self {
        case .checkingSavings: Theme.green
        case .creditCards: .orange
        case .loans: Theme.red
        case .investments: .purple
        case .assets: .teal
        }
    }
}
