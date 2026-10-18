import SwiftUI
import WidgetKit

/// Widgets for OinklyBudget: upcoming bills, and your own reminders. They show names and dates only. There are no
/// amounts or account details, and nothing leaves the Mac.
@main
struct OinklyWidgets: WidgetBundle {
    var body: some Widget {
        UpcomingBillsWidget()
        RemindersWidget()
    }
}

// MARK: Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads the snapshot the app wrote. It makes an entry now and one at each midnight and each due time coming up, so
/// "in 3 days" turns into "Tomorrow" and "Today" without the app having to run.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? Self.sample : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
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
        let entries = moments.sorted().map { SnapshotEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(calendar.date(byAdding: .hour, value: 6, to: now) ?? now)))
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
        ])
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
        StaticConfiguration(kind: "UpcomingBills", provider: SnapshotProvider()) { entry in
            UpcomingBillsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(WidgetSnapshot.scheme)://bills"))
        }
        .configurationDisplayName("Upcoming Bills")
        .description("The next bills that are due. Names and dates only.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct UpcomingBillsView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemSmall ? 3 : 4 }

    /// Overdue first, then important ones, then by date.
    private var bills: [WidgetSnapshot.Bill] {
        let day = Calendar.current.startOfDay(for: entry.date)
        let open = (entry.snapshot?.bills ?? []).filter { $0.due >= day || $0.isOverdue }
        return open.sorted {
            let a = $0.due < day, b = $1.due < day
            if a != b { return a }
            if $0.isImportant != $1.isImportant { return $0.isImportant }
            return $0.due < $1.due
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Bills", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if entry.snapshot == nil {
                Text("Open OinklyBudget to show your bills here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if bills.isEmpty {
                Text("Nothing due in the next 30 days.")
                    .font(.callout)
            } else {
                ForEach(bills.prefix(limit)) { bill in
                    HStack(spacing: 6) {
                        if bill.isImportant { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                        Text(bill.name).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(dayWord(bill.due, from: entry.date))
                            .font(.caption)
                            .foregroundStyle(bill.due < Calendar.current.startOfDay(for: entry.date) ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                }
                if bills.count > limit {
                    Text("and \(bills.count - limit) more").font(.caption2).foregroundStyle(.secondary)
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
        StaticConfiguration(kind: "Reminders", provider: SnapshotProvider()) { entry in
            RemindersView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(WidgetSnapshot.scheme)://summary"))
        }
        .configurationDisplayName("Reminders")
        .description("Your own reminders from OinklyBudget, and when they are next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RemindersView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemSmall ? 3 : 4 }
    private var reminders: [WidgetSnapshot.Reminder] { (entry.snapshot?.reminders ?? []).filter { $0.next >= entry.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Reminders", systemImage: "bell")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if entry.snapshot == nil {
                Text("Open OinklyBudget to show your reminders here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if reminders.isEmpty {
                Text("No reminders. Add one in OinklyBudget ▸ Settings ▸ Reminders.")
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
