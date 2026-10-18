import SwiftUI
import SwiftData
import Charts

// MARK: Reconciliation status

struct ReconciliationStatusReport: View {
    @Query private var allAccounts: [Account]

    private struct Slice: Identifiable {
        let name: String
        let count: Int
        let color: Color
        var id: String { name }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let accounts = allAccounts.live.filter { !$0.isClosed }
        var total = 0, unreconciled = 0, pending = 0
        if let snapshot {
            for account in accounts {
                guard let series = snapshot.accounts[account.persistentModelID] else { continue }
                total += series.dates.count
                unreconciled += series.unreconciledCount
                pending += series.pendingCount
            }
        }
        let reconciled = max(total - unreconciled - pending, 0)
        let slices = [Slice(name: "Reconciled", count: reconciled, color: ReconcileState.reconciled.color),
                      Slice(name: "Pending", count: pending, color: ReconcileState.pending.color),
                      Slice(name: "Unreconciled", count: unreconciled, color: ReconcileState.unreconciled.color)].filter { $0.count > 0 }

        return ReportPanel(title: "Reconciliation Status", summary: "How many of your transactions are matched to a statement, still pending or not yet checked.",
                           headline: total == 0 ? nil : ReportFormat.percent(Double(reconciled) / Double(total) * 100), headlineNote: total == 0 ? nil : "reconciled") {
            if snapshot == nil {
                ReportCalculating(height: 170)
            } else if total == 0 {
                ReportEmpty(message: "No transactions yet.", height: 170)
            } else {
                HStack(spacing: 18) {
                    Chart(slices) { slice in
                        SectorMark(angle: .value("Transactions", slice.count), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(slice.color)
                            .cornerRadius(3)
                    }
                    .frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.color).frame(width: 9, height: 9)
                                Text(slice.name)
                                Spacer()
                                Text("\(slice.count)").foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Unreconciled by account

struct UnreconciledByAccountReport: View {
    @Query private var allAccounts: [Account]

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let rows = allAccounts.live.filter { !$0.isClosed }.compactMap { account -> (Account, LedgerSnapshot.Series)? in
            guard let series = snapshot?.accounts[account.persistentModelID], series.unreconciledCount + series.pendingCount > 0 else { return nil }
            return (account, series)
        }
        .sorted { $0.1.unreconciledCount > $1.1.unreconciledCount }

        return ReportPanel(title: "Unreconciled by Account", summary: "What's still to match against a statement, account by account.") {
            if snapshot == nil {
                ReportCalculating(height: 170)
            } else if rows.isEmpty {
                ReportEmpty(message: "Everything is reconciled. Nothing waiting.", height: 170, shape: .table, title: "All clear")
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("ACCOUNT"); Text("UNRECONCILED").gridColumnAlignment(.trailing); Text("PENDING").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(3)
                    ForEach(rows.prefix(8), id: \.0.persistentModelID) { account, series in
                        GridRow {
                            Label(account.name, systemImage: account.type.symbol).lineLimit(1)
                            Text("\(series.unreconciledCount) · \(ReportFormat.money(series.unreconciledSum.doubleValue))")
                                .foregroundStyle(series.unreconciledCount > 0 ? ReconcileState.unreconciled.color : .secondary)
                            Text("\(series.pendingCount) · \(ReportFormat.money(series.pendingSum.doubleValue))")
                                .foregroundStyle(series.pendingCount > 0 ? ReconcileState.pending.color : .secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: Missing receipts

struct MissingReceiptsReport: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // No receipt and not marked as having none, newest first. Spending only, and not the two halves of a transfer.
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { $0.receiptData == nil && $0.noReceipt == false },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 800
        let candidates: [Transaction] = ((try? modelContext.fetch(descriptor)) ?? []).live
        let missing: [Transaction] = candidates.filter { $0.amount < 0 && !$0.isTransfer }
        let grouped: [String: [Transaction]] = Dictionary(grouping: missing) { $0.account?.name ?? "No account" }
        let byAccount: [(String, Int)] = grouped.map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }

        return ReportPanel(title: "Missing Receipts", summary: "Spending with no receipt attached and not marked as having none.",
                           headline: missing.isEmpty ? nil : "\(missing.count)\(candidates.count == 800 ? "+" : "")", headlineNote: missing.isEmpty ? nil : "to add or mark") {
            if missing.isEmpty {
                ReportEmpty(message: "Every spending transaction has a receipt or is marked as having none.", height: 170, shape: .table, title: "All clear")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(missing.prefix(5)) { transaction in
                        HStack {
                            Text(transaction.date, format: .dateTime.month(.abbreviated).day()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                            Text(transaction.payee.isEmpty ? "No payee" : transaction.payee).lineLimit(1)
                            Spacer()
                            Text(-transaction.amount, format: .appCurrency)
                        }
                        .font(.callout)
                    }
                    if !byAccount.isEmpty {
                        Divider()
                        Text("BY ACCOUNT").font(.caption2).foregroundStyle(.secondary)
                        ForEach(byAccount.prefix(3), id: \.0) { name, count in
                            HStack { Text(name).lineLimit(1); Spacer(); Text("\(count)").foregroundStyle(.secondary) }.font(.callout)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Duplicate payees

struct DuplicatePayeesReport: View {
    @Query(sort: \Payee.name) private var allPayees: [Payee]

    /// "Starbucks #1234", "STARBUCKS" and "Starbucks Coffee" all look alike once case, digits and punctuation are gone.
    private static func key(_ name: String) -> String {
        let lowered = name.lowercased().filter { $0.isLetter || $0 == " " }
        let words = lowered.split(separator: " ").filter { !["inc", "llc", "co", "the", "store"].contains($0) }
        return words.prefix(2).joined(separator: " ")
    }

    var body: some View {
        let payees = allPayees.live
        let groups = Dictionary(grouping: payees) { Self.key($0.name) }
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map { ($0.key, $0.value.map(\.name).sorted()) }
            .sorted { $0.1.count > $1.1.count }

        return ReportPanel(title: "Duplicate Payees", summary: "Payees that look like the same one written differently. Merge them so your reports group them together.",
                           headline: groups.isEmpty ? nil : "\(groups.count)", headlineNote: groups.isEmpty ? nil : "groups to clean up") {
            if payees.isEmpty {
                ReportEmpty(message: "No payees yet.", height: 170)
            } else if groups.isEmpty {
                ReportEmpty(message: "No look-alike payees. Your list is clean.", height: 170, shape: .table, title: "All clear")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups.prefix(5), id: \.0) { _, names in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(names.joined(separator: "  ·  ")).font(.callout).lineLimit(2)
                            Text("\(names.count) names for one payee").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
