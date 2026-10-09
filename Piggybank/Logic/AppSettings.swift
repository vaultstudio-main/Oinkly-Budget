import Foundation
import Observation

/// User preferences, saved on the device. Observable, so every screen that reads a value
/// (including a currency format) redraws as soon as it changes in Settings.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let currency = "currencyCode"
    }

    /// ISO currency code the user picked. Empty means "use this device's currency".
    private(set) var currencyCode: String

    private init() {
        currencyCode = UserDefaults.standard.string(forKey: Key.currency) ?? ""
    }

    static var deviceCurrencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    /// The code amounts are actually shown in.
    var effectiveCurrencyCode: String { currencyCode.isEmpty ? Self.deviceCurrencyCode : currencyCode }

    func setCurrencyCode(_ code: String) {
        currencyCode = code
        UserDefaults.standard.set(code, forKey: Key.currency)
    }

    // MARK: Currency choices

    static let commonCurrencyCodes = ["USD", "EUR", "GBP", "CAD", "AUD", "NZD", "JPY", "CHF", "CNY", "HKD", "SGD", "INR", "MXN", "BRL", "KRW", "SEK", "NOK", "DKK", "ZAR", "AED"]

    static func currencyName(_ code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(name) (\(code))"
    }

    /// Every ISO currency, by name.
    static var allCurrencyCodes: [String] {
        Locale.commonISOCurrencyCodes.sorted { currencyName($0) < currencyName($1) }
    }
}
