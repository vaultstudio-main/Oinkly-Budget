import Foundation
import SwiftData
import WidgetKit
import SwiftUI

/// Keeps the widgets' snapshot up to date. Called when the app opens, when anything is saved, when reminders change
/// and now and then while it runs. Changes are gathered for a moment so a burst of saves writes the file once.
@MainActor
enum WidgetSnapshotWriter {
    private static var pending: Task<Void, Never>?

    static func refreshSoon() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    static func refresh(now: Date = .now) {
        // Screenshots use made-up data: never write it where the real widgets would read it.
        guard !ScreenshotMode.isOn, let container = OinklyBudgetAppDelegate.container else { return }
        let snapshot = makeSnapshot(container: container, now: now)
        if snapshot.write() { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// What the widgets are given, from the saved data.
    static func makeSnapshot(container: ModelContainer, now: Date = .now) -> WidgetSnapshot {
        // A fresh context always reads what has been saved.
        let context = ModelContext(container)
        let bills = ((try? context.fetch(FetchDescriptor<Bill>())) ?? []).live

        let items: [WidgetSnapshot.Bill] = Bills.upcoming(bills, days: 30, now: now)
            .filter { !$0.isPaid && $0.bill.isLive }
            .map { WidgetSnapshot.Bill(id: $0.id, name: $0.bill.name, due: $0.date, isImportant: $0.bill.isImportant, isOverdue: $0.isOverdue) }
            .sorted { $0.due < $1.due }

        let reminders: [WidgetSnapshot.Reminder] = CustomReminders.shared.items
            .filter { $0.isOn && !$0.hasPassed }
            .compactMap { reminder in
                reminder.nextDate(after: now).map {
                    WidgetSnapshot.Reminder(id: reminder.id.uuidString, title: reminder.title.isEmpty ? "Reminder" : reminder.title, next: $0)
                }
            }
            .sorted { $0.next < $1.next }

        let rules = ((try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []).live
        let repeating: [WidgetSnapshot.Repeating] = Recurring.upcoming(rules, days: 31, now: now)
            .map { WidgetSnapshot.Repeating(id: $0.id, name: $0.rule.payee, due: $0.date, isOverdue: $0.isOverdue) }
            .sorted { $0.due < $1.due }

        return WidgetSnapshot(updated: now, bills: items, reminders: Array(reminders.prefix(12)), repeating: Array(repeating.prefix(30)))
    }
}

extension CustomReminder {
    /// The next time this reminder goes off after `date`.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        var parts = clock
        switch repeats {
        case .daily:
            break
        case .weekly:
            parts.weekday = weekday
        case .monthly:
            parts.day = dayOfMonth
        case .once:
            return onceDate > date ? onceDate : nil
        }
        return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime)
    }
}

#if DEBUG
extension WidgetSnapshotWriter {
    /// `-widgetSnapshotCheck` writes the widget file now, reads it back the way the widget does, logs what is in it, and
    /// quits. Shows whether the shared App Group folder works and what the widgets are being given. Debug only.
    @MainActor
    static func runCheckIfRequested() {
        guard CommandLine.arguments.contains("-widgetSnapshotCheck") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            refresh()
            if let snapshot = WidgetSnapshot.load() {
                NSLog("WIDGETCHECK: file read OK. bills \(snapshot.bills.count), repeating \(snapshot.repeating.count), reminders \(snapshot.reminders.count), updated \(snapshot.updated)")
                NSLog("WIDGETCHECK: lines the widget lists this month: \(WidgetLines.make(snapshot, now: .now).map { "\($0.kind.title): \($0.name)" })")
            } else {
                NSLog("WIDGETCHECK: the widget file could not be written or read")
            }
            if let flag = CommandLine.arguments.firstIndex(of: "-widgetRender"), flag + 1 < CommandLine.arguments.count {
                render(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true), snapshot: WidgetSnapshot.load())
            }
            exit(0)
        }
    }

    /// Draws the widget's three sizes with the real snapshot into PNG files, so what the widget shows can be looked at.
    @MainActor
    static func render(to folder: URL, snapshot: WidgetSnapshot?, prefix: String = "widget") {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sizes: [(String, WidgetFamily, CGSize)] = [("small", .systemSmall, CGSize(width: 170, height: 170)),
                                                      ("medium", .systemMedium, CGSize(width: 364, height: 170)),
                                                      ("large", .systemLarge, CGSize(width: 364, height: 382))]
        for (name, family, size) in sizes {
            let entry = SnapshotEntry(date: .now, snapshot: snapshot)
            let view = UpcomingView(entry: entry, forcedFamily: family)
                .padding(16)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.96)))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .padding(16)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                NSLog("WIDGETCHECK: could not draw \(name)")
                continue
            }
            try? png.write(to: folder.appendingPathComponent("\(prefix)-\(name).png"))
            NSLog("WIDGETCHECK: drew \(name) \(Int(size.width))x\(Int(size.height))")
        }
    }
}
#endif
