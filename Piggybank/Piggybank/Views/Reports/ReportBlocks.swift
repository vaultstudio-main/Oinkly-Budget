import SwiftUI
import SwiftData
import Charts

private struct ReportCardMinHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The least height a report card takes. The Reports page sets it to the size of a placeholder.
    var reportCardMinHeight: CGFloat {
        get { self[ReportCardMinHeightKey.self] }
        set { self[ReportCardMinHeightKey.self] = newValue }
    }
}

/// The shell every built report sits in: a title, what it shows, an optional headline figure, then the content.
struct ReportPanel<Content: View>: View {
    @Environment(\.reportCardMinHeight) private var minHeight
    let title: String
    let summary: String
    var headline: String?
    var headlineNote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let headline {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(headline).font(.title3.bold())
                        if let headlineNote { Text(headlineNote).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A small key under a chart: solid for what happened, dashed for the projection.
struct ReportKey: View {
    struct Item: Identifiable {
        let color: Color
        let text: String
        var dashed = false
        var id: String { text }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(item.color, style: StrokeStyle(lineWidth: 1.5, dash: item.dashed ? [3, 2] : []))
                        .background(item.dashed ? Color.clear : item.color, in: RoundedRectangle(cornerRadius: 1))
                        .frame(width: 14, height: 5)
                    Text(item.text)
                }
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct ReportShapeKey: EnvironmentKey {
    static let defaultValue: ReportShape = .line
}

extension EnvironmentValues {
    /// The shape of the report being drawn, so an empty one can show the right outline.
    var reportShape: ReportShape {
        get { self[ReportShapeKey.self] }
        set { self[ReportShapeKey.self] = newValue }
    }
}

/// What a report shows when it has no data yet: its usual outline, faint, with a note on what it needs. It stretches to
/// fill the card, so the card keeps the size it will have once it fills in.
struct ReportEmpty: View {
    @Environment(\.reportShape) private var inheritedShape
    let message: String
    /// The least height, for cards drawn outside the Reports page.
    var height: CGFloat = 150
    /// The faint outline drawn behind the message. By default the shape of the report it sits in.
    var shape: ReportShape?
    /// "Needs more data" while the report is waiting for data; something like "All clear" when there is just nothing to flag.
    var title: String? = "Needs more data"

    var body: some View {
        ZStack {
            GhostView(shape: shape ?? inheritedShape, projects: false)
                .opacity(0.8)
            VStack(spacing: 4) {
                if let title { Text(title).font(.callout.weight(.semibold)) }
                Text(message).font(.callout).foregroundStyle(.secondary)
                if title == "Needs more data" {
                    Text("This builds itself over time as you add transactions.").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: .infinity)
    }
}

/// Shown in place of a chart while the ledger snapshot is still being built.
struct ReportCalculating: View {
    var height: CGFloat = 150

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Calculating…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

/// Number formatting for chart axes and tight spaces.
enum ReportFormat {
    static func compact(_ value: Double) -> String { value.formatted(.number.notation(.compactName)) }
    static func money(_ value: Double) -> String { Decimal(value).formatted(.appCurrency) }
    static func percent(_ value: Double, digits: Int = 0) -> String { "\(value.formatted(.number.precision(.fractionLength(digits))))%" }
    static func month(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).year()) }

    /// "+$120.00" or "−$40.00".
    static func signed(_ value: Decimal) -> String {
        let text = abs(value).formatted(.appCurrency)
        return value >= 0 ? "+\(text)" : "−\(text)"
    }
}

/// A coloured figure with a label above, used in rows of key numbers inside a report.
struct ReportFigure: View {
    let label: String
    let value: String
    var note: String?
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
