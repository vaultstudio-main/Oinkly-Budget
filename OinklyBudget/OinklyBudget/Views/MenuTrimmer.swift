import AppKit
import SwiftData
import UserNotifications

final class OinklyBudgetAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
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
                PageOpener.open(page)
            } else if !NSApp.windows.contains(where: { $0.title == "Oinkly Budget" && $0.isVisible }) {
                NotificationCenter.default.post(name: .piggybankNeedsMainWindow, object: nil)
            }
            completionHandler()
        }
    }

    /// Was the app started by macOS as a login item? Decided before any window opens, so a quiet start can keep them closed.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let property = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: 0x70726474) // 'prdt', keyAEPropData
        let atLogin = property?.enumCodeValue == 0x6C676974 // 'lgit', keyAELaunchedAsLogInItem
        StartupState.launchedAtLogin = atLogin
        let menuBarOn = UserDefaults.standard.object(forKey: BackgroundSettingsSection.showMenuBarKey) as? Bool ?? true
        StartupState.startsHidden = StartupState.shouldStartHidden(launchedAtLogin: atLogin, menuBarItemOn: menuBarOn)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
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
                // Hiding the app is a good moment to save the shared data.
                await SharedDataSession.shared.checkInNow(release: false)
            }
        }
        ShadowCopyManager.shared.start()
        // Say what happened after restoring from the backup copy.
        Task { @MainActor in
            guard let note = UserDefaults.standard.string(forKey: "shadowRestoreNote") else { return }
            UserDefaults.standard.removeObject(forKey: "shadowRestoreNote")
            var window: NSWindow?
            for _ in 0..<80 where window == nil {
                try? await Task.sleep(for: .milliseconds(500))
                window = NSApp.windows.first { $0.title == "Oinkly Budget" && $0.isVisible }
            }
            guard let window else { return }
            let alert = NSAlert()
            alert.messageText = "Backup copy"
            alert.informativeText = note
            _ = await alert.beginSheetModal(for: window)
        }
        // Say what happened to the shared folder after stopping sharing.
        Task { @MainActor in
            guard let note = UserDefaults.standard.string(forKey: SharedDataSession.stopNoteKey) else { return }
            UserDefaults.standard.removeObject(forKey: SharedDataSession.stopNoteKey)
            var window: NSWindow?
            for _ in 0..<80 where window == nil {
                try? await Task.sleep(for: .milliseconds(500))
                window = NSApp.windows.first { $0.title == "Oinkly Budget" && $0.isVisible }
            }
            guard let window else { return }
            let alert = NSAlert()
            alert.messageText = "Sharing stopped"
            alert.informativeText = note
            _ = await alert.beginSheetModal(for: window)
        }
        // Say so when the shared data had to be recovered after an unexpected close.
        Task { @MainActor in
            guard SharedDataSession.shared.notice != nil else { return }
            var window: NSWindow?
            for _ in 0..<80 where window == nil {
                try? await Task.sleep(for: .milliseconds(500))
                window = NSApp.windows.first { $0.title == "Oinkly Budget" && $0.isVisible }
            }
            guard let window, let notice = SharedDataSession.shared.notice else { return }
            SharedDataSession.shared.notice = nil
            let alert = NSAlert()
            alert.messageText = "Shared data"
            alert.informativeText = notice
            _ = await alert.beginSheetModal(for: window)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await OinklyBudgetAppDelegate.refreshReminders() }
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

    /// Quitting saves the shared data first and lets go of the lock.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let shared = SharedDataSession.shared
        let shadow = ShadowCopyManager.shared
        guard shared.isActive || shared.lostLock || shadow.needsCopyAtQuit else { return .terminateNow }
        Task { @MainActor in
            // Saving the shared data lets go of the lock, so the next user can open it.
            await shared.finishForQuit()
            // The last changes go into the backup copy too.
            await shadow.copyForQuit()
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
            PageOpener.open(page)
            return
        }
        if let copy = urls.first(where: { $0.pathExtension.lowercased() == SealedFile.fileExtension }) {
            Task { @MainActor in await CopyOpener.offerRestore(of: copy) }
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
        for _ in 0..<40 where !NSApp.windows.contains(where: { $0.title == "Oinkly Budget" && $0.isVisible }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let container = OinklyBudgetAppDelegate.container else { return }
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
        alert.informativeText = "\(url.lastPathComponent) holds \(file.summary). Everything currently in Oinkly Budget is erased first, and this can't be undone."
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
