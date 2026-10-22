import AppKit
import SwiftUI
import SwiftData

/// A way to take the app's screenshots from a throwaway data file filled with the test data, so no real data is ever on
/// screen and the real data file, reminders and widgets are never touched. Debug builds only; in a release build `isOn` is
/// always false.
///
/// Run the debug app with `-screenshotMode -screenshotDir <folder> -appearance light`. It loads the test data into a
/// temporary data file, sizes the window, visits every page, window, sheet and settings tab, writes a PNG of each, then
/// quits. The Testing menu is left out, so the shots show only what the app has.
enum ScreenshotMode {
    static var isOn: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-screenshotMode")
        #else
        false
        #endif
    }

    /// `-screenshotFresh YES` starts from an empty throwaway data file, so changes to the test data show up. Only ever touches
    /// the throwaway file, never the real data. Call before the file is opened.
    static func removeStoreIfRequested() {
        guard UserDefaults.standard.bool(forKey: "screenshotFresh") else { return }
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }

    /// The throwaway data file, in the app's own temporary folder.
    static var storeURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotStore/OinklyBudget.store") }
}

#if DEBUG
extension Notification.Name {
    /// Debug only: `userInfo["action"]` names something for the page showing to do, such as "addBill".
    static let piggybankScreenshotAction = Notification.Name("piggybank.screenshot.action")
    /// Debug only: `userInfo["tab"]` is "bills" or "recurring".
    static let piggybankScreenshotBillsTab = Notification.Name("piggybank.screenshot.billsTab")
}

extension ScreenshotMode {
    /// A small bank file to import, for the import preview.
    static func sampleStatement() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotStatement", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Checking statement.csv")
        let calendar = Calendar.current
        func day(_ offset: Int) -> String {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            return date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        }
        let rows = [
            "Date,Description,Amount",
            "\(day(2)),CITY WATER UTILITY,-58.40",
            "\(day(3)),FARMERS MARKET #1182,-34.75",
            "\(day(4)),PAYROLL DIRECT DEPOSIT,2150.00",
            "\(day(6)),PIZZA PALACE 0042,-27.90",
            "\(day(7)),HARDWARE DEPOT,-86.00",
            "\(day(9)),BOOK NOOK,-18.25",
            "\(day(11)),CORNER PHARMACY,-12.60",
            "\(day(13)),REFUND STREAMLY,22.99",
        ]
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    static func startIfRequested(container: ModelContainer) {
        guard isOn else { return }
        Task { @MainActor in
            await ScreenshotRun(container: container).run()
        }
    }
}

/// The script: what to open, what to do there, and what to call each picture.
@MainActor
private struct ScreenshotRun {
    let container: ModelContainer
    var folder: URL
    /// The main window, so it is drawn without a frame around it.
    nonisolated(unsafe) static var mainWindowRef: NSWindow?

    init(container: ModelContainer) {
        self.container = container
        let flag = CommandLine.arguments.firstIndex(of: "-screenshotDir")
        let path = flag.flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil } ?? "/Users/Shared/OinklyBudget/shots"
        folder = URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: Doing things

    func post(_ action: String) { NotificationCenter.default.post(name: .piggybankScreenshotAction, object: nil, userInfo: ["action": action]) }

    func go(_ page: String) {
        if page.hasPrefix("account:") {
            NotificationCenter.default.post(name: .piggybankOpenPage, object: nil, userInfo: ["account": String(page.dropFirst("account:".count))])
        } else {
            NotificationCenter.default.post(name: .piggybankOpenPage, object: nil, userInfo: ["page": page])
        }
    }

    func wait(_ seconds: Double = 1.2) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// Brings the app forward. A window of an app that isn't in front is drawn in its inactive colors (a black sidebar
    /// selection, gray buttons), so this is done before every picture.
    func bringForward(_ window: NSWindow? = nil) async {
        if !NSApp.isActive || window?.isKeyWindow == false {
            NSApp.activate(ignoringOtherApps: true)
            (window ?? Self.mainWindowRef)?.makeKeyAndOrderFront(nil)
            await wait(0.6)
        }
    }

