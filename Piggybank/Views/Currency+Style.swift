import Foundation

extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    /// Currency style using the currency chosen in Settings (or the device's currency by default).
    static var appCurrency: Self {
        .currency(code: AppSettings.shared.effectiveCurrencyCode)
    }
}
