import Foundation
import SwiftData

/// Matching and memorizing payees.
enum PayeeMemory {
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Payees whose names start with, then contain, `text`. Empty text matches nothing.
    static func matches(for text: String, in payees: [Payee], limit: Int = 5) -> [Payee] {
        let query = normalized(text)
        guard !query.isEmpty else { return [] }
        let prefix = payees.filter { normalized($0.name).hasPrefix(query) }
        let contains = payees.filter { !normalized($0.name).hasPrefix(query) && normalized($0.name).contains(query) }
        return Array((prefix + contains).prefix(limit))
    }

    static func exactMatch(for text: String, in payees: [Payee]) -> Payee? {
        let query = normalized(text)
        guard !query.isEmpty else { return nil }
        return payees.first { normalized($0.name) == query }
    }

    /// Creates or updates the memorized payee for a just-entered transaction.
    static func record(name: String, category: Category?, amount: Decimal, in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let payees = (try? context.fetch(FetchDescriptor<Payee>())) ?? []
        if let existing = exactMatch(for: trimmed, in: payees) {
            existing.lastCategory = category
            existing.lastAmount = amount
        } else {
            context.insert(Payee(name: trimmed, lastCategory: category, lastAmount: amount))
        }
    }
}
