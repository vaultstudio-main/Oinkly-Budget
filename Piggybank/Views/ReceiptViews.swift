import SwiftUI
import PhotosUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

/// Receipt photos are kept a bit larger than account photos so the print stays readable.
enum Receipt {
    static let maxPixelSize = 2000
    static func isPDF(_ data: Data?) -> Bool { data?.prefix(4) == Data("%PDF".utf8) }
}

/// Shows a PDF's pages, scrollable.
struct PDFPreview: View {
    let data: Data

    var body: some View {
        PDFHost(data: data)
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#if os(macOS)
private struct PDFHost: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(data: data)
    }
}
#else
private struct PDFHost: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(data: data)
    }
}
#endif

/// A photo or PDF of a receipt or bill: preview, add or replace, remove, and optionally "no receipt".
/// Used inside forms and in the register's receipt sheet.
struct ReceiptPicker: View {
    @Binding var data: Data?
    /// Pass a binding to offer "No receipt for this transaction".
    var noReceipt: Binding<Bool>?

    @State private var picked: PhotosPickerItem?
    @State private var choosingPDF = false
    @State private var importError: String?

    var body: some View {
        Group {
            if let data {
                if Receipt.isPDF(data) {
                    PDFPreview(data: data)
                } else if let image = AccountPhoto.image(from: data) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if noReceipt?.wrappedValue == true && data == nil {
                Text("Marked as having no receipt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(data == nil ? "Add Receipt Photo…" : "Replace with Photo…", systemImage: "doc.text.viewfinder")
                }
                Button {
                    choosingPDF = true
                } label: {
                    Label(data == nil ? "Attach PDF Bill…" : "Replace with PDF…", systemImage: "doc.richtext")
                }
            }

            if data != nil {
                Button("Remove Attachment", role: .destructive) { data = nil; picked = nil }
            }

            if let noReceipt, data == nil {
                Toggle("No receipt for this transaction", isOn: noReceipt)
            }

            if let importError {
                Text(importError).font(.footnote).foregroundStyle(.orange)
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let loaded = try? await item.loadTransferable(type: Data.self) {
                    data = AccountPhoto.compress(loaded, maxPixelSize: Receipt.maxPixelSize)
                    noReceipt?.wrappedValue = false
                }
            }
        }
        .fileImporter(isPresented: $choosingPDF, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let loaded = try? Data(contentsOf: url), Receipt.isPDF(loaded) else {
                    importError = "That file couldn't be read as a PDF."
                    return
                }
                importError = nil
                data = loaded
                noReceipt?.wrappedValue = false
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }
}

#if os(macOS)
/// The register's last column: "Add Receipt", "View Receipt", or "No Receipt" once marked.
struct ReceiptButton: View {
    let transaction: Transaction
    @State private var showing = false

    private var title: String {
        if transaction.receiptLocked { return "No Receipt" }
        if transaction.receiptData != nil { return "View Receipt" }
        return transaction.noReceipt ? "No Receipt" : "Add Receipt"
    }

    var body: some View {
        if transaction.isLive {
            Button(title) { showing = true }
                .buttonStyle(.link)
                .disabled(transaction.receiptLocked)
                .foregroundStyle(title == "No Receipt" ? Color.secondary : Color.accentColor)
                .sheet(isPresented: $showing) {
                    ReceiptSheet(transaction: transaction)
                }
        }
    }
}

private struct ReceiptSheet: View {
    let transaction: Transaction
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt").font(.title2.bold())
                Text("\(transaction.payee.isEmpty ? "Transaction" : transaction.payee) · \(transaction.date.formatted(date: .abbreviated, time: .omitted)) · \(transaction.amount.formatted(.appCurrency))")
                    .foregroundStyle(.secondary)
            }
            ReceiptPicker(
                data: Binding(
                    get: { transaction.isLive ? transaction.receiptData : nil },
                    set: { new in
                        guard transaction.isLive else { return }
                        transaction.receiptData = new
                        modelContext.saveNow()
                    }
                ),
                noReceipt: Binding(
                    get: { transaction.isLive ? transaction.noReceipt : false },
                    set: { new in
                        guard transaction.isLive else { return }
                        transaction.noReceipt = new
                        modelContext.saveNow()
                    }
                )
            )
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
#endif
