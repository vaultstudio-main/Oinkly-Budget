import SwiftUI
import SwiftData

private enum SidebarItem: Hashable {
    case summary
    case reports
    case liabilities
    case investments
    case bills
    case planning
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

    private var selectedAccountID: Account.ID? {
        if case .account(let id) = selection { id } else { nil }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                Section("Overview") {
                    Label("Summary", systemImage: "building.columns")
                        .tag(SidebarItem.summary)
                    Label("Transactions", systemImage: "list.bullet.rectangle")
                        .tag(SidebarItem.transactions)
                    Label("Reports", systemImage: "chart.bar.xaxis")
                        .tag(SidebarItem.reports)
                    Label("Liabilities", systemImage: "scalemass")
                        .tag(SidebarItem.liabilities)
                    Label("Investments", systemImage: "chart.line.uptrend.xyaxis")
                        .tag(SidebarItem.investments)
                    Label("Bills", systemImage: "calendar")
                        .tag(SidebarItem.bills)
                    Label("Planning", systemImage: "target")
                        .tag(SidebarItem.planning)
                }
                Section("Accounts") {
                    // Cash on hand sits at the top by itself, not inside a folder.
                    ForEach(accounts.filter(\.isCashOnHand)) { account in
                        if account.isLive {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.name)
                                    Text(account.typeTitle).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: account.type.symbol)
                            }
                            .tag(SidebarItem.account(account.id))
                            .contextMenu {
                                Button("Edit Details…") { editingAccount = account }
                            }
                        }
                    }
                    ForEach(AccountGroup.allCases) { group in
                        let members = accounts.filter { $0.type.group == group && !$0.isCashOnHand }
                        if !members.isEmpty {
                            DisclosureGroup(isExpanded: expansion(of: group)) {
                                ForEach(members) { account in
                                    if account.isLive {
                                    Label {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(account.name)
                                            Text(account.typeTitle).font(.caption).foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: account.type.symbol)
                                    }
                                    .tag(SidebarItem.account(account.id))
                                    .contextMenu {
                                        Button("Edit Details…") { editingAccount = account }
                                    }
                                    }
                                }
                            } label: {
                                Label(group.title, systemImage: "folder")
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
            .navigationSplitViewColumnWidth(300)
            .toolbar(removing: .sidebarToggle)
        } detail: {
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
            case .manageAccounts:
                VStack(alignment: .leading, spacing: 0) {
                    Text("Manage Accounts").font(.largeTitle.bold()).padding([.top, .horizontal], 16)
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
        .navigationTitle("Piggybank Budgeting")
        .onReceive(NotificationCenter.default.publisher(for: .piggybankOpenPage)) { note in
            switch note.userInfo?["page"] as? String {
            case "summary": selection = .summary
            case "transactions": selection = .transactions
            case "reports": selection = .reports
            case "bills": selection = .bills
            case "planning": selection = .planning
            case "liabilities": selection = .liabilities
            case "investments": selection = .investments
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .piggybankWillDeleteAccounts)) { _ in selection = .summary }
        .focusedSceneValue(\.selectedAccountID, selectedAccountID)
        .appAppearance()
        .sheet(item: $editingAccount) { AccountEditView(account: $0) }
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
