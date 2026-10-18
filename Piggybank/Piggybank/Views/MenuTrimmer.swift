import AppKit
import SwiftData
import UserNotifications

/// Keeps the Mac menu bar to the Apple menu, Piggybank, File and Help. SwiftUI adds Edit, View and Window on its own
/// and rebuilds them from time to time, so this removes them again whenever they come back.
enum MenuTrimmer {
    private static let removed: Set<String> = ["Edit", "View", "Window"]
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        trim()
        NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async { trim() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            trim()
        }
        // Copy, paste and the rest normally live in the Edit menu. Without it they would stop working in text
        // fields, so they are handled here directly.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
               event.charactersIgnoringModifiers == "w", let window = NSApp.keyWindow {
                window.performClose(nil)
                return nil
            }
            return handleEditingShortcut(event) ? nil : event
        }
    }

    private static func trim() {
        guard let menu = NSApp.mainMenu else { return }
        for item in menu.items where removed.contains(item.submenu?.title ?? item.title) {
            menu.removeItem(item)
        }
        trimAppMenu(menu)
        trimFileMenu(menu)
    }

    /// File keeps only the ways to add things. Close and Close All come back with every window, so they are removed
    /// again here. ⌘W still closes the front window (see the key monitor).
    private static func trimFileMenu(_ mainMenu: NSMenu) {
        guard let file = mainMenu.items.first(where: { $0.submenu?.title == "File" })?.submenu else { return }
        for item in file.items where item.title == "Close" || item.title == "Close All" {
            file.removeItem(item)
        }
        // Don't leave a divider hanging at the bottom or two in a row.
        while let last = file.items.last, last.isSeparatorItem { file.removeItem(last) }
        var index = 1
        while index < file.items.count {
            if file.items[index].isSeparatorItem && file.items[index - 1].isSeparatorItem {
                file.removeItem(at: index)
            } else {
                index += 1
            }
        }
    }

    /// The app's own menu keeps only About, Settings and Quit. No Services or Hide rows.
    private static func trimAppMenu(_ mainMenu: NSMenu) {
        guard let appMenu = mainMenu.items.first?.submenu else { return }
        let keep: (NSMenuItem) -> Bool = { item in
            let title = item.title
            let isQuit = title.hasPrefix("Quit") && !title.contains("Keep")
            return title.hasPrefix("About") || title.hasPrefix("Testing") || title.hasPrefix("Settings")
                || title.hasPrefix("Preferences") || isQuit
        }
        let wanted = appMenu.items.filter(keep)
        // Already trimmed: nothing to do, and no churn that would re-trigger the menu observer.
        if appMenu.items.count == wanted.count + max(wanted.count - 1, 0) { return }

        appMenu.removeAllItems()
        for (index, item) in wanted.enumerated() {
            if index > 0 { appMenu.addItem(.separator()) }
            // The system words these with the short product name.
            if item.title.hasPrefix("Quit") { item.title = "Quit OinklyBudget" }
            appMenu.addItem(item)
        }
    }

    private static func handleEditingShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control),
              NSApp.keyWindow?.firstResponder is NSTextView,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let selector: Selector?
        switch (key, flags.contains(.shift)) {
        case ("c", false): selector = #selector(NSText.copy(_:))
        case ("x", false): selector = #selector(NSText.cut(_:))
        case ("v", false): selector = #selector(NSText.paste(_:))
        case ("a", false): selector = #selector(NSText.selectAll(_:))
        case ("z", false): selector = Selector(("undo:"))
        case ("z", true): selector = Selector(("redo:"))
        default: selector = nil
        }
        guard let selector else { return false }
        return NSApp.sendAction(selector, to: nil, from: nil)
    }
}

