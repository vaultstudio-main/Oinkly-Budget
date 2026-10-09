import SwiftUI
import SwiftData

private enum SidebarItem: Hashable {
    case summary
    case reports
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
        NavigationSplitView {
            List(selection: $selection) {
                Section("Overview") {
                    Label("Summary", systemImage: "building.columns")
                        .tag(SidebarItem.summary)
                    Label("Reports", systemImage: "chart.bar.xaxis")
                        .tag(SidebarItem.reports)
                }
                Section("Accounts") {
                    ForEach(AccountGroup.allCases) { group in
                        let members = accounts.filter { $0.type.group == group }
                        if !members.isEmpty {
                            DisclosureGroup(isExpanded: expansion(of: group)) {
                                ForEach(members) { account in
                                    if account.isLive {
                                    HStack {
                                        Label(account.name, systemImage: account.type.symbol)
                                        Spacer()
                                        Text(account.balance, format: .appCurrency)
                                            .foregroundStyle(.secondary)
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
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
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
            case .summary, nil:
                if accounts.isEmpty {
                    ContentUnavailableView("No Accounts", systemImage: "building.columns", description: Text("Open Settings (⌘,) ▸ Accounts to add one."))
                } else {
                    SummaryView()
                }
            }
        }
        .navigationTitle("Piggybank Financial")
        .onReceive(NotificationCenter.default.publisher(for: .piggybankWillDeleteAccounts)) { _ in selection = .summary }
        .focusedSceneValue(\.selectedAccountID, selectedAccountID)
        .preferredColorScheme(.dark)
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
