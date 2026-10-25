import SwiftUI

/// One bar of a ShareBarChart: a name, how big it is, and what to print at the end of the bar. A colour is optional; the shared
/// palette fills in the rest.
struct ShareBar: Identifiable {
    let name: String
    let value: Double
    var label: String
    var color: Color?
    var id: String { name }
}

/// The app's way of showing how a whole is split: horizontal bars, biggest first, with the amount and share printed at the end of each.
/// It stands in for the circle graphs the app no longer uses.
struct ShareBarChart: View {
    let bars: [ShareBar]
    static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .indigo, .red, .mint]

    /// The bars for a split of money: each with its amount and its share of the total.
    static func money(_ items: [(name: String, value: Double, color: Color?)], limit: Int = 8) -> [ShareBar] {
        let total = max(items.reduce(0) { $0 + $1.value }, 1)
        return items.prefix(limit).map {
            ShareBar(name: $0.name, value: $0.value,
                     label: "\(ReportFormat.money($0.value))  \(ReportFormat.percent($0.value / total * 100))", color: $0.color)
        }
    }

    var body: some View {
        let biggest = max(bars.map(\.value).max() ?? 1, 0.000001)
        VStack(spacing: 8) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                HStack(spacing: 10) {
                    Text(bar.name).font(.callout).lineLimit(1).frame(width: 140, alignment: .trailing)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(bar.color ?? Self.palette[index % Self.palette.count])
                            .frame(width: max(geo.size.width * bar.value / biggest, 3))
                    }
                    .frame(height: 16)
                    Text(bar.label).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(width: 130, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
