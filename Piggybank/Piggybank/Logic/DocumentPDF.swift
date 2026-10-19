import AppKit
import PDFKit

/// A column of a table in an exported document. A column has a fixed width, or shares what is left with the other
/// flexible columns in proportion to `flex`.
struct DocColumn {
    var title: String
    var width: CGFloat?
    var flex: CGFloat = 1
    var rightAligned = false

    static func fixed(_ title: String, _ width: CGFloat, right: Bool = false) -> DocColumn {
        DocColumn(title: title, width: width, rightAligned: right)
    }

    static func flexible(_ title: String, _ flex: CGFloat = 1, right: Bool = false) -> DocColumn {
        DocColumn(title: title, width: nil, flex: flex, rightAligned: right)
    }
}

struct DocTable {
    var title: String?
    var columns: [DocColumn]
    var rows: [[String]]
    /// A bold line after the last row, such as a total.
    var totalRow: [String]?
    /// Shown instead of the rows when there are none.
    var emptyNote = "Nothing to show."
}

/// An image or PDF (a receipt, a bill) that gets pages of its own after the text.
struct DocAttachment {
    var title: String
    var data: Data
}

enum DocSection {
    case table(DocTable)
    case text(String)
}

/// Everything an exported document shows: a title block, a row of headline figures, then sections that flow over as
/// many pages as they need. Built from the database first, so drawing never touches it.
struct ExportDocument {
    var title: String
    var subtitle: String
    var summary: [(label: String, value: String)] = []
    var sections: [DocSection] = []
    var attachments: [DocAttachment] = []
}

