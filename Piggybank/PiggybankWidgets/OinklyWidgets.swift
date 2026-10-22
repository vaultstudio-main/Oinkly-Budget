import SwiftUI
import WidgetKit
import AppIntents

/// Widgets for OinklyBudget: upcoming bills, and your own reminders. They show names and dates only. There are no
/// amounts or account details, and nothing leaves the Mac.
@main
struct OinklyWidgets: WidgetBundle {
    var body: some Widget {
        UpcomingBillsWidget()
        RemindersWidget()
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
    case week = 7, twoWeeks = 14, month = 30
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "How far ahead"
    static let caseDisplayRepresentations: [LookAhead: DisplayRepresentation] = [
        .week: "7 days", .twoWeeks: "14 days", .month: "30 days",
    ]
}

struct UpcomingBillsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Upcoming Bills"
    static let description = IntentDescription("Choose which bills show and how far ahead to look. Names and dates only.")

    @Parameter(title: "Show", default: .all) var scope: BillScope
    @Parameter(title: "Look ahead", default: .month) var lookAhead: LookAhead
    @Parameter(title: "Include repeating transactions", default: true) var includeRepeating: Bool
}

/// One of the person's own reminders, offered in the Reminders widget's choices. The titles come from the snapshot the
/// app wrote, so the widget never reads the app's data.
struct ReminderChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Reminder"
    static let defaultQuery = ReminderChoiceQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct ReminderChoiceQuery: EntityQuery {
    private func all() -> [ReminderChoice] {
        (WidgetSnapshot.load()?.reminders ?? []).map { ReminderChoice(id: $0.id, title: $0.title) }
    }

    func entities(for identifiers: [String]) async throws -> [ReminderChoice] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [ReminderChoice] { all() }
}

struct RemindersIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Reminders"
    static let description = IntentDescription("Choose which reminders show. Leave empty to show them all.")

    @Parameter(title: "Reminders") var reminders: [ReminderChoice]?
}

// MARK: Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// What the person chose for this widget.
    var onlyImportant = false
    var includeRepeating = true
    var lookAheadDays = 30
    /// Nil shows every reminder.
    var reminderIDs: Set<String>?
}

/// Reads the snapshot the app wrote. It makes an entry now and one at each midnight and each due time coming up, so
/// "in 3 days" turns into "Tomorrow" and "Today" without the app having to run.
enum SnapshotTimeline {
    static func make(onlyImportant: Bool = false, includeRepeating: Bool = true, lookAheadDays: Int = 30, reminderIDs: Set<String>? = nil) -> Timeline<SnapshotEntry> {
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
        let entries = moments.sorted().map {
            SnapshotEntry(date: $0, snapshot: snapshot, onlyImportant: onlyImportant, includeRepeating: includeRepeating, lookAheadDays: lookAheadDays, reminderIDs: reminderIDs)
        }
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

struct BillsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: SnapshotTimeline.sample) }

    func snapshot(for configuration: UpcomingBillsIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: context.isPreview ? SnapshotTimeline.sample : WidgetSnapshot.load(),
                      onlyImportant: configuration.scope == .importantOnly, includeRepeating: configuration.includeRepeating,
                      lookAheadDays: configuration.lookAhead.rawValue)
    }

    func timeline(for configuration: UpcomingBillsIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        SnapshotTimeline.make(onlyImportant: configuration.scope == .importantOnly, includeRepeating: configuration.includeRepeating,
                              lookAheadDays: configuration.lookAhead.rawValue)
    }
}

struct RemindersProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: SnapshotTimeline.sample) }

    private func ids(_ configuration: RemindersIntent) -> Set<String>? {
        guard let chosen = configuration.reminders, !chosen.isEmpty else { return nil }
        return Set(chosen.map(\.id))
    }

    func snapshot(for configuration: RemindersIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: context.isPreview ? SnapshotTimeline.sample : WidgetSnapshot.load(), reminderIDs: ids(configuration))
    }

    func timeline(for configuration: RemindersIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        SnapshotTimeline.make(reminderIDs: ids(configuration))
    }
}

// MARK: Wording

