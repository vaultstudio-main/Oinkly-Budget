import Foundation

/// What a register can be narrowed to, from its Settings bubble: only some statuses, and only transactions with or without a
/// receipt. Nothing ticked in a group means that group lets everything through, so a register with no filter shows it all.
struct RegisterFilter: Equatable {
    /// The statuses to show. Empty shows every status.
    var states: Set<ReconcileState> = []
    var withReceipt = false
    var withoutReceipt = false

    var isActive: Bool { !states.isEmpty || withReceipt != withoutReceipt }

    func matches(_ transaction: Transaction) -> Bool {
        if !states.isEmpty && !states.contains(transaction.state) { return false }
        // Both ticked, or neither, is no narrowing at all.
        if withReceipt != withoutReceipt {
            let has = transaction.receiptData != nil
            if withReceipt != has { return false }
        }
        return true
    }

    /// What the page says it is showing, such as "Unreconciled, Pending · With Receipt". Empty when nothing is narrowed.
    var summary: String {
        var parts: [String] = []
        let ordered = ReconcileState.allCases.filter { states.contains($0) }
        if !ordered.isEmpty { parts.append(ordered.map(\.title).joined(separator: ", ")) }
        if withReceipt != withoutReceipt { parts.append(withReceipt ? "With Receipt" : "Without Receipt") }
        return parts.joined(separator: " · ")
    }
}