/// Draws an `ExportDocument` as a PDF in plain black and grey, so it prints well. The same look is used for every
/// export: account statements, a transaction, reports, bills and the budget.
@MainActor
enum DocumentPDF {
    private static let margin: CGFloat = 40
    private static let rowHeight: CGFloat = 15
    private static let footerHeight: CGFloat = 28
    /// A fixed dark grey. System colours change with light and dark mode, which would make printed text pale.
    private static let grey = NSColor(white: 0.38, alpha: 1)
    /// The color of titles and table headings: black for the plain style, a deep blue for the color style.
    private static var accent: NSColor {
        AppSettings.shared.exportStyle == .color ? NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.62, alpha: 1) : .black
    }
    /// Table heading text and the rules under them. Blue in the color style, grey in the plain one.
    private static var headingColor: NSColor {
        AppSettings.shared.exportStyle == .color ? NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.62, alpha: 1) : grey
    }

    static func render(_ document: ExportDocument, paper: PaperSize) -> Data {
        // Lay everything out once to count the pages, then again to draw with the real "Page x of y".
        var counter = Page(document: document, paper: paper, context: nil, totalPages: 0)
        counter.layout()
        let total = counter.pageCount

        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: paper.size)
        let info = [kCGPDFContextTitle: "\(document.title), \(document.subtitle)", kCGPDFContextCreator: "Oinkly Budget"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info) else { return Data() }
        var drawer = Page(document: document, paper: paper, context: context, totalPages: total)
        drawer.layout()
        context.closePDF()
        return data as Data
    }

    // MARK: Layout and drawing

    private struct Page {
        let document: ExportDocument
        let paper: PaperSize
        let context: CGContext?
        let totalPages: Int
        var pageCount = 0
        private var y: CGFloat = 0
        private var open = false

        init(document: ExportDocument, paper: PaperSize, context: CGContext?, totalPages: Int) {
            self.document = document
            self.paper = paper
            self.context = context
            self.totalPages = totalPages
        }

        private var width: CGFloat { paper.size.width - margin * 2 }
        private var bottom: CGFloat { paper.size.height - margin - footerHeight }

        mutating func layout() {
            newPage()
            drawHeader()
            for section in document.sections {
                switch section {
                case .table(let table): drawTable(table)
                case .text(let text): drawText(text)
                }
            }
            closePage()
            for attachment in document.attachments { drawAttachment(attachment) }
        }

        // MARK: Pages

        private mutating func newPage() {
            if open { closePage() }
            pageCount += 1
            open = true
            y = margin
            guard let context else { return }
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: paper.size.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        }

        private mutating func closePage() {
            guard open else { return }
            open = false
            guard let context else { return }
            drawFooter()
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }

        private func drawFooter() {
            let footerY = paper.size.height - margin + 6
            let left = "\(document.title) · \(document.subtitle) · made \(Date.now.formatted(.dateTime.month(.abbreviated).day().year()))"
            text(left, in: CGRect(x: margin, y: footerY, width: width * 0.75, height: 12), size: 7.5, color: grey)
            text("Page \(pageCount) of \(totalPages)", in: CGRect(x: margin + width * 0.75, y: footerY, width: width * 0.25, height: 12),
                 size: 7.5, color: grey, right: true)
        }

        // MARK: Header

        private mutating func drawHeader() {
            text(document.title, in: CGRect(x: margin, y: y, width: width, height: 24), size: 19, weight: .bold, color: accent)
            y += 22
            text(document.subtitle, in: CGRect(x: margin, y: y + 2, width: width, height: 16), size: 11, color: grey)
            y += 30
            guard !document.summary.isEmpty else { y += 4; return }
            let cell = width / CGFloat(min(document.summary.count, 4))
            for (index, item) in document.summary.enumerated() {
                let column = index % 4
                if index > 0 && column == 0 { y += 34 }
                let x = margin + cell * CGFloat(column)
                text(item.label, in: CGRect(x: x, y: y, width: cell - 8, height: 12), size: 8, color: grey)
                text(item.value, in: CGRect(x: x, y: y + 12, width: cell - 8, height: 16), size: 12, weight: .semibold)
            }
            y += 46
        }

        // MARK: Text

        private mutating func drawText(_ string: String) {
            let font = NSFont.systemFont(ofSize: 9)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: style]
            let bounds = NSString(string: string).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                               options: [.usesLineFragmentOrigin], attributes: attributes)
            let height = ceil(bounds.height) + 6
            if y + height > bottom { newPage() }
            if context != nil { NSString(string: string).draw(in: CGRect(x: margin, y: y, width: width, height: height), withAttributes: attributes) }
            y += height + 6
        }

        // MARK: Tables

        private func widths(_ columns: [DocColumn]) -> [CGFloat] {
            let fixed = columns.reduce(0) { $0 + ($1.width ?? 0) }
            let flexTotal = columns.filter { $0.width == nil }.reduce(0) { $0 + $1.flex }
            let rest = max(width - fixed, 60)
            return columns.map { $0.width ?? (flexTotal > 0 ? rest * $0.flex / flexTotal : 0) }
        }

        private mutating func drawTable(_ table: DocTable) {
            let widths = widths(table.columns)
            if let title = table.title {
                if y + 60 > bottom { newPage() }
                y += 6
                text(title, in: CGRect(x: margin, y: y, width: width, height: 18), size: 12, weight: .semibold, color: accent)
                y += 22
            }
            func headings() {
                var x = margin
                for (index, column) in table.columns.enumerated() {
                    text(column.title.uppercased(), in: CGRect(x: x, y: y + 2, width: widths[index] - 6, height: rowHeight),
                         size: 7.5, weight: .semibold, color: headingColor, right: column.rightAligned)
                    x += widths[index]
                }
                line(from: margin, to: margin + width, y: y + rowHeight, alpha: 0.55, thickness: 0.8)
                y += rowHeight + 4
            }
            if y + rowHeight * 3 > bottom { newPage() }
            headings()
            if table.rows.isEmpty {
                text(table.emptyNote, in: CGRect(x: margin, y: y + 4, width: width, height: 16), size: 10, color: grey)
                y += 24
            }
            for row in table.rows {
                if y + rowHeight > bottom { newPage(); headings() }
                drawRow(row, columns: table.columns, widths: widths, bold: false)
            }
            if let total = table.totalRow {
                if y + rowHeight > bottom { newPage(); headings() }
                line(from: margin, to: margin + width, y: y, alpha: 0.55, thickness: 0.8)
                drawRow(total, columns: table.columns, widths: widths, bold: true)
            }
            y += 14
        }

        private mutating func drawRow(_ row: [String], columns: [DocColumn], widths: [CGFloat], bold: Bool) {
            var x = margin
            for (index, column) in columns.enumerated() {
                let value = index < row.count ? row[index] : ""
                text(value, in: CGRect(x: x, y: y + 1.5, width: widths[index] - 6, height: rowHeight),
                     size: 8.5, weight: bold ? .semibold : .regular, right: column.rightAligned)
                x += widths[index]
            }
            line(from: margin, to: margin + width, y: y + rowHeight, alpha: 0.12, thickness: 0.5)
            y += rowHeight
        }

        // MARK: Attachments

        private mutating func drawAttachment(_ attachment: DocAttachment) {
            let pdf = PDFDocument(data: attachment.data)
            let image = pdf == nil ? NSImage(data: attachment.data) : nil
            guard pdf != nil || image != nil else { return }
            let pages = pdf?.pageCount ?? 1
            for index in 0..<pages {
                newPage()
                text(pages > 1 ? "\(attachment.title) (page \(index + 1) of \(pages))" : attachment.title,
                     in: CGRect(x: margin, y: y, width: width, height: 20), size: 12, weight: .semibold)
                y += 26
                let area = CGRect(x: margin, y: y, width: width, height: bottom - y)
                if let context {
                    if let page = pdf?.page(at: index) {
                        draw(pdfPage: page, in: area, context: context)
                    } else if let image {
                        draw(image: image, in: area)
                    }
                }
                closePage()
            }
        }

        private func fit(_ size: CGSize, in area: CGRect) -> CGRect {
            guard size.width > 0, size.height > 0 else { return area }
            let scale = min(area.width / size.width, area.height / size.height, 1)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            return CGRect(x: area.minX + (area.width - fitted.width) / 2, y: area.minY, width: fitted.width, height: fitted.height)
        }

        private func draw(image: NSImage, in area: CGRect) {
            let target = fit(image.size, in: area)
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        private func draw(pdfPage: PDFPage, in area: CGRect, context: CGContext) {
            let bounds = pdfPage.bounds(for: .mediaBox)
            let target = fit(bounds.size, in: area)
            context.saveGState()
            // The page is drawn upright inside the flipped drawing space.
            context.translateBy(x: target.minX, y: target.maxY)
            context.scaleBy(x: target.width / bounds.width, y: -target.height / bounds.height)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            pdfPage.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }

        // MARK: Drawing helpers

        private func line(from x0: CGFloat, to x1: CGFloat, y: CGFloat, alpha: CGFloat, thickness: CGFloat) {
            guard let context else { return }
            context.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(thickness)
            context.move(to: CGPoint(x: x0, y: y))
            context.addLine(to: CGPoint(x: x1, y: y))
            context.strokePath()
        }

        private func text(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
                          color: NSColor = .black, right: Bool = false) {
            guard context != nil else { return }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            style.alignment = right ? .right : .left
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: style,
            ]
            NSString(string: string).draw(in: rect, withAttributes: attributes)
        }
    }
}
