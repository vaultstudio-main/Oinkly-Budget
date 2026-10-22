import Foundation
import SwiftData

/// A label you can put on any number of transactions, such as "Vacation" or "Reimbursable", and filter reports by.
@Model
final class Tag {
    var name: String = ""
    var colorHex: String = "007AFF"
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Transaction.tags)
    var transactions: [Transaction] = []

    init(name: String, colorHex: String = "007AFF") {
        self.name = name
        self.colorHex = colorHex
    }
}
