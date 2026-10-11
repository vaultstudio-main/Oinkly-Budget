import Foundation
import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// How the app looks: follow the device, or always light or dark.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Nil lets the device decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// User preferences, saved on the device. Observable, so every screen that reads a value
/// (including a currency format) redraws as soon as it changes in Settings.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let currency = "currencyCode"
        static let appearance = "appearance"
    }

    /// ISO currency code the user picked. Empty means "use this device's currency".
    private(set) var currencyCode: String

    /// Light, dark, or follow the device.
    private(set) var appearance: Appearance

    private init() {
        currencyCode = UserDefaults.standard.string(forKey: Key.currency) ?? ""
        appearance = UserDefaults.standard.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
    }

    func setAppearance(_ value: Appearance) {
        appearance = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.appearance)
        applyToApp()
    }

    /// On the Mac the whole app's appearance is set directly. SwiftUI's own setting can't go back to "follow the system"
    /// once it has been forced to light or dark. On iPhone and iPad every screen uses `preferredColorScheme` instead.
    func applyToApp() {
        #if os(macOS)
        let named: NSAppearance.Name? = switch appearance {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
        NSApplication.shared.appearance = named.flatMap { NSAppearance(named: $0) }
        #endif
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
