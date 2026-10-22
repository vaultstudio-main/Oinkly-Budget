import Foundation
import SwiftData

/// One part of a split while it is being edited: not saved until the transaction is.
struct SplitDraft: Identifiable {
    var id = UUID()
    var category: Category?
    /// Always positive while editing. The sign comes from the transaction when it is saved.
    var amount: Decimal?
    var memo = ""
}

/// Dividing one transaction across several categories.
enum Splits {
    /// The least parts a split can have. One part is just an ordinary transaction.
    static let minimumParts = 2

    static func allocated(_ parts: [SplitDraft]) -> Decimal {
        parts.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
    }

    /// What is still to be given a category. Zero when the parts add up.
    static func remaining(_ parts: [SplitDraft], of total: Decimal) -> Decimal {
        total - allocated(parts)
    }

    /// Every part has a category and an amount, there are at least two, and they add up to the total to the cent.
    static func isValid(_ parts: [SplitDraft], total: Decimal) -> Bool {
        guard total > 0, parts.count >= minimumParts else { return false }
        guard parts.allSatisfy({ $0.category != nil && ($0.amount ?? 0) > 0 }) else { return false }
        return remaining(parts, of: total) == 0
    }

    /// The first two parts for a transaction that is about to be split: what is chosen so far, and an empty one.
    static func starting(category: Category?, total: Decimal?) -> [SplitDraft] {
        [SplitDraft(category: category, amount: total), SplitDraft()]
    }

    /// The parts of a transaction that is already split, in the order they were entered, as positive amounts.
    static func drafts(of transaction: Transaction) -> [SplitDraft] {
        transaction.splits.sorted { $0.order != $1.order ? $0.order < $1.order : $0.createdAt < $1.createdAt }
            .map { SplitDraft(category: $0.category, amount: abs($0.amount), memo: $0.memo) }
    }

    /// Replaces a transaction's parts with `parts`, signed like the transaction. The transaction's own category is
    /// cleared, since each part has its own.
    @MainActor
    static func apply(_ parts: [SplitDraft], to transaction: Transaction, isPayment: Bool, in context: ModelContext) {
        removeAll(from: transaction, in: context)
        for (index, part) in parts.enumerated() {
            let amount = part.amount ?? 0
            let split = TransactionSplit(transaction: transaction, category: part.category, amount: isPayment ? -amount : amount,
                                         memo: part.memo, order: index)
            context.insert(split)
        }
        transaction.category = nil
    }

    /// Turns a split transaction back into an ordinary one.
    @MainActor
    static func removeAll(from transaction: Transaction, in context: ModelContext) {
        for split in transaction.splits { context.delete(split) }
    }
}

extension Transaction {
    /// Divided across more than one category.
    var isSplit: Bool { isLive && !splits.isEmpty }

    /// Where the money went: one entry for an ordinary transaction, one per part for a split. Reports use this so
    /// each part counts under its own category and the total is never counted twice.
    var categoryParts: [(category: Category?, amount: Decimal)] {
        guard isSplit else { return [(category, amount)] }
        return splits.sorted { $0.order < $1.order }.map { ($0.category, $0.amount) }
    }

    /// "Split (3)" for a split transaction, otherwise nil.
    var splitTitle: String? { isSplit ? "Split (\(splits.count))" : nil }

    /// What the Category column reads: a locked title, "Split (n)", or the category's name.
    var categoryTitle: String {
        fixedCategoryTitle ?? splitTitle ?? category?.name ?? ""
    }

    /// A transaction that can be divided: an ordinary payment or deposit, not a transfer, payment, withdrawal,
    /// opening deposit or investment entry.
    var canSplit: Bool {
        isLive && fixedCategoryTitle == nil && account?.supportsHoldings != true
    }
}
