import SwiftUI

/// The period tabs, previous/next arrows and the "Current" button (at the side) shared by every report.
struct PeriodControls: View {
    let periods: [ReportPeriod]
    @Binding var period: ReportPeriod
    @Binding var anchor: Date
    /// The earliest date the report has data for. The back arrow stops there.
    let earliest: Date?

    var body: some View {
        let range = Reports.range(period, anchor: anchor)
        VStack(spacing: 12) {
            Picker("Period", selection: $period) {
                ForEach(periods) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: period) { _, _ in anchor = Date.now }

            HStack(spacing: 14) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(earliest.map { range.start <= $0 } ?? true)
                Text(Reports.label(period, range: range))
                    .font(.headline)
                    .frame(minWidth: 150)
                    .contentTransition(.numericText())
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(range.end > .now)
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)
            // To the side, so it never pushes the arrows and the label around.
            .overlay(alignment: .trailing) {
                CurrentPeriodButton(title: "Current", isCurrent: range.start <= .now && range.end > .now) {
                    withAnimation(.smooth) { anchor = .now }
                }
            }
        }
        .padding(.top, 4)
    }

    private func step(_ direction: Int) {
        withAnimation(.smooth) { anchor = Reports.shifted(anchor, period: period, by: direction) }
    }
}

extension ReportPeriod {
    /// Every report except Income & Spending looks back over at least a quarter.
    static let longTerm: [ReportPeriod] = [.quarterly, .sixMonths, .yearly]
}
