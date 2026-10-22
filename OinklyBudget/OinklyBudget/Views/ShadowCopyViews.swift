import SwiftUI
import SwiftData
import AppKit

// MARK: Status bar

/// The one status in the bottom bar for the data's safety: this Mac's database and the shadow copy together, in words and a
/// dot. Green when everything is saved and the shadow copy is up to date, yellow while something is being written,
/// orange when the shadow copy needs attention (including when it isn't set up), red when saving or copying keeps failing.
struct ShadowDatabaseStatusLabel: View {
    private var manager: ShadowCopyManager { ShadowCopyManager.shared }
    private var database: DatabaseStatus { DatabaseStatus.shared }
    @Environment(\.openSettings) private var openSettings

    static let name = "Shadow Copy Database"

    var body: some View {
        if !ScreenshotMode.isOn {
            Button { showShadowCopySettings() } label: {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    let look = Self.look(database: database.state, lastSaved: database.lastSaved, shadow: manager.status,
                                         sharing: SharedDataSession.shared.status != nil)
                    HStack(spacing: 5) {
                        Circle().fill(look.color).frame(width: 8, height: 8)
                        Text(look.text).foregroundStyle(.secondary)
                    }
                    .help(look.detail)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(look.text)
                    .accessibilityHint(look.detail)
                    .onAppear { manager.tick() }
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Opens Settings on Data & Backup and scrolls down to the Shadow Copy part.
    private func showShadowCopySettings() {
        UserDefaults.standard.set("data", forKey: MacSettingsView.tabKey)
        manager.revealRequested = true
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    struct Look {
        var color: Color
        var text: String
        var detail: String
    }

    /// What to show for this Mac's database and the shadow copy together. The worst of the two wins: a database problem,
    /// then a shadow copy that keeps failing, then a shadow copy that needs attention (not set up counts), then work in
    /// progress, then all well. While sharing, the sharing dot says whether the data is saved, so only a database problem
    /// counts here.
    static func look(database: DatabaseStatus.State, lastSaved: Date? = nil, shadow: ShadowCopyManager.Status, sharing: Bool, now: Date = .now) -> Look {
        if case .problem(let why) = database {
            return Look(color: Theme.red, text: "Database · Problem",
                        detail: "Your changes couldn't be saved: \(why) They are still in the app. Try again, or back up your data and restart.")
        }
        switch shadow {
        case .failed(let why):
            return Look(color: Theme.red, text: "Shadow Copy · Problem", detail: "Copying keeps failing: \(why) Your data is not affected.")
        case .notSetUp:
            return Look(color: .orange, text: "\(name) · Not set up",
                        detail: "A shadow copy keeps a second copy of your data in a folder you choose. Click to set it up.")
        case .folderMissing:
            return Look(color: .orange, text: "\(name) · Folder not found",
                        detail: "The folder for your shadow copy can't be found. It may be on a drive that isn't connected. Click to choose another.")
        case .otherData:
            return Look(color: .orange, text: "\(name) · Other data",
                        detail: "The shadow copy in that folder is of other data, so it was left alone. Click to start a new one.")
        case .behind(let when):
            let detail = when.map { "The last shadow copy was \($0.formatted(date: .abbreviated, time: .shortened)). Click to copy now." } ?? "No shadow copy has been made yet. Click to copy now."
            return Look(color: .orange, text: "\(name) · Out of date", detail: detail)
        case .copying:
            return Look(color: .yellow, text: "\(name) · Copying…", detail: "Your shadow copy is being updated.")
        case .upToDate(let when):
            if !sharing, case .unsaved = database {
                return Look(color: .yellow, text: "\(name) · Saving…", detail: "Your changes are being saved.")
            }
            let ago = RelativeDateTimeFormatter.shadow.localizedString(for: when, relativeTo: now)
            let saved = lastSaved.map { " Last saved on this Mac \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
            return Look(color: Theme.green, text: "\(name) · Copied \(ago)",
                        detail: "Everything is saved on this Mac and your shadow copy is up to date, copied \(when.formatted(date: .abbreviated, time: .shortened)).\(saved)")
        }
    }
}

extension RelativeDateTimeFormatter {
    static let shadow: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .numeric
        return formatter
    }()
}

// MARK: First time

/// Offered once the person has put some data in: what a shadow copy is, and that it is not encrypted.
struct ShadowSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Protect your data with a shadow copy", systemImage: "shield.lefthalf.filled")
                .font(.title3.weight(.semibold))
            Text("A shadow copy is a second copy of your data in a folder you choose, such as Documents. Oinkly Budget keeps it up to date on its own and keeps a few older versions. If your data ever goes missing or can't be opened, you can restore from it.")
            Text("It is kept in Oinkly Budget's own file format, so other apps can't read it, but it is not encrypted: that keeps out casual readers, not someone determined. A folder in iCloud Drive is also on Apple's servers. Choose somewhere you are comfortable with.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Don't Ask Again") { ShadowCopyManager.shared.stopAsking(); dismiss() }
                Spacer()
                Button("Not Now") { ShadowCopyManager.shared.snoozeAsking(); dismiss() }
                Button("Choose Folder…") {
                    dismiss()
                    ShadowCopyManager.shared.chooseFolder()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}

// MARK: Settings

/// Settings ▸ Data & Backup ▸ Shadow Copy.
struct ShadowCopySection: View {
    /// What Settings scrolls to when the status in the bottom bar is clicked.
    static let scrollID = "shadowCopySection"

    private var manager: ShadowCopyManager { ShadowCopyManager.shared }
    @State private var restoring = false
    @State private var confirmingOff = false

    var body: some View {
        Section {
            if manager.isSetUp {
                setUp
            } else {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep a Shadow Copy").font(.body.weight(.medium))
                        Text("A second copy of your data in a folder you choose, kept up to date on its own.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose Folder…") { manager.chooseFolder() }
                }
            }
        } header: {
            Text("Shadow Copy")
        } footer: {
            Text("The shadow copy is kept in Oinkly Budget's own file format, so other apps can't read it, but it is not encrypted: that keeps out casual readers, not someone determined. A folder in iCloud Drive is also on Apple's servers.")
        }
        .id(Self.scrollID)
        .task { await manager.reloadDetails() }
        .sheet(isPresented: $restoring) { ShadowRestoreSheet() }
        .confirmationDialog("Turn off the shadow copy?", isPresented: $confirmingOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { manager.turnOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Oinkly Budget stops updating it. What is already in the folder stays there.")
        }
    }

    @ViewBuilder
    private var setUp: some View {
        Label(statusText, systemImage: statusSymbol).foregroundStyle(statusColor)
        if let path = manager.folderPath { LabeledContent("Folder", value: path) }
        if let last = manager.lastCopy { LabeledContent("Last copied", value: last.formatted(date: .abbreviated, time: .shortened)) }
        if manager.versionCount > 0 {
            LabeledContent("Kept", value: "\(manager.versionCount) cop\(manager.versionCount == 1 ? "y" : "ies"), \(ByteCountFormatter.string(fromByteCount: manager.size, countStyle: .file))")
        }
        if case .otherData = manager.status {
            Button("Start a New Shadow Copy Here", role: .destructive) { Task { await manager.replaceExisting() } }
        }
        if SharedDataSession.isEnabled {
            Text("While sharing, the shadow copy is made from the shared data each time it is saved.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        HStack {
            Button("Copy Now") { Task { await manager.copyNow(onlyIfChanged: false) } }
            Button("Show in Finder") { manager.revealInFinder() }
            Button("Restore…") { restoring = true }.disabled(SharedDataSession.isEnabled)
            Button("Change Folder…") { manager.chooseFolder() }
            Spacer()
            Button("Turn Off…", role: .destructive) { confirmingOff = true }
        }
    }

    private var statusText: String {
        switch manager.status {
        case .notSetUp: "Not set up"
        case .copying: "Copying…"
        case .upToDate: "Up to date"
        case .behind: "Out of date: changes are waiting to be copied"
        case .folderMissing: "The folder can't be found"
        case .otherData: "The shadow copy in that folder is of other data"
        case .failed(let why): "Copying keeps failing: \(why)"
        }
    }

    private var statusSymbol: String {
        switch manager.status {
        case .upToDate: "checkmark.circle.fill"
        case .copying: "arrow.triangle.2.circlepath"
        case .failed: "xmark.octagon.fill"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch manager.status {
        case .upToDate: Theme.green
        case .copying: .yellow
        case .failed: Theme.red
        default: .orange
        }
    }
}

/// The copies in the shadow folder, newest first, each with a button to restore it.
struct ShadowRestoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [ShadowVersion]?
    @State private var good: Set<URL> = []
    @State private var choice: ShadowVersion?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore from the shadow copy").font(.title3.weight(.semibold))
            Text("This replaces the data on this Mac with the copy you choose. What is there now is kept first in Application Support ▸ Backups.")
                .font(.callout).foregroundStyle(.secondary)
            if let versions {
                if versions.isEmpty {
                    Text("There are no copies in the shadow folder yet.")
                } else {
                    List(versions) { version in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(version.info.savedAt.formatted(date: .abbreviated, time: .shortened) + (version.isLatest ? " (latest)" : ""))
                                    .font(.body.weight(.medium))
                                Text("\(version.info.accounts) accounts, \(version.info.transactions.formatted()) transactions · \(version.info.source)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if good.contains(version.url) {
                                Button("Restore…") { choice = version }
                            } else {
                                Text("Checking…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 260)
                }
            } else {
                ProgressView("Looking…")
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await load() }
        .confirmationDialog("Restore this copy?", isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } }), titleVisibility: .visible) {
            Button("Restore and Restart", role: .destructive) {
                if let choice, ShadowCopyManager.shared.requestRestore(choice) { dismiss() }
            }
            Button("Cancel", role: .cancel) { choice = nil }
        } message: {
            if let choice {
                Text("Your data becomes the copy from \(choice.info.savedAt.formatted(date: .abbreviated, time: .shortened)). Anything you did after that is not in it. A copy of the current data is kept first.")
            }
        }
    }

    private func load() async {
        guard let parent = ShadowCopyManager.shared.resolveParent() else { versions = []; return }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        let folder = ShadowFolder(inside: parent)
        let all = await Task.detached { folder.allVersions() }.value
        versions = all
        for version in all {
            let ok = await Task.detached { folder.isGood(version) }.value
            if ok { good.insert(version.url) }
        }
    }
}

// MARK: When something looks wrong at start-up

/// Shown instead of the app when the shadow copy and the data disagree in a way that needs a decision: the data looks
/// empty or much smaller than the shadow copy, or can't be read. Nothing is opened or changed until the person chooses.
struct ShadowRescueView: View {
    let finding: ShadowFinding

    @State private var best: ShadowVersion?
    @State private var versions: [ShadowVersion] = []
    @State private var loaded = false

    var body: some View {
        ZStack {
            Brand.gradient.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("BootPig").resizable().scaledToFit().frame(height: 70).shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                Text("Oinkly Budget").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(finding.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(explanation).font(.callout).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center).frame(maxWidth: 400)
                if let best {
                    Text("Newest good shadow copy: \(best.info.savedAt.formatted(date: .abbreviated, time: .shortened)), with \(best.info.accounts) accounts and \(best.info.transactions.formatted()) transactions.")
                        .font(.callout.weight(.medium)).foregroundStyle(.white).multilineTextAlignment(.center).frame(maxWidth: 400)
                } else if loaded {
                    Text("No good copy was found in the shadow folder.").font(.callout.weight(.medium)).foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
                buttons
            }
            .padding(30)
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var explanation: String {
        switch finding {
        case .dataLooksEmpty(let accounts, let transactions):
            "There is nothing in your data, but the shadow copy has \(accounts) accounts and \(transactions.formatted()) transactions. The data may have been erased or lost."
        case .dataMuchSmaller(let have, let shadow):
            "Your data has \(have.formatted()) transactions and the shadow copy has \(shadow.formatted()). Something may have gone missing."
        case .dataUnreadable(let why):
            "Oinkly Budget couldn't read your data (\(why)). Nothing has been changed."
        case .otherData:
            "The shadow copy in your folder is of other data."
        default:
            ""
        }
    }

    private var canKeepOpening: Bool {
        if case .dataUnreadable = finding { return false }
        return true
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 10) {
            if let best {
                Button("Restore It") { _ = ShadowCopyManager.shared.requestRestore(best, countdown: false) }.keyboardShortcut(.defaultAction)
            }
            if versions.count > 1 {
                Menu("Choose an Older Copy") {
                    ForEach(versions) { version in
                        Button("\(version.info.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(version.info.transactions.formatted()) transactions") {
                            _ = ShadowCopyManager.shared.requestRestore(version, countdown: false)
                        }
                    }
                }
                .fixedSize()
            }
            if canKeepOpening {
                Button("Keep My Data As It Is") {
                    UserDefaults.standard.set(true, forKey: ShadowCopyManager.skipCheckKey)
                    AppStore.relaunch()
                }
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
    }

    private func load() async {
        let all = await ShadowCopyManager.shared.versions()
        versions = all
        guard let parent = ShadowCopyManager.shared.resolveParent() else { loaded = true; return }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        let folder = ShadowFolder(inside: parent)
        best = await Task.detached { folder.newestGoodVersion() }.value
        loaded = true
    }
}

#if DEBUG
enum ShadowViewsCheck {
    /// `-shadowCheck <folder>` draws the status label in each state, the first-time sheet and the rescue screen into PNG
    /// files and quits. Debug only.
    @MainActor
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "-shadowCheck"), flag + 1 < arguments.count else { return }
        let folder = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func save(_ view: some View, _ name: String) {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: folder.appendingPathComponent("shadow-\(name).png"))
            }
        }
        let up = ShadowCopyManager.Status.upToDate(.now.addingTimeInterval(-300))
        let looks: [ShadowDatabaseStatusLabel.Look] = [
            ShadowDatabaseStatusLabel.look(database: .saved, shadow: up, sharing: false),
            ShadowDatabaseStatusLabel.look(database: .unsaved, shadow: up, sharing: false),
            ShadowDatabaseStatusLabel.look(database: .saved, shadow: .copying, sharing: false),
            ShadowDatabaseStatusLabel.look(database: .saved, shadow: .notSetUp, sharing: false),
            ShadowDatabaseStatusLabel.look(database: .saved, shadow: .behind(.now.addingTimeInterval(-7200)), sharing: false),
            ShadowDatabaseStatusLabel.look(database: .saved, shadow: .folderMissing, sharing: false),
            ShadowDatabaseStatusLabel.look(database: .saved, shadow: .otherData, sharing: false),
            ShadowDatabaseStatusLabel.look(database: .saved, shadow: .failed("the disk is full."), sharing: false),
            ShadowDatabaseStatusLabel.look(database: .problem("the disk is full."), shadow: up, sharing: false),
            ShadowDatabaseStatusLabel.look(database: .unsaved, shadow: up, sharing: true),
        ]
        let bar = VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(looks.enumerated()), id: \.offset) { _, look in
                HStack(spacing: 5) { Circle().fill(look.color).frame(width: 8, height: 8); Text(look.text).foregroundStyle(.secondary) }.font(.caption)
            }
        }.padding(16).frame(width: 340, alignment: .leading).background(Color(white: 0.96))
        save(bar, "labels")
        save(ShadowSetupSheet().background(Color(white: 0.96)), "setup")
        save(ShareSetupSheet(onShare: {}).background(Color(white: 0.96)), "share")
        save(ShadowRescueView(finding: .dataLooksEmpty(shadowAccounts: 6, shadowTransactions: 1_240)).frame(width: 500, height: 480), "rescue")
        exit(0)
    }
}
#endif
