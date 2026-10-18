import SwiftUI
import SwiftData
import Charts

/// The shell every built report sits in: a title, what it shows, an optional headline figure, then the content.
struct ReportPanel<Content: View>: View {
    let title: String
    let summary: String
    var headline: String?
    var headlineNote: String?
    /// True when the numbers are made up to show what the report will look like.
    var sample = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if sample {
                            Text("Sample")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// A line of text where a chart would go, for a report that has nothing to show yet.
struct ReportEmpty: View {
    let message: String
    var height: CGFloat = 150
    /// The faint outline drawn behind the message, so an empty report still shows its shape.
    var shape: ReportShape = .line

    var body: some View {
        ZStack {
            GhostView(shape: shape, projects: false)
                .opacity(0.8)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
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
