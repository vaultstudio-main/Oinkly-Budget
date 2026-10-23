import SwiftUI

/// At the top of both tabs of the Monthly Outlook: how much of the month's money is safe to move to savings, and from which day.
/// It is worked out twice: from what is really happening (the outlook), and from the War Plan. The safe amount is what the month
/// ends with less the buffer, and the day is the earliest from which all of it can come out and the balance still never drops
/// under the buffer.
struct SafeToMoveCard: View {
    let outlook: MonthOutlook
    let plan: [WarPlanItem]
    let opening: Decimal
    let buffer: Decimal

    var body: some View {
        let actual = SafePull(opening: opening, buffer: buffer, events: SafePull.events(outlook: outlook))
        let planned = SafePull(opening: opening, buffer: buffer, events: SafePull.events(plan: plan))
        return ReportCard(title: "Safe to Move to Savings") {
            HStack(alignment: .top, spacing: 0) {
                block("From what is happening", pull: actual, missing: nil)
                Divider().padding(.horizontal, 20)
                block("From your plan", pull: plan.isEmpty ? nil : planned, missing: "No plan yet. Add lines on the War Plan tab.")
                Divider().padding(.horizontal, 20)
                lowest(actual)
            }
            .frame(height: 78, alignment: .top)
        }
        .help("The amount is what the month ends with less your buffer. The day is the earliest from which all of it can come out and the balance still never drops under the buffer.")
    }

    private func isToday(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(.now, equalTo: outlook.month, toGranularity: .month) && calendar.startOfDay(for: date) <= calendar.startOfDay(for: .now)
    }

    private func block(_ title: String, pull: SafePull?, missing: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let pull, pull.spare > 0, let best = pull.best {
                Text(pull.spare, format: .appCurrency).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.green).lineLimit(1).minimumScaleFactor(0.7)
                Text(isToday(best.date) ? "Safe now, and from \(best.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
                                        : "From \(best.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let pull {
                Text(max(pull.spare, 0), format: .appCurrency).font(.system(size: 28, weight: .bold)).foregroundStyle(.secondary).lineLimit(1)
                Text(pull.points.isEmpty ? "Nothing is dated yet" : "Nothing is safe to move yet").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("–").font(.system(size: 28, weight: .bold)).foregroundStyle(.tertiary)
                Text(missing ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The tightest point of the month, so you can see how close it comes to the buffer.
    private func lowest(_ pull: SafePull) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TIGHTEST POINT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let low = pull.lowest {
                Text(low.balance, format: .appCurrency)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(low.balance < buffer ? Theme.red : Color.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("On \(low.date.formatted(.dateTime.month(.abbreviated).day())), buffer \(buffer.formatted(.appCurrency))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("–").font(.system(size: 28, weight: .bold)).foregroundStyle(.tertiary)
                Text("Nothing is dated yet").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