final class PiggybankAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the app at launch so a backup opened from Finder can reach the data.
    nonisolated(unsafe) static var container: ModelContainer?

    /// Without this, macOS holds notifications back while the app is in front. Reminders should show anyway.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Clicking a reminder brings OinklyBudget forward and goes to the page the reminder named.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let page = response.notification.request.content.userInfo["page"] as? String
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            if let page, page != ReminderPage.none.rawValue {
                NotificationCenter.default.post(name: .piggybankOpenPage, object: nil, userInfo: ["page": page])
            }
            completionHandler()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        MenuTrimmer.install()
        Task { @MainActor in await Self.refreshReminders() }
        // The widgets read a small snapshot of bill names and reminder times. Keep it current as data changes.
        Task { @MainActor in WidgetSnapshotWriter.refreshSoon() }
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            Task { @MainActor in
                WidgetSnapshotWriter.refreshSoon()
                SharedDataSession.shared.noteSaved()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                WidgetSnapshotWriter.refreshSoon()
                // Hiding the app is a good moment to bring the shared file up to date.
                await SharedDataSession.shared.checkInNow(release: false)
            }
        }
        // Tell the person about anything the shared data had to do at launch, such as keeping unsaved work. It waits
        // for the main window so it never holds up the start-up, and shows as a sheet on that window.
        Task { @MainActor in
            guard SharedDataSession.shared.notice != nil else { return }
            var window: NSWindow?
            for _ in 0..<80 where window == nil {
                try? await Task.sleep(for: .milliseconds(500))
                window = NSApp.windows.first { $0.title == "OinklyBudget" && $0.isVisible }
            }
            guard let window, let notice = SharedDataSession.shared.notice else { return }
            SharedDataSession.shared.notice = nil
            let alert = NSAlert()
            alert.messageText = "Shared data"
            alert.informativeText = notice
            _ = await alert.beginSheetModal(for: window)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await PiggybankAppDelegate.refreshReminders() }
        }
        // Planned reminders only look 45 days ahead, so top them up now and then even if nobody opens the app.
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .seconds(6 * 3600))
                await Self.refreshReminders()
                WidgetSnapshotWriter.refresh()
            }
        }
    }

    @MainActor
    static func refreshReminders() async {
        guard let container else { return }
        await BillNotifier.refresh(in: container.mainContext)
        await CustomReminders.shared.apply()
    }

    /// Quitting writes the shared data back and lets go of the lock first, so the next person can open it at once.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let session = SharedDataSession.shared
        guard session.isActive, !session.isReadOnly else { return .terminateNow }
        Task { @MainActor in
            await session.checkInNow(release: true)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Closing the window leaves OinklyBudget running, so its menu bar item stays. Without a menu bar item there
    /// would be nothing left to show, so then closing the last window quits as usual. ⌘Q always quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let showsMenuBarItem = UserDefaults.standard.object(forKey: BackgroundSettingsSection.showMenuBarKey) as? Bool ?? true
        return !showsMenuBarItem
    }

    /// Double-clicking a .pig file in Finder offers to restore it. A tap on a widget arrives here too, as an
    /// oinklybudget:// link naming the page to open.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let link = urls.first(where: { $0.scheme == WidgetSnapshot.scheme }), let page = link.host {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .piggybankOpenPage, object: nil, userInfo: ["page": page])
            return
        }
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == DataBackup.fileExtension }) else { return }
        Task { @MainActor in await BackupOpener.offerRestore(of: url) }
    }
}

/// Opening a backup from Finder: say what is in it, ask first, then replace everything with it.
@MainActor
enum BackupOpener {
    static func offerRestore(of url: URL) async {
        // A launch by double-click arrives before the app is ready. Wait for the main window.
        for _ in 0..<40 where !NSApp.windows.contains(where: { $0.title == "OinklyBudget" && $0.isVisible }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let container = PiggybankAppDelegate.container else { return }
        let file: BackupFile
        do {
            file = try DataBackup.decode(try Data(contentsOf: url))
        } catch {
            show(title: "Couldn't open that backup", text: error.localizedDescription)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace everything with this backup?"
        alert.informativeText = "\(url.lastPathComponent) holds \(file.summary). Everything currently in OinklyBudget is erased first, and this can't be undone."
        alert.addButton(withTitle: "Replace Everything")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DataDeletion.afterLeavingAccountPages {
            do {
                try DataBackup.restore(file, into: container.mainContext)
                show(title: "Backup restored", text: "Restored \(file.summary).")
            } catch {
                container.mainContext.rollback()
                show(title: "Couldn't restore the backup", text: error.localizedDescription)
            }
        }
    }

    private static func show(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
