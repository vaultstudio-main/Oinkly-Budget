import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Shown after the splash when the app has no accounts yet.
/// Lets you add every kind of account, then continue into the app.
struct AccountSetupView: View {
    let onFinish: () -> Void
    /// What Skip for now does; without one, it finishes like Done.
    var onSkip: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var allAccounts: [Account]

    /// Only accounts added here. Cash on Hand is built in.
    private var accounts: [Account] { allAccounts.live.addedByUser }
    @State private var shadowProblem: String?

    var body: some View {
        wideBody
    }

    // MARK: Mac: the whole window, so there is nothing to scroll

    /// The same tabbed list as Manage Accounts: a tab for each group, a smaller tab for each type under it, and Add Account at the
    /// bottom. The way forward sits in the bottom bar beside it.
    private var wideBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let's set up your accounts")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Pick a tab for the kind of account, then Add Account. Add everything you want to track. You can add more any time.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 10)

            AccountTabsView {
                if let shadowProblem {
                    Text(shadowProblem).font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
                Text("\(accounts.count) added").font(.callout).foregroundStyle(.secondary)
                Button {
                    restoreAnything()
                } label: {
                    Label("Restore…", systemImage: "square.and.arrow.down")
                }
                .help("Already have your data saved? Bring it back from a .pig file, a .pigdata copy, or the folder that holds your backup copy.")
                Button("Skip for now") { (onSkip ?? onFinish)() }
                Button(action: onFinish) {
                    Text(accounts.isEmpty ? "Add an account to continue" : "Done")
                }
                .buttonStyle(.borderedProminent)
                .disabled(accounts.isEmpty)
            }
        }
        .background(background)
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
            show("Couldn't restore that backup", error.localizedDescription)
        }
    }

    private var background: Color {
        Theme.background
    }
}
