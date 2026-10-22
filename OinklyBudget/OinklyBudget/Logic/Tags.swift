import Foundation
import SwiftData

/// Labels on transactions, such as "Vacation" or "Reimbursable".
enum Tags {
    /// Colors a tag can be given.
    static let palette = ["007AFF", "34C759", "FF9500", "FF3B30", "AF52DE", "5AC8FA", "FF2D55", "A2845E", "8E8E93"]

    static let maxNameLength = 24

    /// A name with the spaces trimmed and shortened to the limit.
    static func clean(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    /// For comparing names: "Vacation", "vacation " and "VACATION" are the same tag.
    static func key(_ name: String) -> String { clean(name).lowercased() }

    static func find(_ name: String, in tags: [Tag]) -> Tag? {
        let wanted = key(name)
        guard !wanted.isEmpty else { return nil }
        return tags.first { $0.isLive && key($0.name) == wanted }
    }

    /// The tags for these names, making any that don't exist yet. Blank and repeated names are skipped.
    @MainActor
    static func resolve(_ names: [String], in context: ModelContext) -> [Tag] {
        var existing = ((try? context.fetch(FetchDescriptor<Tag>())) ?? []).live
        var result: [Tag] = []
        for name in names {
            let cleaned = clean(name)
            guard !cleaned.isEmpty else { continue }
            if let tag = find(cleaned, in: existing) {
                if !result.contains(where: { $0 === tag }) { result.append(tag) }
            } else {
                let colorHex = palette[existing.count % palette.count]
                let made = Tag(name: cleaned, colorHex: colorHex)
                context.insert(made)
                existing.append(made)
                result.append(made)
            }
        }
        return result
    }

    /// Replaces a transaction's tags with the ones named.
    @MainActor
    static func apply(_ names: [String], to transaction: Transaction, in context: ModelContext) {
        transaction.tags = resolve(names, in: context)
    }

    /// Moves every transaction from `source` to `target`, then removes `source`.
    @MainActor
    static func merge(_ source: Tag, into target: Tag, in context: ModelContext) {
        guard source !== target else { return }
        for transaction in Array(source.transactions) where transaction.isLive {
            if !transaction.tags.contains(where: { $0 === target }) { transaction.tags.append(target) }
            transaction.tags.removeAll { $0 === source }
        }
        context.delete(source)
        context.saveNow()
    }

    /// Takes the label off every transaction and removes it. The transactions stay.
    @MainActor
    static func delete(_ tag: Tag, in context: ModelContext) {
        for transaction in Array(tag.transactions) where transaction.isLive { transaction.tags.removeAll { $0 === tag } }
        context.delete(tag)
        context.saveNow()
    }

    /// Adds `tag` to every transaction given, or, when all of them already have it, takes it off all of them.
    @MainActor
    static func toggle(_ tag: Tag, on transactions: [Transaction], in context: ModelContext) {
        let live = transactions.filter(\.isLive)
        let allHave = !live.isEmpty && live.allSatisfy { $0.tags.contains { $0 === tag } }
        for transaction in live {
            if allHave {
                transaction.tags.removeAll { $0 === tag }
            } else if !transaction.tags.contains(where: { $0 === tag }) {
                transaction.tags.append(tag)
            }
        }
        context.saveNow()
    }
}

extension Transaction {
    /// This transaction's tags, by name.
    var sortedTags: [Tag] {
        guard isLive else { return [] }
        return tags.live.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var tagNames: [String] { sortedTags.map(\.name) }
}
