import SwiftUI

/// Previous / next month control used at the top of every account page.
struct MonthSelector: View {
    @Binding var month: Date
    let range: ClosedRange<Date>

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

            if !MonthFilter.isCurrent(month) {
                Button("This Month") { select(MonthFilter.start(of: .now)) }
                    .font(.caption)
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
