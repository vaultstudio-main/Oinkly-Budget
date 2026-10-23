import SwiftUI
import SwiftData
import Charts

/// Every report in one place, grouped into sections. Each report totals this month, the last three and six months and
/// the last year side by side and looks six months ahead, so there is no period to pick.
struct ReportsView: View {
    @State private var section = ReportSection.overview
    @State private var pageWidth: CGFloat = 1000
    @State private var pageHeight: CGFloat = 800
    /// The room the reports have, under the title and tabs.
    @State private var viewport: CGFloat = 700
    /// How much the charts are shrunk, so the tab fits: lowered a step at a time while the tab is taller than the room.
    @State private var scale: CGFloat = 1
    /// Set once the charts are as small as they go and the tab is still too tall: each card's content then scrolls inside it.
    @State private var capped = false
    /// The last thirteen months, shared with the reports through the environment.
    @Query private var yearTransactions: [Transaction]

    init() {
        let thisMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let yearStart = Calendar.current.date(byAdding: .month, value: -13, to: thisMonth) ?? thisMonth
        _yearTransactions = Query(filter: #Predicate<Transaction> { $0.date >= yearStart })
    }

    var body: some View {
        VStack(spacing: 0) {
            // The title and the tabs stay at the top while the reports scroll below them. The tabs are like those on file folders.
            FolderTabbedHeader(title: "Reports", tabs: ReportSection.allCases, selection: $section, label: { $0.rawValue }) {
                Text(section.blurb).font(.callout).foregroundStyle(.secondary)
            } centre: { EmptyView() } trailing: { EmptyView() }
            ScrollView {
                VStack(spacing: 14) {
                    if section == .projections { ProjectionsPage() } else { grid(section.reports) }
                }
                .padding(16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Still taller than the room under the title and tabs: shrink the charts a step and measure again, then, with the
                    // charts as small as they go, let the cards' own content scroll.
                    guard section != .projections, height > viewport + 2 else { return }
                    if scale > ReportSize.smallest { scale = max(scale - 0.05, ReportSize.smallest) } else if !capped { capped = true }
                }
                // Made again at each step, so the size is measured again and the loop carries on until the tab fits.
                .id("\(scale)|\(capped)")
            }            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(viewport - height) > 1 { scale = 1; capped = false }
                viewport = height
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
            if let name = (note.userInfo?["action"] as? String)?.split(separator: ":", maxSplits: 1).last.map(String.init),
               (note.userInfo?["action"] as? String)?.hasPrefix("reportSection:") == true, let found = ReportSection(rawValue: name) { section = found }
        }
        #endif
        .environment(\.reportInputs, ReportInputs(year: yearTransactions.live))
        .background(Theme.background)
        .onChange(of: section) { _, _ in scale = 1; capped = false }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageWidth = $0.width; if abs(pageHeight - $0.height) > 1 { scale = 1; capped = false }; pageHeight = $0.height }
    }

    // MARK: Sections

    /// Reports packed into rows `columns` across. A wide report takes two columns on a page wide enough for three, or the whole row on a
    /// narrow one, and a smaller report is brought forward to fill any gap beside it. A row that is still short stretches its last
    /// card to fill it, so no space is wasted.
    private func rows(of items: [ReportItem], columns: Int) -> [[(item: ReportItem, span: Int)]] {
        func span(_ item: ReportItem) -> Int { item.isWide ? min(2, columns) : 1 }
        var waiting = items
        var rows: [[(item: ReportItem, span: Int)]] = []
        while !waiting.isEmpty {
            var row: [(item: ReportItem, span: Int)] = []
            var used = 0
            while used < columns {
                // The next in order if it fits, otherwise the first later one that does.
                guard let index = waiting.firstIndex(where: { used + span($0) <= columns }) else { break }
                let item = waiting.remove(at: index)
                row.append((item, span(item)))
                used += span(item)
            }
            if used < columns, let last = row.indices.last { row[last].span += columns - used }
            rows.append(row)
        }
        return rows
    }

    /// Every card is at least as big as its placeholder, so a report with no data yet takes the same room it will
    /// take once it fills in.
    @ViewBuilder
    private func card(_ item: ReportItem, cap: CGFloat?) -> some View {
        let minimum: CGFloat = ReportSize.h(item.isWide ? 330 : 290)
        if let kind = item.trend {
            TrendChartCard(kind: kind, height: ReportSize.h(item.isWide ? 220 : 190)).environment(\.reportCardMinHeight, minimum)
        } else if let built = ReportCards.view(section: section, title: item.title) {
            built.environment(\.reportCardMinHeight, minimum).environment(\.reportShape, item.shape).environment(\.reportContentCap, cap)
        } else {
            ReportPlaceholderCard(report: item)
        }
    }

    private func grid(_ items: [ReportItem]) -> some View {
        // Three across when the page is wide enough.
        let columns = pageWidth >= 1000 ? section.columns : 2
        ReportSize.scale = scale
        // Each row's share of the room, less what a card spends on its title and margins.
        let rowCount = rows(of: items, columns: columns).count
        let share = max((viewport - 32 - CGFloat(max(rowCount - 1, 0)) * 14) / CGFloat(max(rowCount, 1)), 260)
        let cap: CGFloat? = capped ? share - 96 : nil
        return VStack(spacing: 14) {
            ForEach(Array(rows(of: items, columns: columns).enumerated()), id: \.offset) { _, row in
                SpanRowLayout(columns: columns, spacing: 14) {
                    ForEach(row, id: \.item.id) { entry in
                        card(entry.item, cap: cap).layoutValue(key: SpanKey.self, value: entry.span)
                    }
                }
            }
        }
    }
}

// MARK: Shared styling

extension View {
    func tileStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tileBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    fileprivate var tileBackground: some ShapeStyle {
        AnyShapeStyle(Theme.panel)
    }
}

/// A titled card: the dark panel on the Mac.
struct ReportCard<Content: View>: View {
    let title: String
    var fillsHeight = false
    @ViewBuilder let content: Content

    var body: some View {
        Panel(title: title, fillsHeight: fillsHeight) { content }
    }
}

// MARK: Spanning rows

private nonisolated struct SpanKey: LayoutValueKey {
    static let defaultValue = 1
}

/// One row of report cards. Each card says how many of the row's equal columns it takes, and every card is as tall as the tallest.
private struct SpanRowLayout: Layout {
    let columns: Int
    var spacing: CGFloat = 14

    private func widths(_ subviews: Subviews, in total: CGFloat) -> [CGFloat] {
        let cell = max((total - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
        return subviews.map { cell * CGFloat($0[SpanKey.self]) + spacing * CGFloat($0[SpanKey.self] - 1) }
    }

    private func rowHeight(_ subviews: Subviews, _ widths: [CGFloat]) -> CGFloat {
        zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 900
        return CGSize(width: total, height: rowHeight(subviews, widths(subviews, in: total)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = widths(subviews, in: bounds.width)
        let height = rowHeight(subviews, sizes)
        var x = bounds.minX
        for (subview, width) in zip(subviews, sizes) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: height))
            x += width + spacing
        }
    }
}
