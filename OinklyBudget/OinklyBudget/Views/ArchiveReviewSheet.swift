import SwiftUI
import SwiftData

/// The year-end question about archived accounts, which can also be opened from Manage Accounts ▸ Archived: keep them, or delete them for good.
/// Archived accounts are kept because their transactions are part of the history behind net worth, debts and interest, so deleting them is
/// said plainly and asked about twice.
struct ArchiveReviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allAccounts: [Account]
    @State private var confirming = false

    private var archived: [Account] { allAccounts.live.filter(\.isClosed) }
    private var transactionCount: Int { archived.reduce(0) { $0 + $1.transactions.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your archive", systemImage: "archivebox.fill").font(.title3.weight(.semibold))
            Text("These accounts are paid off or ended, and are kept out of sight. Their transactions are kept too, so the history behind your net worth, debts and interest stays right.")
            if archived.isEmpty {
                Text("Nothing is archived.").foregroundStyle(.secondary)
            } else {
                List(archived) { account in
                    HStack {
                        Image(systemName: account.type.symbol).foregroundStyle(.secondary).frame(width: 22)
                        Text(account.name)
                        Spacer()
                        Text("\(account.transactions.count) transaction\(account.transactions.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(height: min(CGFloat(archived.count) * 30 + 12, 220))
            }
            Text("Keep them and nothing changes. Delete them and these accounts and their \(transactionCount.formatted()) transaction\(transactionCount == 1 ? "" : "s") are removed for good: reports for past months will change, for example your net worth history will no longer include the debt they carried. You are asked again next year end.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Delete Archived Accounts…", role: .destructive) { confirming = true }
                    .disabled(archived.isEmpty)
                Spacer()
                Button("Keep Them") { ArchiveReview.markReviewed(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 540)
        .confirmationDialog("Delete \(archived.count) archived account\(archived.count == 1 ? "" : "s")?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete for Good", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also deletes \(transactionCount.formatted()) transaction\(transactionCount == 1 ? "" : "s") and can't be undone. Past reports will change.")
        }
    }

    private func deleteAll() {
        let doomed = archived
        ArchiveReview.markReviewed()
        dismiss()
        DataDeletion.afterLeavingAccountPages {
            for account in doomed { modelContext.delete(account) }
            modelContext.saveNow()
        }
    }
}
