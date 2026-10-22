import SwiftUI
import SwiftData
import Charts

/// Every report in one place, grouped into sections. Each report totals this month, the last three and six months and
/// the last year side by side and looks six months ahead, so there is no period to pick.
struct ReportsView: View {
    @State private var section = ReportSection.overview
    @State private var pageWidth: CGFloat = 1000
    /// The last thirteen months, shared with the reports through the environment.
    @Query private var yearTransactions: [Transaction]

    init() {
        let thisMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let yearStart = Calendar.current.date(byAdding: .month, value: -13, to: thisMonth) ?? thisMonth
        _yearTransactions = Query(filter: #Predicate<Transaction> { $0.date >= yearStart })
    }

    var body: some View {
        VStack(spacing: 0) {
            // The title and the tabs stay at the top while the reports scroll below them.
            PinnedHeader("Reports") { sectionPicker }
            ScrollView {
                VStack(spacing: 14) {
                    grid(section.reports)
                }
                .padding(16)
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
    }

    // MARK: Sections

    private var sectionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReportSection.allCases) { item in
                        Button { section = item } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.callout.weight(section == item ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(section == item ? Color.accentColor.opacity(0.22) : Theme.panel, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(section.blurb).font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Reports laid out in rows: wide ones alone, the rest packed `columns` across. Any card left over stretches to
    /// fill its row, so no space is wasted.
    private func rows(of items: [ReportItem], columns: Int) -> [[ReportItem]] {
        var rows: [[ReportItem]] = []
        var buffer: [ReportItem] = []
        for item in items {
            if item.isWide {
                if !buffer.isEmpty { rows.append(buffer); buffer = [] }
                rows.append([item])
            } else {
                buffer.append(item)
                if buffer.count == columns { rows.append(buffer); buffer = [] }
            }
        }
        if !buffer.isEmpty { rows.append(buffer) }
        return rows
    }

    /// Every card is at least as big as its placeholder, so a report with no data yet takes the same room it will
    /// take once it fills in.
    @ViewBuilder
    private func card(_ item: ReportItem) -> some View {
        let minimum: CGFloat = item.isWide ? 330 : 290
        if let kind = item.trend {
            TrendChartCard(kind: kind, height: item.isWide ? 220 : 190).environment(\.reportCardMinHeight, minimum)
        } else if let built = ReportCards.view(section: section, title: item.title) {
            built.environment(\.reportCardMinHeight, minimum).environment(\.reportShape, item.shape)
        } else {
            ReportPlaceholderCard(report: item)
        }
    }

    private func grid(_ items: [ReportItem]) -> some View {
        // Three across when the page is wide enough.
        let columns = pageWidth >= 1000 ? 3 : 2
        return VStack(spacing: 14) {
            ForEach(Array(rows(of: items, columns: columns).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(row) { card($0) }
                }
                .fixedSize(horizontal: false, vertical: true)
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
