import SwiftUI

/// One headline number: a small title, a big value and a short note. Every report uses it, so they all match.
struct StatTile<Value: View, Note: View>: View {
    let title: String
    @ViewBuilder let value: Value
    @ViewBuilder let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
            value
                .font(.title2.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            note
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .tileStyle()
    }
}

/// Lays tiles out in equal columns, four across when there's room and two by two otherwise, with every tile the
/// same width and height so the row fills the card area evenly.
struct StatGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        TileGridLayout { content }
    }
}

private struct TileGridLayout: Layout {
    var spacing: CGFloat = 12

    private func metrics(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (columns: Int, cellWidth: CGFloat, rowHeight: CGFloat, rows: Int, width: CGFloat) {
        let width = proposal.width ?? 360
        let columns = width >= 640 ? 4 : 2
        let cellWidth = max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
        let rowHeight = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }.max() ?? 0
        let rows = (subviews.count + columns - 1) / columns
        return (columns, cellWidth, rowHeight, rows, width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = metrics(proposal, subviews)
        let height = CGFloat(m.rows) * m.rowHeight + CGFloat(max(m.rows - 1, 0)) * spacing
        return CGSize(width: m.width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = metrics(ProposedViewSize(width: bounds.width, height: bounds.height), subviews)
        for (index, subview) in subviews.enumerated() {
            let column = index % m.columns
            let row = index / m.columns
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(column) * (m.cellWidth + spacing), y: bounds.minY + CGFloat(row) * (m.rowHeight + spacing)),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: m.cellWidth, height: m.rowHeight)
            )
        }
    }
}

/// What a card shows when there is nothing to put in it yet, so the card stays on the page and says why.
struct NoDataNote: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

/// A row of tiles with no numbers yet, laid out exactly like the real ones.
struct PlaceholderTiles: View {
    let titles: [String]

    var body: some View {
        StatGrid {
            ForEach(titles, id: \.self) { title in
                StatTile(title: title) {
                    Text("—").foregroundStyle(.secondary)
                } note: {
                    Text("no data yet")
                }
            }
        }
    }
}
