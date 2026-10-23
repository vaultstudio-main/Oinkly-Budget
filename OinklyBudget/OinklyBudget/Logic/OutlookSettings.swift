import Foundation

/// The Monthly Outlook's own settings, kept in preferences and shared by the Outlook and War Plan tabs and the Settings window:
/// what a month starts with and the buffer to keep. They are read by the outlook and the War Plan and change nothing else.
enum OutlookSettings {
    static let bufferKey = "outlookBuffer"
    static let startAmountKey = "outlookStartAmount"
    static let startAccountKey = "outlookStartAccount"
    /// The window's id, for opening it from the page.
    static let windowID = "outlook-settings"

    /// The settings are stored as text, so an empty field is "not set" rather than zero.
    static func decimal(_ text: String) -> Decimal? {
        text.isEmpty ? nil : Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func text(_ value: Decimal?) -> String {
        guard let value, value != 0 else { return "" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    /// What the month starts with: the chosen account's balance now, otherwise the typed amount.
    static func opening(accounts: [Account], startAccount: String, startAmount: String, now: Date = .now) -> Decimal {
        if !startAccount.isEmpty, let account = accounts.first(where: { MonthOutlook.accountKey($0) == startAccount }) {
            return account.balance(asOf: now)
        }
        return decimal(startAmount) ?? 0
    }
}
