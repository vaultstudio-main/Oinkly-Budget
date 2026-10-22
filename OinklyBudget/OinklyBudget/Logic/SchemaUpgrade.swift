import Foundation
import SwiftData

/// Tidy-up that runs once after the database has moved from the 1.0 shape to the current one. The move itself is
/// automatic (every new field has a default); this fills the new fields from where the same facts were kept before. It
/// is safe to run on every launch: each step only acts when there is something left to move.
@MainActor
enum SchemaUpgrade {
    static func run(in context: ModelContext) {
        // Wire and digital routing numbers used to be packed into the one routing field with a "|" between them.
        for account in ((try? context.fetch(FetchDescriptor<Account>())) ?? []) where account.isLive && account.routingNumber.contains("|") {
            let parts = account.routingNumber.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            account.achRouting = parts.indices.contains(0) ? parts[0] : ""
            if parts.indices.contains(1) { account.wireRouting = parts[1] }
            if parts.indices.contains(2) { account.digitalRouting = parts[2] }
        }

        // Primary checking used to be a setting on this Mac.
        PrimaryChecking.adoptLegacySetting(in: context)

        // The opening deposit used to be found by its payee, category and method. Now it carries a flag.
        let name = Transaction.depositName
        let deposits = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.payee == name && !$0.isOpeningDeposit }))) ?? []
        for deposit in deposits where deposit.hasOpeningDepositShape { deposit.isOpeningDeposit = true }

        // Reminders and saved import layouts used to be kept in this login's preferences.
        if !ScreenshotMode.isOn { SettingsRecords.adoptLegacy(in: context) }

        ArtworkChoices.removeOrphans(in: context)

        seedTaxFlags(in: context)
        context.saveNow()
    }

    /// The categories people usually need at tax time. Flagged once; after that the flags are yours to change.
    private static let taxKeys: Set<String> = ["charity", "healthcare", "dental", "taxes-income", "taxes-other", "property-tax", "education",
                                               "student-loans", "mental-health", "pharmacy", "health-insurance", "childcare", "business-expenses"]
    private static let taxSeededKey = "taxFlagsSeeded"

    static func seedTaxFlags(in context: ModelContext, force: Bool = false) {
        guard force || !UserDefaults.standard.bool(forKey: taxSeededKey) else { return }
        for category in ((try? context.fetch(FetchDescriptor<Category>())) ?? []) where category.isLive {
            if let key = category.systemKey, taxKeys.contains(key) { category.isTaxRelated = true }
        }
        UserDefaults.standard.set(true, forKey: taxSeededKey)
    }
}
