import SwiftUI

/// Previous / next month control used at the top of every account page.
struct MonthSelector: View {
    @Binding var month: Date
    let range: ClosedRange<Date>
    /// Pages that place the "This Month" button somewhere else turn the built-in one off.
    var showsThisMonthButton = true

    private var calendar: Calendar { .current }

    var body: some View {
        HStack(spacing: 8) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(month <= range.lowerBound)

            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .frame(minWidth: 140)
                .contentTransition(.numericText())

            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(month >= range.upperBound)

            if showsThisMonthButton, !MonthFilter.isCurrent(month) {
                ThisMonthButton(month: $month)
            }
        }
        .buttonStyle(.borderless)
    }

    private func step(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        select(min(max(MonthFilter.start(of: next), range.lowerBound), range.upperBound))
    }

    private func select(_ date: Date) {
        withAnimation(.smooth) { month = date }
    }
}

/// A pill-shaped button that jumps back to the current month. Dimmed while that month is already showing.
struct ThisMonthButton: View {
    @Binding var month: Date

    var body: some View {
        CurrentPeriodButton(title: "This Month", isCurrent: MonthFilter.isCurrent(month)) {
            withAnimation(.smooth) { month = MonthFilter.start(of: .now) }
        }
    }
}

/// The pill used to jump back to now, on every page that has a month or a report period. It is always there, and
/// dimmed when you are already looking at the current one, so showing or hiding it never moves anything else.
struct CurrentPeriodButton: View {
    let title: String
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "calendar")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.accentColor.opacity(isCurrent ? 0.06 : 0.15)))
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(isCurrent ? 0.15 : 0.45), lineWidth: 1))
                .foregroundStyle(isCurrent ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .help("Back to the current period")
    }
}
