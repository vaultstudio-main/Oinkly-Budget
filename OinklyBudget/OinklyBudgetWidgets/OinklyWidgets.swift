import SwiftUI
import WidgetKit
import AppIntents

/// The Oinkly Budget widget: bills, repeating transactions and your own reminders in one list, in three sizes. It shows
/// names and dates only. There are no amounts or account details, and nothing leaves the Mac.
@main
struct OinklyWidgets: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
    }
}

// MARK: Choices (right-click a widget, then Edit Widget)

enum BillScope: String, AppEnum {
    case all, importantOnly
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Which bills"
    static let caseDisplayRepresentations: [BillScope: DisplayRepresentation] = [
        .all: "All bills", .importantOnly: "Important bills only",
    ]
}

enum LookAhead: Int, AppEnum {
    case thisMonth = 0, week = 7, twoWeeks = 14, month = 30
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "How far ahead"
    static let caseDisplayRepresentations: [LookAhead: DisplayRepresentation] = [
        .thisMonth: "This month", .week: "7 days", .twoWeeks: "14 days", .month: "30 days",
    ]
}

struct UpcomingIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Upcoming Transactions"
    static let description = IntentDescription("Choose what shows and how far ahead to look. Names and dates only.")

    @Parameter(title: "Bills", default: .all) var scope: BillScope
    @Parameter(title: "Look ahead", default: .thisMonth) var lookAhead: LookAhead
    @Parameter(title: "Include repeating transactions", default: true) var includeRepeating: Bool
    @Parameter(title: "Include my reminders", default: true) var includeReminders: Bool

    var options: WidgetLines.Options {
        WidgetLines.Options(onlyImportant: scope == .importantOnly, includeRepeating: includeRepeating, includeReminders: includeReminders,
                            lookAheadDays: lookAhead == .thisMonth ? nil : lookAhead.rawValue)
    }
}

// MARK: Timeline

/// Reads the snapshot the app wrote. It makes an entry now and one at each midnight and each reminder time coming up, so
/// "in 3 days" turns into "Tomorrow" and "Today" without the app having to run.
enum SnapshotTimeline {
    static func make(options: WidgetLines.Options) -> Timeline<SnapshotEntry> {
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        let now = Date()
        var moments: Set<Date> = [now]
        var midnight = calendar.startOfDay(for: now)
        for _ in 0..<8 {
            midnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
            moments.insert(midnight)
        }
        for reminder in snapshot?.reminders ?? [] where reminder.next > now && reminder.next < midnight { moments.insert(reminder.next) }
        let entries = moments.sorted().map { SnapshotEntry(date: $0, snapshot: snapshot, options: options) }
        return Timeline(entries: entries, policy: .after(calendar.date(byAdding: .hour, value: 6, to: now) ?? now))
    }

    static let sample = WidgetSnapshot(
        updated: .now,
        bills: [
            .init(id: "1", name: "Electric", due: Date().addingTimeInterval(86_400 * 2), isImportant: true, isOverdue: false),
            .init(id: "2", name: "Internet", due: Date().addingTimeInterval(86_400 * 6), isImportant: false, isOverdue: false),
            .init(id: "3", name: "Water", due: Date().addingTimeInterval(86_400 * 12), isImportant: false, isOverdue: false),
        ],
        reminders: [
            .init(id: "1", title: "Review my budget", next: Date().addingTimeInterval(86_400)),
            .init(id: "2", title: "Back up my data", next: Date().addingTimeInterval(86_400 * 8)),
        ],
        repeating: [
            .init(id: "r1", name: "Paycheque", due: Date().addingTimeInterval(86_400 * 3), isOverdue: false),
            .init(id: "r2", name: "Rent", due: Date().addingTimeInterval(86_400 * 9), isOverdue: false),
        ])
}

struct UpcomingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: SnapshotTimeline.sample, options: WidgetLines.Options(lookAheadDays: 30))
    }

    func snapshot(for configuration: UpcomingIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: context.isPreview ? SnapshotTimeline.sample : WidgetSnapshot.load(),
                      options: context.isPreview ? WidgetLines.Options(lookAheadDays: 30) : configuration.options)
    }

    func timeline(for configuration: UpcomingIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        SnapshotTimeline.make(options: configuration.options)
    }
}

// MARK: Widget

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        // A new kind, so the old Upcoming Bills and Reminders widgets that were placed on the desktop are dropped, and this one is
        // added fresh from the gallery.
        AppIntentConfiguration(kind: "UpcomingTransactions", intent: UpcomingIntent.self, provider: UpcomingProvider()) { entry in
            UpcomingView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(WidgetSnapshot.scheme)://bills"))
        }
        .configurationDisplayName("Upcoming Transactions")
        .description("Bills, repeating transactions and your reminders that are coming up, in one list. Names and dates only. Edit the widget to choose what shows and how far ahead.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
