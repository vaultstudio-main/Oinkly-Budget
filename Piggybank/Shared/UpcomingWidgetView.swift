import SwiftUI
import WidgetKit

/// The widget's picture: one list of bills, repeating transactions and reminders in three sizes. It lives here, and not in
/// the widget extension, so the app can draw the same views to an image and check them (debug builds). Compiled into both.

nonisolated struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var options = WidgetLines.Options()

    var lines: [WidgetLine] { WidgetLines.make(snapshot, now: date, options: options) }
}

// MARK: Wording

func dayWord(_ date: Date, from now: Date) -> String {
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
func fullWhen(_ line: WidgetLine, from now: Date) -> String {
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

struct UpcomingView: View {
    let entry: SnapshotEntry
    /// Only for drawing the view outside a widget (debug builds): the size to draw, in place of the widget's own.
    var forcedFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var widgetFamily

    private var family: WidgetFamily { forcedFamily ?? widgetFamily }

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 9
        default: 3
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
