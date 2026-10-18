import SwiftUI

/// A report that isn't built yet. It has the size and shape the finished report will have, so the page already looks
/// like the real thing, and says what the report will show.
struct ReportPlaceholderCard: View {
    let report: ReportItem
    var showsProjection = true

    private var shows: Bool { report.projects && showsProjection }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: report.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title).font(.headline)
                    Text(report.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("Coming soon")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            GhostView(shape: report.shape, projects: shows)
                .frame(height: report.isWide ? 210 : 170)

            HStack(spacing: 6) {
                legend(color: .secondary.opacity(0.5), text: "History")
                if shows { legend(color: .accentColor.opacity(0.6), text: "Next 6 months", dashed: true) }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func legend(color: Color, text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
                .background(dashed ? Color.clear : color, in: RoundedRectangle(cornerRadius: 2))
                .frame(width: 14, height: 8)
            Text(text)
        }
    }
}

/// The grey outline of a chart, table, ring or row of tiles. With a projection, the right third is a dashed zone.
private struct GhostView: View {
    let shape: ReportShape
    let projects: Bool

    private let bars: [CGFloat] = [0.45, 0.6, 0.5, 0.72, 0.58, 0.8, 0.66, 0.74, 0.62, 0.84, 0.7, 0.9]
    private let points: [CGFloat] = [0.35, 0.42, 0.4, 0.5, 0.48, 0.58, 0.55, 0.64, 0.62, 0.7, 0.68, 0.78]
    private let ghost = Color.secondary.opacity(0.16)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05))
            switch shape {
            case .bars: barsView
            case .line: lineView
            case .table: tableView
            case .tiles: tilesView
            case .ring: ringView
            }
        }
    }

    /// The dashed band over the last six of twelve slots.
    private func projectionBand(_ size: CGSize) -> some View {
        let width = size.width * 0.34
        return RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .frame(width: width, height: size.height - 16)
            .position(x: size.width - width / 2 - 8, y: size.height / 2)
    }

    private var barsView: some View {
        GeometryReader { geo in
            ZStack {
                if projects { projectionBand(geo.size) }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(bars.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(projects && index >= 8 ? Color.accentColor.opacity(0.25) : ghost)
                            .frame(height: (geo.size.height - 36) * bars[index])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var lineView: some View {
        GeometryReader { geo in
            ZStack {
                if projects { projectionBand(geo.size) }
                Path { path in
                    let step = (geo.size.width - 32) / CGFloat(points.count - 1)
                    for (index, value) in points.enumerated() {
                        let point = CGPoint(x: 16 + step * CGFloat(index), y: geo.size.height - 20 - (geo.size.height - 40) * value)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private var tableView: some View {
        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 12) {
                    Circle().fill(ghost).frame(width: 18, height: 18)
                    Capsule().fill(ghost).frame(width: CGFloat(110 + (row * 37) % 90), height: 9)
                    Spacer()
                    Capsule().fill(ghost).frame(width: 56, height: 9)
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var tilesView: some View {
        HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(ghost).frame(width: 50, height: 7)
                    Capsule().fill(ghost).frame(width: 80, height: 16)
                    Capsule().fill(ghost).frame(width: 60, height: 7)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
    }

    private var ringView: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(ghost, lineWidth: 22)
                Circle().trim(from: 0, to: 0.64).stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if projects {
                    Circle().trim(from: 0.64, to: 0.8)
                        .stroke(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 22, lineCap: .round, dash: [4, 6]))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 8) {
                        Circle().fill(ghost).frame(width: 10, height: 10)
                        Capsule().fill(ghost).frame(width: CGFloat(90 + row * 18), height: 8)
                    }
                }
            }
        }
        .padding(18)
    }
}
