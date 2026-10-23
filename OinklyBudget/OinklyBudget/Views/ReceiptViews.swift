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
    var height: CGFloat = 360

    var body: some View {
        PDFHost(data: data)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

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

/// A photo or PDF of a receipt or bill, laid out to take little room: Add Receipt Photo and Attach PDF Bill side by side, a viewing area
/// of one set size showing what is attached, and Remove Attachment or "No receipt" under it. Used inside forms and in the register's
/// receipt sheet.
struct ReceiptPicker: View {
    @Binding var data: Data?
    /// Pass a binding to offer "No receipt for this transaction".
    var noReceipt: Binding<Bool>?

    /// The height of the viewing area, the same with or without something attached, so the form never jumps.
    var viewingHeight: CGFloat = 170

    @State private var picked: PhotosPickerItem?
    @State private var choosingPDF = false
    @State private var importError: String?

    private var markedNone: Bool { noReceipt?.wrappedValue == true && data == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(data == nil ? "Add Receipt Photo" : "Replace with Photo", systemImage: "doc.text.viewfinder")
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    choosingPDF = true
                } label: {
                    Label(data == nil ? "Add PDF Bill" : "Replace with PDF", systemImage: "doc.richtext")
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .disabled(markedNone)

            viewing

            if noReceipt != nil || data != nil {
                HStack {
                    if let noReceipt, data == nil { Toggle("No receipt for this transaction", isOn: noReceipt) }
                    Spacer()
                    if data != nil { Button("Remove Attachment", role: .destructive) { data = nil; picked = nil } }
                }
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

    /// What is attached, in a box of one set height; a plain note in the same box when nothing is.
    private var viewing: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06))
            if let data, Receipt.isPDF(data) {
                PDFPreview(data: data, height: viewingHeight)
            } else if let data, let image = AccountPhoto.image(from: data) {
                image.resizable().scaledToFit().padding(4)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: markedNone ? "nosign" : "doc.text.viewfinder").font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                    Text(markedNone ? "Marked as having no receipt." : "Nothing attached. Add a photo of the receipt or a PDF of the bill.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: viewingHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// The receipt's own column down the right side of a transaction window, beside the form: Add Receipt Photo and Add PDF Bill side by
/// side, and a viewing area under them. Where the transaction can't have a receipt it says so, so the window keeps its shape.
struct ReceiptColumn: View {
    let supported: Bool
    var title = "Receipt"
    @Binding var data: Data?
    var noReceipt: Binding<Bool>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if supported {
                ReceiptPicker(data: $data, noReceipt: noReceipt, viewingHeight: 330)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "nosign").font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                    Text("This kind of transaction doesn't take a receipt.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 340)
    }
}

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
