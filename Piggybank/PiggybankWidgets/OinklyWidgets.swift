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

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var options = WidgetLines.Options()

    var lines: [WidgetLine] { WidgetLines.make(snapshot, now: date, options: options) }
}

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

/// "Fri, Oct 24 · in 3 days", the way the menu bar item says it.
private func fullWhen(_ line: WidgetLine, from now: Date) -> String {
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: line.date)).day ?? 0
    let clock = line.kind == .reminder ? ", " + line.date.formatted(date: .omitted, time: .shortened) : ""
    switch days {
    case ..<0: return "Overdue by \(-days) day\(days == -1 ? "" : "s")"
    case 0: return "Today" + clock
    case 1: return "Tomorrow" + clock
    default: return line.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + clock + " · in \(days) days"
    }
}

private extension WidgetLine.Kind {
    var symbol: String {
        switch self {
        case .bill: "calendar"
        case .repeating: "arrow.triangle.2.circlepath"
        case .reminder: "bell"
        }
    }

    var color: Color {
        switch self {
        case .bill: .blue
        case .repeating: .purple
        case .reminder: .teal
        }
    }
}

// MARK: Widget

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UpcomingBills", intent: UpcomingIntent.self, provider: UpcomingProvider()) { entry in
            UpcomingView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(WidgetSnapshot.scheme)://bills"))
        }
        .configurationDisplayName("Upcoming Transactions")
        .description("Bills, repeating transactions and your reminders that are coming up, in one list. Names and dates only. Edit the widget to choose what shows and how far ahead.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct UpcomingView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 9
        default: 4
        }
    }

    private var rangeName: String {
        entry.options.lookAheadDays.map { "the next \($0) days" } ?? entry.date.formatted(.dateTime.month(.wide))
    }

    var body: some View {
        let lines = entry.lines
        VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 6) {
            header(lines)
            if entry.snapshot == nil {
                Text("Open Oinkly Budget to show what is coming up here.")
                    .font(family == .systemSmall ? .caption : .callout)
                    .foregroundStyle(.secondary)
            } else if lines.isEmpty {
                Text("Nothing due in \(rangeName).")
                    .font(.callout)
            } else {
                ForEach(lines.prefix(limit)) { line in
                    row(line)
                }
                if lines.count > limit {
                    Text("and \(lines.count - limit) more").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ lines: [WidgetLine]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(family == .systemSmall ? "Upcoming" : "Upcoming Transactions", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if family != .systemSmall, entry.snapshot != nil {
                Text(summary(lines))
                    .font(family == .systemLarge ? .subheadline.weight(.semibold) : .caption)
                    .foregroundStyle(family == .systemLarge ? Color.primary : Color.secondary)
            }
        }
    }

    private func summary(_ lines: [WidgetLine]) -> String {
        let bills = lines.filter { $0.kind == .bill }.count
        let repeating = lines.filter { $0.kind == .repeating }.count
        let reminders = lines.filter { $0.kind == .reminder }.count
        var parts: [String] = []
        if bills > 0 { parts.append("\(bills) bill\(bills == 1 ? "" : "s")") }
        if repeating > 0 { parts.append("\(repeating) repeating") }
        if reminders > 0 { parts.append("\(reminders) reminder\(reminders == 1 ? "" : "s")") }
        let overdue = lines.filter(\.isOverdue).count
        if overdue > 0 { parts.append("\(overdue) overdue") }
        return parts.isEmpty ? "Nothing due in \(rangeName)" : parts.joined(separator: " · ") + " · \(rangeName)"
    }

    @ViewBuilder
    private func row(_ line: WidgetLine) -> some View {
        switch family {
        case .systemSmall:
            HStack(spacing: 5) {
                Image(systemName: line.kind.symbol).font(.caption2).foregroundStyle(line.kind.color)
                Text(line.name).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 4)
                Text(dayWord(line.date, from: entry.date))
                    .font(.caption)
                    .foregroundStyle(line.isOverdue ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
        default:
            HStack(spacing: 8) {
                Image(systemName: line.kind.symbol).font(.callout).foregroundStyle(line.kind.color).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(line.name).font(.callout.weight(.medium)).lineLimit(1)
                        if line.isImportant { Image(systemName: "exclamationmark.circle.fill").font(.caption2).foregroundStyle(.orange) }
                        Text(line.kind.title)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(line.kind.color.opacity(0.16), in: Capsule())
                            .foregroundStyle(line.kind.color)
                    }
                    Text(family == .systemLarge ? fullWhen(line, from: entry.date) : dayWord(line.date, from: entry.date))
                        .font(.caption)
                        .foregroundStyle(line.isOverdue ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
