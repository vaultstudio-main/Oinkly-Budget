import Foundation
import SwiftData

/// Cash on Hand is the one account every Oinkly Budget has. It can't be deleted or given another type, so there is always
/// somewhere to record the cash you carry.
extension Account {
    static let defaultName = "Cash on Hand"

    /// Makes sure there is exactly one default account: the existing one, an old cash account adopted as the default,
    /// or a new Cash on Hand. Safe to run on every launch, and after anything that deletes accounts.
    @discardableResult
    static func ensureDefault(in context: ModelContext) -> Account {
        let all = ((try? context.fetch(FetchDescriptor<Account>())) ?? []).filter(\.isLive)
        let flagged = all.filter(\.isDefault)
        if let keep = flagged.first {
            // Two devices, or a restore, can leave more than one. Only the first stays the default.
            for extra in flagged.dropFirst() { extra.isDefault = false }
            keep.type = .cash
            keep.isClosed = false
            return keep
        }
        if let cash = all.first(where: { $0.type == .cash }) {
            cash.isDefault = true
            cash.isClosed = false
            return cash
        }
        let made = Account(name: defaultName, type: .cash, openingBalance: 0)
        made.isDefault = true
        context.insert(made)
        return made
    }
}

extension Sequence where Element == Account {
    /// The accounts you added yourself, without the built-in Cash on Hand.
    var addedByUser: [Account] { filter { !$0.isDefault } }
}
