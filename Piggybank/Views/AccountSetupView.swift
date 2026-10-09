import SwiftUI
import SwiftData

/// Shown after the splash when the app has no accounts yet.
/// Lets you add every kind of account, then continue into the app.
struct AccountSetupView: View {
    let onFinish: () -> Void

    @Query(sort: \Account.name) private var allAccounts: [Account]

    private var accounts: [Account] { allAccounts.live }
    @State private var newAccountType: AccountType?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                VStack(alignment: .leading, spacing: 22) {
                    ForEach(AccountGroup.setupOrder) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: typeColumns, spacing: 12) {
                                ForEach(group.accountTypes) { type in
                                    Button { newAccountType = type } label: { typeCard(type) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if !accounts.isEmpty { addedAccounts }

                VStack(spacing: 10) {
                    Button(action: onFinish) {
                        Text(accounts.isEmpty ? "Add an account to continue" : "Done")
                            .frame(maxWidth: 320)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(accounts.isEmpty)

                    Button("Skip for now", action: onFinish)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(background)
        .sheet(item: $newAccountType) { AccountEditView(account: nil, initialType: $0) }
    }

    /// One column on iPhone and iPad so they match; two on the wide Mac window.
    private var typeColumns: [GridItem] {
        #if os(iOS)
        [GridItem(.flexible())]
        #else
        [GridItem(.adaptive(minimum: 240), spacing: 12)]
        #endif
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.pink)
            Text("Let's set up your accounts")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Pick a type to add it. Add everything you want to track: bank accounts, cards, investments, property and loans. You can add more any time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    private func typeCard(_ type: AccountType) -> some View {
        let isDebt = type.group.isLiability
        return HStack(spacing: 14) {
            Image(systemName: type.symbol)
                .font(.title2)
                .foregroundStyle(isDebt ? Color.red : Color.green)
                .frame(width: 44, height: 44)
                .background((isDebt ? Color.red : Color.green).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(type.title).font(.headline)
                Text(type.blurb).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(isDebt ? "Debt" : "Asset")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isDebt ? Color.red : Color.green)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private var addedAccounts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADDED").font(.caption).foregroundStyle(.secondary)
            ForEach(accounts) { account in
                if account.isLive {
                HStack(spacing: 12) {
                    Image(systemName: account.type.symbol)
                        .foregroundStyle(account.isDebt ? Color.red : Color.green)
                        .frame(width: 28)
                    VStack(alignment: .leading) {
                        Text(account.name).font(.headline)
                        Text(account.type.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(account.balance, format: .appCurrency)
                }
                .padding(12)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var maxContentWidth: CGFloat {
        #if os(iOS)
        560
        #else
        780
        #endif
    }

    private var background: Color {
        #if os(macOS)
        Theme.background
        #else
        Color(.systemGroupedBackground)
        #endif
    }
}
