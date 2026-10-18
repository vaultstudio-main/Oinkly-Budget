import Foundation
import SwiftData
import PDFKit

#if DEBUG
/// Debug builds only: with the launch argument `-pdfTestDir <folder>`, prints what the Summary and every Reports section would
/// put in a PDF, and quits. It lets the printed output be checked without clicking through save panels.
@MainActor
enum PDFTestHook {
    static func runIfRequested(container: ModelContainer) {
        guard let folder = UserDefaults.standard.string(forKey: "pdfTestDir") else { return }
        Task { @MainActor in
            // Give the background ledger snapshot a moment to build.
            try? await Task.sleep(for: .seconds(6))
            let context = container.mainContext
            let source = PageDocuments.source(in: context)
            @MainActor func describe(_ name: String, _ document: ExportDocument) {
                let data = DocumentPDF.render(document, paper: .regional)
                let pages = PDFDocument(data: data)?.pageCount ?? 0
                print("=== \(name): \(data.count) bytes, \(pages) page(s)")
                print("title: \(document.title) | \(document.subtitle)")
                print("summary: \(document.summary.map { "\($0.label)=\($0.value)" }.joined(separator: "; "))")
                for section in document.sections {
                    switch section {
                    case .text(let text): print("text: \(text)")
                    case .table(let table):
                        print("table: \(table.title ?? "(untitled)") [\(table.rows.count) rows]")
                        for row in table.rows.prefix(4) { print("   \(row.joined(separator: " | "))") }
                        if let total = table.totalRow { print("   TOTAL \(total.joined(separator: " | "))") }
                    }
                }
            }
            describe("Summary", PageDocuments.summary(source))
            for section in ReportSection.allCases { describe("Report \(section.rawValue)", PageDocuments.report(section, source)) }
            fflush(stdout)
            exit(0)
        }
    }
}
#endif