    func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain && $0.frame.width > 1000 && $0.contentView != nil && $0.sheetParent == nil }
    }

    /// Clicks a menu item by its title, the way a person would.
    func menu(_ title: String) {
        func search(_ menu: NSMenu) -> (NSMenu, Int)? {
            for (index, item) in menu.items.enumerated() {
                if item.title == title, item.isEnabled { return (menu, index) }
                if let sub = item.submenu, let found = search(sub) { return found }
            }
            return nil
        }
        guard let main = NSApp.mainMenu, let (found, index) = search(main) else { NSLog("SHOT: no menu item \(title)"); return }
        found.performActionForItem(at: index)
    }

    func waitForWindow(titled title: String, tries: Int = 12) async -> NSWindow? {
        for _ in 0..<tries {
            if let match = NSApp.windows.first(where: { $0.title == title && $0.isVisible }) { return match }
            await wait(0.5)
        }
        NSLog("SHOT: no window titled \(title)")
        return nil
    }

    // MARK: Taking pictures

    /// `-screenshotOnly <prefix>` takes just the pictures whose names start with it, for trying one thing again.
    var only: String? {
        guard let flag = CommandLine.arguments.firstIndex(of: "-screenshotOnly"), flag + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[flag + 1]
    }

    func capture(_ window: NSWindow, as name: String) {
        if let only, !name.hasPrefix(only) { return }
        // The frame view includes the title bar and toolbar, such as the tabs of the Settings window.
        // The main window is its own content. Others are taken with their frame, so the title bar and tabs show.
        let source = window === Self.mainWindowRef ? window.contentView : (window.contentView?.superview ?? window.contentView)
        guard let view = source, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSLog("SHOT: could not capture \(name)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: folder.appendingPathComponent(name + ".png"))
        NSLog("SHOT: \(name) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    /// The sheet that is open on the main window.
    func captureSheet(as name: String) {
        if let sheet = mainWindow()?.attachedSheet ?? NSApp.windows.first(where: { $0.sheetParent != nil && $0.isVisible }) {
            capture(sheet, as: name)
        } else {
            NSLog("SHOT: no sheet for \(name)")
        }
    }

    /// The biggest scroll view in a window.
    func scrollMain(toBottom: Bool) {
        guard let root = mainWindow()?.contentView else { return }
        var best: NSScrollView?
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView, (scroll.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0), scroll.frame.width > 600 { best = scroll }
            view.subviews.forEach(walk)
        }
        walk(root)
        guard let scroll = best, let document = scroll.documentView else { return }
        let target = toBottom ? max(document.frame.height - scroll.contentView.bounds.height, 0) : 0
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? target : (toBottom ? 0 : max(document.frame.height - scroll.contentView.bounds.height, 0))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Opens a window from the menu, takes its picture and closes it.
    func windowShot(menu title: String, windowTitle: String, as name: String, extra: (() async -> Void)? = nil, size: NSSize? = nil) async {
        menu(title)
        guard let opened = await waitForWindow(titled: windowTitle) else { return }
        if let size { opened.setContentSize(size) }
        opened.setFrameOrigin(NSPoint(x: 120, y: 120))
        await wait(1.2)
        if let extra { await extra() }
        await bringForward(opened)
        capture(opened, as: name)
        opened.close()
        await wait(0.6)
    }

    /// A page, taken after it has settled.
    func pageShot(_ page: String, as name: String, wait seconds: Double = 2.2) async {
        go(page)
        await wait(seconds)
        await bringForward(mainWindow())
        if let window = mainWindow() { capture(window, as: name) }
    }

    /// A sheet opened by an action on the page that is showing.
    func sheetShot(open action: String, as name: String, waiting: Double = 1.5) async {
        post(action)
        await wait(waiting)
        await bringForward(Self.mainWindowRef)
        captureSheet(as: name)
        post("closeSheets")
        await wait(0.8)
    }

    /// A view drawn on its own, off to the side, for things that are not in a window (the menu bar pop-up).
    func offscreenShot<V: View>(_ view: V, size: NSSize, as name: String) async {
        let hosting = NSHostingView(rootView: view.modelContainer(container).environment(\.colorScheme, .light))
        let panel = NSWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 200), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.backgroundColor = .windowBackgroundColor
        panel.orderFront(nil)
        await wait(1.5)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize.width > 0 ? NSSize(width: size.width, height: min(max(hosting.fittingSize.height, 120), 900)) : size)
        panel.setContentSize(hosting.frame.size)
        await wait(0.5)
        capture(panel, as: name)
        panel.close()
    }

    // MARK: The script

    func run() async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = container.mainContext
        // Give the app a moment to finish starting before the test data goes in; loading it holds the app up.
        await wait(3)
        if ((try? context.fetchCount(FetchDescriptor<Account>())) ?? 0) <= 1 {
            NSLog("SHOT: loading the test data")
            do { try TestData.load(into: context); context.saveNow() } catch { NSLog("SHOT: test data failed: \(error.localizedDescription)") }
            NSLog("SHOT: test data loaded")
        }
        // The start-up window runs its checks and then opens the main window.
        var found: NSWindow?
        var tick = 0
        for _ in 0..<60 where found == nil {
            await wait(1)
            found = mainWindow()
            tick += 1
            if tick % 5 == 0 { NSLog("SHOT: waiting \(tick)s, windows: \(NSApp.windows.map { "\($0.title)|\($0.frame.size)|visible \($0.isVisible)" }), active \(NSApp.isActive), policy \(NSApp.activationPolicy().rawValue)") }
        }
        guard let window = found else {
            NSLog("SHOT: no main window. Windows: \(NSApp.windows.map { "\($0.title) visible \($0.isVisible) \($0.frame)" })")
            exit(1)
        }
        await wait(4)
        Self.mainWindowRef = window
        // 1600 x 1000 points is 3200 x 2000 pixels on a Retina screen; the App Store copies are scaled to 2880 x 1800.
        NSApp.activate(ignoringOtherApps: true)
        let width = CommandLine.arguments.firstIndex(of: "-screenshotWidth").flatMap { Double(CommandLine.arguments[$0 + 1]) } ?? 1600
        window.setFrame(NSRect(x: 40, y: 40, width: width, height: width * 0.625), display: true)
        window.makeKeyAndOrderFront(nil)
        await wait(2)

        // Overview pages
        await pageShot("transactions", as: "x-warmup")
        await pageShot("summary", as: "page-summary")
        scrollMain(toBottom: true); await wait(1); await bringForward(window); capture(window, as: "page-summary-lower"); scrollMain(toBottom: false)
        await pageShot("transactions", as: "page-transactions")
        await pageShot("reports", as: "page-reports")
        for section in ["Spending", "Income", "Cash Flow", "Net Worth", "Debt & Loans", "Savings & Goals", "Budgets", "Bills", "Investments"] {
            post("reportSection:\(section)")
            await wait(1.6)
            await bringForward(window)
            capture(window, as: "page-reports-" + section.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-"))
        }
        await pageShot("liabilities", as: "page-liabilities")
        await pageShot("investments", as: "page-investments")
        await pageShot("planning", as: "page-planning")
        await sheetShot(open: "goalDetail", as: "sheet-goal-detail")
        await sheetShot(open: "addGoal", as: "sheet-add-goal")
        await pageShot("budgets", as: "page-budgets")
        await pageShot("outlook", as: "page-month-outlook")
        await pageShot("manageAccounts", as: "page-manage-accounts")

        // Bills & Recurring
        await pageShot("bills", as: "page-bills")
        await sheetShot(open: "addBill", as: "sheet-add-bill")
        await sheetShot(open: "editBill", as: "sheet-edit-bill")
        NotificationCenter.default.post(name: .piggybankScreenshotBillsTab, object: nil, userInfo: ["tab": "recurring"])
        await wait(2)
        await bringForward(window)
        capture(window, as: "page-recurring")
        await sheetShot(open: "addRule", as: "sheet-add-rule")
        await sheetShot(open: "editRule", as: "sheet-edit-rule")
        NotificationCenter.default.post(name: .piggybankScreenshotBillsTab, object: nil, userInfo: ["tab": "bills"])

        // Accounts
        await pageShot("account:Everyday Checking", as: "account-checking")
        // The split transaction and the tagged ones, found with the search field on the Transactions page.
        await pageShot("transactions", as: "x-transactions")
        post("search:Big Box"); await wait(1.5); await bringForward(window); capture(window, as: "page-transactions-split")
        post("search:Trail Shoes"); await wait(1.5); await bringForward(window); capture(window, as: "page-transactions-tags")
        post("search:"); await wait(0.8)
        await pageShot("account:Everyday Checking", as: "x-checking-back")
        post("select:Big Box Store"); await wait(1)
        await sheetShot(open: "edit", as: "sheet-edit-split")
        post("details"); await wait(1.5)
        if let detail = await waitForWindow(titled: "Transaction", tries: 6) { detail.setFrameOrigin(NSPoint(x: 160, y: 140)); await wait(1); capture(detail, as: "win-detail-split"); detail.close() }
        await wait(0.6)
        post("select:Hardware Depot|86.35"); await wait(0.8)
        post("details"); await wait(1.8)
        if let detail = await waitForWindow(titled: "Transaction", tries: 6) { detail.setFrameOrigin(NSPoint(x: 160, y: 140)); await wait(1.5); capture(detail, as: "win-detail-receipt"); detail.close() }
        await wait(0.6)
        await sheetShot(open: "editDetails", as: "sheet-edit-account-checking")
        await sheetShot(open: "export:pdf", as: "sheet-export-pdf")
        await sheetShot(open: "export:csv", as: "sheet-export-csv")
        post("import"); await wait(2.5); captureSheet(as: "sheet-import")
        post("importMapping"); await wait(1.2); captureSheet(as: "sheet-import-mapping")
        post("closeSheets"); await wait(0.8)
        post("select:Hardware Depot|86.35"); await wait(0.8)
        await sheetShot(open: "makeRecurring", as: "sheet-make-recurring")
        await pageShot("account:Sapphire Card", as: "account-card")
        post("select:Trail Shoes Co"); await wait(0.8)
        await sheetShot(open: "edit", as: "sheet-edit-tags")
        await pageShot("account:House Down Payment", as: "account-savings")
        await sheetShot(open: "editDetails", as: "sheet-edit-account-savings")
        await pageShot("account:Student Loan", as: "account-loan")
        await pageShot("account:Home Mortgage", as: "account-mortgage")
        await pageShot("account:Honda Civic Loan", as: "account-auto-loan")
        await pageShot("account:Cash on Hand", as: "account-cash")
        post("newCash"); await wait(1.5)
        if let cash = await waitForWindow(titled: "New Cash Transaction", tries: 6) { cash.setFrameOrigin(NSPoint(x: 160, y: 140)); await wait(1); capture(cash, as: "win-new-cash"); cash.close() }
        await wait(0.6)
        await pageShot("account:Brokerage", as: "account-brokerage")
        await pageShot("account:401(k)", as: "account-401k")
        await pageShot("account:Family Home", as: "account-asset")
        await pageShot("account:Everyday Checking", as: "x-back")

        // Windows from the menus
        await windowShot(menu: "New Transaction…", windowTitle: "New Transaction", as: "win-new-transaction",
                         extra: { self.post("account:Everyday Checking"); await self.wait(0.8) })
        await windowShot(menu: "New Transaction…", windowTitle: "New Transaction", as: "win-new-transaction-autofill",
                         extra: { self.post("account:Everyday Checking"); await self.wait(0.6); self.post("payee:Bean"); await self.wait(1.2) })
        await windowShot(menu: "New Transaction…", windowTitle: "New Transaction", as: "win-new-transaction-split",
                         extra: { self.post("account:Everyday Checking"); await self.wait(0.6); self.post("splitDemo"); await self.wait(1.4) })
        await windowShot(menu: "New Credit Card Charge…", windowTitle: "New Credit Card Charge", as: "win-card-charge")
        await windowShot(menu: "ATM Withdrawal…", windowTitle: "ATM Withdrawal", as: "win-atm")
        await windowShot(menu: "Transfer…", windowTitle: "Transfer", as: "win-transfer")
        await windowShot(menu: "Pay a Bill…", windowTitle: "Pay a Bill", as: "win-pay-bill")
        await pageShot("account:Brokerage", as: "x-back2")
        await windowShot(menu: "Update Investment Price…", windowTitle: "Update Investment Price", as: "win-update-price")
        await pageShot("summary", as: "x-back3")

        // Help, release notes, about
        menu("Oinkly Budget Help")
        if let help = await waitForWindow(titled: "Oinkly Budget Help") {
            help.setFrame(NSRect(x: 80, y: 80, width: 1200, height: 800), display: true)
            help.makeKeyAndOrderFront(nil)
            await wait(1.5)
            for (topic, name) in [("Welcome", "win-help-welcome"), ("Recurring Transactions", "win-help-recurring"), ("Split Transactions", "win-help-split")] {
                post("helpTopic:\(topic)")
                await wait(2.5)
                capture(help, as: name)
            }
            help.close()
        }
        await windowShot(menu: "Release Notes", windowTitle: "Release Notes", as: "win-release-notes", size: NSSize(width: 860, height: 780))
        await windowShot(menu: "About Oinkly Budget", windowTitle: "About Oinkly Budget", as: "win-about")

        // Settings, one tab at a time
        let key = MacSettingsView.tabKey
        let before = UserDefaults.standard.string(forKey: key)
        for (tab, name) in [("general", "set-general"), ("reminders", "set-reminders"), ("accounts", "set-accounts"), ("categories", "set-categories"),
                            ("tags", "set-tags"), ("cleanup", "set-cleanup"), ("payments", "set-payment-methods"), ("data", "set-data")] {
            UserDefaults.standard.set(tab, forKey: key)
            menu("Settings…")
            await wait(2)
            if let settings = NSApp.windows.first(where: { $0.isVisible && abs($0.frame.width - 640) < 80 && $0.contentView != nil }) {
                settings.setFrameOrigin(NSPoint(x: 160, y: 140))
                await wait(0.8)
                capture(settings, as: name)
                settings.close()
            } else {
                NSLog("SHOT: no settings window for \(tab)")
            }
            await wait(0.8)
        }
        if let before { UserDefaults.standard.set(before, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }

        // Things drawn on their own
        await offscreenShot(MenuBarBills(), size: NSSize(width: 400, height: 640), as: "menubar-popup")
        let snapshot = WidgetSnapshotWriter.makeSnapshot(container: container)
        WidgetSnapshotWriter.render(to: folder, snapshot: snapshot, prefix: "widget")

        NSLog("SHOT: done")
        exit(0)
    }
}
#endif