private func dayWord(_ date: Date, from now: Date) -> String {
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    switch days {
    case ..<0: return "Overdue"
    case 0: return "Today"
    case 1: return "Tomorrow"
    case 2...6: return date.formatted(.dateTime.weekday(.wide))
    default: return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: Upcoming bills

struct UpcomingBillsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UpcomingBills", intent: UpcomingBillsIntent.self, provider: BillsProvider()) { entry in
            UpcomingBillsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(WidgetSnapshot.scheme)://bills"))
        }
        .configurationDisplayName("Upcoming Bills")
        .description("The next bills and repeating transactions that are due. Names and dates only. Edit the widget to choose which and how far ahead.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct UpcomingBillsView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 9
        default: 4
        }
    }

    /// One line in the widget: a bill or a repeating transaction.
    private struct Line: Identifiable {
        let id: String
        let name: String
        let due: Date
        let isImportant: Bool
        let isOverdue: Bool
        let isRepeating: Bool
    }

    /// Overdue first, then important ones, then by date. Only what the widget was set to show.
    private var lines: [Line] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: entry.date)
        let end = calendar.date(byAdding: .day, value: entry.lookAheadDays + 1, to: day) ?? day
        let bills = (entry.snapshot?.bills ?? []).filter {
            ($0.due >= day || $0.isOverdue) && $0.due < end && (!entry.onlyImportant || $0.isImportant)
        }.map { Line(id: "bill-" + $0.id, name: $0.name, due: $0.due, isImportant: $0.isImportant, isOverdue: $0.isOverdue, isRepeating: false) }
        let repeating = entry.includeRepeating && !entry.onlyImportant ? (entry.snapshot?.repeating ?? []).filter {
            ($0.due >= day || $0.isOverdue) && $0.due < end
        }.map { Line(id: "repeat-" + $0.id, name: $0.name, due: $0.due, isImportant: false, isOverdue: $0.isOverdue, isRepeating: true) } : []
        return (bills + repeating).sorted {
            let a = $0.due < day, b = $1.due < day
            if a != b { return a }
            if $0.isImportant != $1.isImportant { return $0.isImportant }
            return $0.due < $1.due
        }
    }

    private var hasRepeating: Bool { entry.includeRepeating && !(entry.snapshot?.repeating.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(hasRepeating ? "Bills & Recurring" : "Bills", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if entry.snapshot == nil {
                Text("Open Oinkly Budget to show your bills here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if lines.isEmpty {
                Text("Nothing due in the next \(entry.lookAheadDays) days.")
                    .font(.callout)
            } else {
                ForEach(lines.prefix(limit)) { line in
                    HStack(spacing: 6) {
                        if line.isImportant { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                        if line.isRepeating { Image(systemName: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(.secondary) }
                        Text(line.name).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(dayWord(line.due, from: entry.date))
                            .font(.caption)
                            .foregroundStyle(line.due < Calendar.current.startOfDay(for: entry.date) ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                }
                if lines.count > limit {
                    Text("and \(lines.count - limit) more").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Reminders

struct RemindersWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Reminders", intent: RemindersIntent.self, provider: RemindersProvider()) { entry in
            RemindersView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(WidgetSnapshot.scheme)://summary"))
        }
        .configurationDisplayName("Reminders")
        .description("Your own reminders from Oinkly Budget, and when they are next. Edit the widget to choose which ones.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct RemindersView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 8
        default: 4
        }
    }

    private var reminders: [WidgetSnapshot.Reminder] {
        (entry.snapshot?.reminders ?? []).filter { $0.next >= entry.date && (entry.reminderIDs?.contains($0.id) ?? true) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Reminders", systemImage: "bell")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if entry.snapshot == nil {
                Text("Open Oinkly Budget to show your reminders here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if reminders.isEmpty {
                Text("No reminders. Add one in Oinkly Budget ▸ Settings ▸ Reminders.")
                    .font(.caption)
            } else {
                ForEach(reminders.prefix(limit)) { reminder in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(reminder.title).font(.callout.weight(.medium)).lineLimit(1)
                        Text("\(dayWord(reminder.next, from: entry.date)), \(reminder.next.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
