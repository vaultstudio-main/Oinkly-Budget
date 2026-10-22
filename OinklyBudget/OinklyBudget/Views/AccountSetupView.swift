import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Shown after the splash when the app has no accounts yet.
/// Lets you add every kind of account, then continue into the app.
struct AccountSetupView: View {
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var allAccounts: [Account]

    /// Only accounts added here. Cash on Hand is built in.
    private var accounts: [Account] { allAccounts.live.addedByUser }
    @State private var newAccountType: AccountType?
    @State private var shadowProblem: String?

    var body: some View {
        wideBody
    }

    // MARK: Mac: the whole window, so there is little to scroll

    /// Account types in columns across the window, with what has been added and the way forward in a side panel.
    private var wideBody: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let's set up your accounts")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Pick a type to add it. Add everything you want to track. You can add more any time.")
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 290, maximum: 460), spacing: 20, alignment: .top)],
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(AccountGroup.setupOrder) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.title.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, 2)
                                ForEach(group.accountTypes.filter { $0 != .cash }) { type in
                                    Button { newAccountType = type } label: { compactCard(type) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("ADDED (\(accounts.count))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                if accounts.isEmpty {
                    Text("Nothing yet. Pick an account type to start.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(accounts) { account in
                                if account.isLive {
                                    HStack(spacing: 10) {
                                        Image(systemName: account.type.symbol)
                                            .foregroundStyle(account.isDebt ? Color.red : Color.green)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(account.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            Text(account.typeTitle).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 4)
                                        Text(account.balance, format: .appCurrency).font(.callout)
                                    }
                                    .padding(10)
                                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    Button(action: onFinish) {
                        Text(accounts.isEmpty ? "Add an account to continue" : "Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(accounts.isEmpty)

                    Button("Skip for now", action: onFinish)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                    Divider().padding(.vertical, 4)

                    Button {
                        restoreAnything()
                    } label: {
                        Label("Restore…", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .help("Bring back your data from a .pig file, a .pigdata copy, or the folder that holds your backup copy")

                    Text("Already have your data saved? Restore it from a .pig file, a copy, or your backup copy folder instead of adding accounts by hand.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let shadowProblem {
                        Text(shadowProblem).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                }
            }
            .padding(20)
            .frame(width: 300)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(background)
        .sheet(item: $newAccountType) { AccountEditView(account: nil, initialType: $0) }
    }

    /// One way in for everything: a .pig file, a .pigdata copy, or the folder that holds a backup copy.
    private func restoreAnything() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data, .folder]
        panel.message = "Choose a .pig file, a .pigdata copy, or the folder that contains “\(ShadowFolder.folderName)”."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        if isFolder.boolValue {
            if let problem = ShadowCopyManager.shared.restoreFromFolder(url) { shadowProblem = problem }
        } else if url.pathExtension.lowercased() == SealedFile.fileExtension {
            Task { await CopyOpener.offerRestore(of: url) }
        } else {
            restoreFromFile(url)
        }
    }

    /// Brings everything back from a .pig file, then goes straight into the app.
    private func restoreFromFile(_ url: URL) {

        func show(_ title: String, _ text: String) {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = text
            alert.runModal()
        }

        do {
            let file = try DataBackup.decode(try Data(contentsOf: url))
            try DataBackup.restore(file, into: modelContext)
            modelContext.saveNow()
            onFinish()
        } catch {
            modelContext.rollback()
            show("Couldn't import that file", error.localizedDescription)
        }
    }

    /// A shorter version of the type card, so more of them fit on screen.
    private func compactCard(_ type: AccountType) -> some View {
        let isDebt = type.group.isLiability
        return HStack(spacing: 10) {
            Image(systemName: type.symbol)
                .font(.callout)
                .foregroundStyle(isDebt ? Color.red : Color.green)
                .frame(width: 30, height: 30)
                .background((isDebt ? Color.red : Color.green).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(type.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(type.blurb).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    private var background: Color {
        Theme.background
    }
}
