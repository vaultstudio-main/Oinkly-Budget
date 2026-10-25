import SwiftUI
import SwiftData
import AppKit

// MARK: Status bar

/// The one status in the bottom bar for the data's safety: this Mac's database and the backup copy together, in words and a
/// dot. Green when everything is saved and the backup copy is up to date, yellow while something is being written,
/// orange when the backup copy needs attention (including when it isn't set up), red when saving or copying keeps failing.
struct ShadowDatabaseStatusLabel: View {
    private var manager: ShadowCopyManager { ShadowCopyManager.shared }
    private var database: DatabaseStatus { DatabaseStatus.shared }
    @Environment(\.openSettings) private var openSettings

    static let name = "Backup Copy Database"

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

    /// Opens Settings on Data & Backup and scrolls down to the Backup Copy part.
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

    /// What to show for this Mac's database and the backup copy together. The worst of the two wins: a database problem,
    /// then a backup copy that keeps failing, then a backup copy that needs attention (not set up counts), then work in
    /// progress, then all well. While sharing, the sharing dot says whether the data is saved, so only a database problem
    /// counts here.
    static func look(database: DatabaseStatus.State, lastSaved: Date? = nil, shadow: ShadowCopyManager.Status, sharing: Bool, now: Date = .now) -> Look {
        if case .problem(let why) = database {
            return Look(color: Theme.red, text: "Database · Problem",
                        detail: "Your changes couldn't be saved: \(why) They are still in the app. Try again, or back up your data and restart.")
        }
        switch shadow {
        case .failed(let why):
            return Look(color: Theme.red, text: "Backup Copy · Problem", detail: "Copying keeps failing: \(why) Your data is not affected.")
        case .notSetUp:
            return Look(color: .orange, text: "\(name) · Not set up",
                        detail: "A backup copy keeps a second copy of your data in a folder you choose. Click to set it up.")
        case .folderMissing:
            return Look(color: .orange, text: "\(name) · Folder not found",
                        detail: "The folder for your backup copy can't be found. It may be on a drive that isn't connected. Click to choose another.")
        case .otherData:
            return Look(color: .orange, text: "\(name) · Other data",
                        detail: "The backup copy in that folder is of other data, so it was left alone. Click to start a new one.")
        case .behind(let when):
            let detail = when.map { "The last backup copy was \($0.formatted(date: .abbreviated, time: .shortened)). Click to copy now." } ?? "No backup copy has been made yet. Click to copy now."
            return Look(color: .orange, text: "\(name) · Out of date", detail: detail)
        case .copying:
            return Look(color: .yellow, text: "\(name) · Copying…", detail: "Your backup copy is being updated.")
        case .upToDate(let when):
            if !sharing, case .unsaved = database {
                return Look(color: .yellow, text: "\(name) · Saving…", detail: "Your changes are being saved.")
            }
            let ago = RelativeDateTimeFormatter.shadow.localizedString(for: when, relativeTo: now)
            let saved = lastSaved.map { " Last saved on this Mac \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
            return Look(color: Theme.green, text: "\(name) · Copied \(ago)",
                        detail: "Everything is saved on this Mac and your backup copy is up to date, copied \(when.formatted(date: .abbreviated, time: .shortened)).\(saved)")
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

/// Offered once the person has put some data in: choose a default save location, which is also where a backup copy of the data is kept,
/// and that the copy is not encrypted.
struct ShadowSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Choose where your files are saved", systemImage: "folder.badge.gearshape")
                .font(.title3.weight(.semibold))
            Text("Pick a default save location, such as a folder in Documents. Statements, reports and backups are then saved straight into it, with no save window to go through each time.")
            Text("A backup copy of your data keeps itself up to date in the same folder, with a few older versions. It is the best thing you can do to make sure your data is safe: if your data ever goes missing or can't be opened, you can restore from it.")
            Text("The backup copy is kept in Oinkly Budget's own file format, so other apps can't read it, but it is not encrypted: that keeps out casual readers, not someone determined. A folder in iCloud Drive is also on Apple's servers. Choose somewhere you are comfortable with. You can change or turn off either one later in Settings ▸ Data & Backup.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Don't Ask Again") { ShadowCopyManager.shared.stopAsking(); dismiss() }
                Spacer()
                Button("Not Now") { dismiss() }
                Button("Choose Folder…") {
                    dismiss()
                    if DefaultSaveFolder.choose(), let folder = DefaultSaveFolder.url { ShadowCopyManager.shared.setUp(in: folder) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}

// MARK: Settings

/// Settings ▸ Data & Backup ▸ Backup Copy and Save Location: the folder save windows open in, a switch for keeping a Backup Copy of the
/// data there, and when it is on, whether it is up to date, where it is kept and when it was last copied. Choosing a save location turns
/// the Backup Copy on. Turning it off asks whether to delete its folder too.
struct ShadowCopySection: View {
    /// What Settings scrolls to when the status in the bottom bar is clicked.
    static let scrollID = "shadowCopySection"

    private var manager: ShadowCopyManager { ShadowCopyManager.shared }
    @State private var restoring = false
    @State private var confirmingOff = false
    @State private var saveName = DefaultSaveFolder.displayName

    var body: some View {
        Section {
            Toggle("Use a default save location", isOn: Binding(
                get: { saveName != nil },
                set: { wantsOn in
                    if wantsOn { chooseSaveLocation() } else { DefaultSaveFolder.clear(); saveName = nil }
                }))
            if let saveName {
                LabeledContent("Save Location") {
                    HStack(spacing: 10) {
                        Label(saveName, systemImage: "folder").lineLimit(1)
                        Button("Change…") { chooseSaveLocation() }
                    }
                }
            }
            Toggle("Keep a Backup Copy of my data", isOn: Binding(
                get: { manager.isOn },
                set: { wantsOn in
                    if !wantsOn { confirmingOff = true }
                    else if let folder = DefaultSaveFolder.url { manager.setUp(in: folder) }
                    else { manager.chooseFolder() }
                }))
            if manager.isOn { details }
        } header: {
            Text("Backup Copy and Save Location")
        } footer: {
            Text("With a save location, statements, reports and backups are saved straight into that folder with no save window, named by Oinkly Budget, and the folder opens in Finder. Choosing one also keeps a Backup Copy of your whole database in it, a second copy that is kept up to date on its own, in Oinkly Budget's own file format and not encrypted. Turn it off to be asked where to save each time. Turn the Backup Copy switch off to keep the save location without the copy.")
        }
        .id(Self.scrollID)
        .task { await manager.reloadDetails() }
        .sheet(isPresented: $restoring) { ShadowRestoreSheet() }
        .confirmationDialog("Turn off the backup copy?", isPresented: $confirmingOff, titleVisibility: .visible) {
            Button("Turn Off and Delete the Folder", role: .destructive) { manager.turnOffAndDeleteFolder() }
            Button("Turn Off and Keep the Folder") { manager.turnOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you also want to delete the “\(ShadowFolder.folderName)” folder? It holds your latest copy and its older versions. Deleting moves it to the Trash.")
        }
    }

    /// Asks for the save location. The Backup Copy starts there too, unless one is already kept somewhere else.
    private func chooseSaveLocation() {
        guard DefaultSaveFolder.choose() else { return }
        saveName = DefaultSaveFolder.displayName
        if !manager.isOn, let folder = DefaultSaveFolder.url { manager.setUp(in: folder) }
    }

    @ViewBuilder
    private var details: some View {
        LabeledContent("Status") {
            Label(statusText, systemImage: statusSymbol).foregroundStyle(statusColor)
        }
        LabeledContent("Folder", value: manager.folderPath ?? "Can't be found")
        LabeledContent("Last copied", value: manager.lastCopy.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
        if case .otherData = manager.status {
            Button("Start a New Backup Copy Here", role: .destructive) { Task { await manager.replaceExisting() } }
        }
        if SharedDataSession.isEnabled {
            Text("While sharing, the backup copy is made from the shared data each time it is saved.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        HStack {
            Button("Copy Now") { Task { await manager.copyNow(onlyIfChanged: false, portable: .always) } }
            Button("Restore…") { restoring = true }.disabled(SharedDataSession.isEnabled)
            Button("Show in Finder") { manager.revealInFinder() }
            Button("Change Folder…") { manager.chooseFolder() }
        }
    }

    private var statusText: String {
        switch manager.status {
        case .notSetUp: "Starting…"
        case .copying: "Saving a copy…"
        case .upToDate: "Up to date"
        case .behind: "Changes are waiting to be copied"
        case .folderMissing: "The folder can't be found"
        case .otherData: "That folder holds a backup copy of other data"
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

/// The copies in the backup copy folder, newest first, each with a button to restore it.
struct ShadowRestoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [ShadowVersion]?
    @State private var portables: [PortableVersion] = []
    @State private var good: Set<URL> = []
    @State private var choice: ShadowVersion?
    @State private var portableChoice: PortableVersion?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore from the backup copy").font(.title3.weight(.semibold))
            Text("This replaces the data on this Mac with the copy you choose. What is there now is kept first in Application Support ▸ Backups.")
                .font(.callout).foregroundStyle(.secondary)
            if let versions {
                if versions.isEmpty {
                    Text("There are no copies in the backup copy folder yet.")
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
                    .frame(height: portables.isEmpty ? 260 : 190)
                }
                if !portables.isEmpty {
                    Text("Portable files").font(.headline).padding(.top, 4)
                    Text("Used when no snapshot above is usable, or to go back across a version change. Includes your settings.")
                        .font(.caption).foregroundStyle(.secondary)
                    List(portables) { file in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.info.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.body.weight(.medium))
                                Text("\(file.info.summary) · \(file.info.source)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if good.contains(file.url) {
                                Button("Restore…") { portableChoice = file }
                            } else {
                                Text("Checking…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 130)
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
        .confirmationDialog("Restore this portable file?", isPresented: Binding(get: { portableChoice != nil }, set: { if !$0 { portableChoice = nil } }), titleVisibility: .visible) {
            Button("Restore and Restart", role: .destructive) {
                if let portableChoice, ShadowCopyManager.shared.requestRestore(portable: portableChoice) { dismiss() }
            }
            Button("Cancel", role: .cancel) { portableChoice = nil }
        } message: {
            if let portableChoice {
                Text("Your data becomes the file from \(portableChoice.info.savedAt.formatted(date: .abbreviated, time: .shortened)), \(portableChoice.info.summary). Anything you did after that is not in it. A copy of the current data is kept first.")
            }
        }
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
        let files = await Task.detached { folder.portableVersions() }.value
        versions = all
        portables = files
        for version in all {
            let ok = await Task.detached { folder.isGood(version) }.value
            if ok { good.insert(version.url) }
        }
        for file in files {
            let ok = await Task.detached { folder.isGood(file) }.value
            if ok { good.insert(file.url) }
        }
    }
}

// MARK: When something looks wrong at start-up

/// Shown instead of the app when the backup copy and the data disagree in a way that needs a decision: the data looks
/// empty or much smaller than the backup copy, or can't be read. Nothing is opened or changed until the person chooses.
struct ShadowRescueView: View {
    let finding: ShadowFinding

    @State private var best: ShadowVersion?
    @State private var versions: [ShadowVersion] = []
    @State private var bestPortable: PortableVersion?
    @State private var portables: [PortableVersion] = []
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
                    Text("Newest good backup copy: \(best.info.savedAt.formatted(date: .abbreviated, time: .shortened)), with \(best.info.accounts) accounts and \(best.info.transactions.formatted()) transactions.")
                        .font(.callout.weight(.medium)).foregroundStyle(.white).multilineTextAlignment(.center).frame(maxWidth: 400)
                } else if let bestPortable {
                    Text("No good snapshot was found, but the portable file from \(bestPortable.info.savedAt.formatted(date: .abbreviated, time: .shortened)) is good: \(bestPortable.info.summary).")
                        .font(.callout.weight(.medium)).foregroundStyle(.white).multilineTextAlignment(.center).frame(maxWidth: 400)
                } else if loaded {
                    Text("No good copy was found in the backup copy folder.").font(.callout.weight(.medium)).foregroundStyle(.white)
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
            "There is nothing in your data, but the backup copy has \(accounts) accounts and \(transactions.formatted()) transactions. The data may have been erased or lost."
        case .dataMuchSmaller(let have, let shadow):
            "Your data has \(have.formatted()) transactions and the backup copy has \(shadow.formatted()). Something may have gone missing."
        case .dataUnreadable(let why):
            "Oinkly Budget couldn't read your data (\(why)). Nothing has been changed."
        case .otherData:
            "The backup copy in your folder is of other data."
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
            } else if let bestPortable {
                Button("Restore It") { _ = ShadowCopyManager.shared.requestRestore(portable: bestPortable, countdown: false) }.keyboardShortcut(.defaultAction)
            }
            if versions.count > 1 || !portables.isEmpty {
                Menu("Choose Another Copy") {
                    ForEach(versions) { version in
                        Button("\(version.info.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(version.info.transactions.formatted()) transactions") {
                            _ = ShadowCopyManager.shared.requestRestore(version, countdown: false)
                        }
                    }
                    if !portables.isEmpty {
                        Divider()
                        ForEach(portables) { file in
                            Button("Portable file · \(file.info.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(file.info.transactions.formatted()) transactions") {
                                _ = ShadowCopyManager.shared.requestRestore(portable: file, countdown: false)
                            }
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
        portables = await ShadowCopyManager.shared.portableVersions()
        guard let parent = ShadowCopyManager.shared.resolveParent() else { loaded = true; return }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        let folder = ShadowFolder(inside: parent)
        best = await Task.detached { folder.newestGoodVersion() }.value
        if best == nil { bestPortable = await Task.detached { folder.newestGoodPortable() }.value }
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
        // Settings ▸ Data & Backup, as it looks with and without a backup copy
        let schema = Schema(versionedSchema: OinklyBudgetSchemaV9.self)
        if let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)) {
            let manager = ShadowCopyManager.shared
            /// Draws the Settings page in a real window (a form doesn't draw any other way) and saves a picture of it.
            func capture<Content: View>(_ view: Content, _ name: String) {
                NSApplication.shared.setActivationPolicy(.accessory)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 1500), styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .aqua)
                window.contentView = NSHostingView(rootView: view)
                window.setFrame(NSRect(x: 100, y: 0, width: 640, height: 1500), display: true)
                window.orderFrontRegardless()
                RunLoop.current.run(until: Date().addingTimeInterval(2.5))
                guard let content = window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
                content.cacheDisplay(in: content.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: folder.appendingPathComponent("shadow-\(name).png")) }
                window.orderOut(nil)
            }
            manager.showPreview(isSetUp: false, status: .notSetUp, path: nil, copies: 0, bytes: 0, lastCopy: nil, lastPortable: nil, portables: 0)
            capture(DataSettingsView().modelContainer(container), "settings-not-set-up")
            manager.showPreview(isSetUp: true, status: .upToDate(.now.addingTimeInterval(-300)), path: "/Users/someone/Documents", copies: 11, bytes: 148_000_000,
                                lastCopy: .now.addingTimeInterval(-300), lastPortable: .now.addingTimeInterval(-7_200), portables: 5)
            capture(DataSettingsView().modelContainer(container), "settings-set-up")
        }
        save(ShadowSetupSheet().background(Color(white: 0.96)), "setup")
        save(ShareSetupSheet(onShare: {}).background(Color(white: 0.96)), "share")
        save(ShadowRescueView(finding: .dataLooksEmpty(shadowAccounts: 6, shadowTransactions: 1_240)).frame(width: 500, height: 480), "rescue")
        exit(0)
    }
}
#endif
