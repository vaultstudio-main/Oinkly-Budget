import SwiftUI
import SwiftData

/// A read-only close look at one transaction, in its own window. Double-click a row to open it; several can stay
/// open side by side. Edit… opens the usual edit sheet, so looking never changes anything.
struct TransactionDetailWindow: View {
    let id: PersistentIdentifier?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    private var transaction: Transaction? {
        guard let id, let found = modelContext.model(for: id) as? Transaction, found.isLive else { return nil }
        return found
    }

    var body: some View {
        Group {
            if let transaction, let account = transaction.account {
                content(transaction, account: account)
            } else {
                ContentUnavailableView("Transaction Not Found", systemImage: "questionmark.folder",
                                       description: Text("It may have been deleted."))
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .background(Theme.background)
    }

    private func otherSide(of transaction: Transaction) -> Account? {
        guard let transferID = transaction.transferID else { return nil }
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == transferID })
        let mine = transaction.persistentModelID
        return (try? modelContext.fetch(descriptor))?.first { $0.persistentModelID != mine && $0.isLive }?.account
    }

    @ViewBuilder
    private func content(_ transaction: Transaction, account: Account) -> some View {
        let investment = account.supportsHoldings && !transaction.isTransfer
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transaction.payee.isEmpty ? "Transaction" : transaction.payee).font(.title.bold())
                        Text(transaction.amount, format: .appCurrency)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(transaction.amount > 0 ? Theme.green : (transaction.amount < 0 ? Theme.red : Color.secondary))
                    }

                    VStack(spacing: 0) {
                        row("Date", transaction.date.formatted(date: .complete, time: .omitted))
                        row("Account", account.name)
                        if let other = otherSide(of: transaction) {
                            row(transaction.amount < 0 ? "Transferred to" : "Transferred from", other.name)
                        }
                        if investment {
                            row("Type", InvestmentType.of(transaction).title)
                        } else {
                            row("Category", transaction.fixedCategoryTitle ?? transaction.category?.name ?? "None")
                            row("Method", account.lockedPaymentType?.title ?? transaction.paymentTitle)
                            if !transaction.checkNumber.isEmpty { row("Check number", transaction.checkNumber) }
                        }
                        if let bill = transaction.paidBill {
                            row("Paid bill", bill.name)
                        }
                        row("Status", transaction.state.title)
                        if !transaction.memo.isEmpty { row("Memo", transaction.memo) }
                    }
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))

                    if let data = transaction.receiptData {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Receipt").font(.headline)
                            if Receipt.isPDF(data) {
                                PDFPreview(data: data).frame(height: 520)
                            } else if let image = AccountPhoto.image(from: data) {
                                image.resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    } else if transaction.noReceipt {
                        Text("Marked as having no receipt.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Button("Print PDF", systemImage: "printer") {
                    guard transaction.isLive else { return }
                    PDFSaver.save(DocumentBuilders.transaction(transaction),
                                  suggestedName: "\(transaction.payee.isEmpty ? "Transaction" : transaction.payee) – \(transaction.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Edit…") { editing = true }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .sheet(isPresented: $editing) {
            if transaction.isLive {
                EditTransactionSheet(transaction: transaction, account: account, categories: allCategories.live)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
