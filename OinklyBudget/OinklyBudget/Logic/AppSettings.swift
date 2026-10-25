import Foundation
import Observation
import SwiftUI
import AppKit

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

}

/// Which paper PDFs are made for.
enum PaperChoice: String, CaseIterable, Identifiable {
    case automatic, letter, a4

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic (\(PaperSize.regional.title))"
        case .letter: "US Letter"
        case .a4: "A4"
        }
    }
}

/// How exported PDFs look. Plain is black and grey and prints well on any printer.
enum ExportStyle: String, CaseIterable, Identifiable {
    case plain, color

    var id: Self { self }

    var title: String { self == .plain ? "Plain (black and grey)" : "With color accents" }
}

/// User preferences, saved on the device. Observable, so every screen that reads a value
/// (including a currency format) redraws as soon as it changes in Settings.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let currency = "currencyCode"
        static let appearance = "appearance"
        static let paper = "paperChoice"
        static let exportStyle = "exportStyle"
        static let letterheadMode = "letterheadMode"
        static let letterheadName = "letterheadName"
        static let letterheadDetails = "letterheadDetails"
    }

    /// ISO currency code the user picked. Empty means "use this device's currency".
    private(set) var currencyCode: String

    /// Light, dark, or follow the device.
    private(set) var appearance: Appearance

    /// The paper for PDFs: follow the region, or always Letter or A4.
    private(set) var paperChoice: PaperChoice

    /// The look of exported PDFs.
    private(set) var exportStyle: ExportStyle

    /// What goes at the top of a PDF's first page.
    private(set) var letterheadMode: LetterheadMode
    /// The name and the line of details beside your own logo.
    private(set) var letterheadName: String
    private(set) var letterheadDetails: String
    /// Changes whenever the logo file is replaced or removed, so a screen showing it redraws.
    private(set) var letterheadLogoVersion = 0

    private init() {
        letterheadMode = UserDefaults.standard.string(forKey: Key.letterheadMode).flatMap(LetterheadMode.init(rawValue:)) ?? .oinkly
        letterheadName = UserDefaults.standard.string(forKey: Key.letterheadName) ?? ""
        letterheadDetails = UserDefaults.standard.string(forKey: Key.letterheadDetails) ?? ""
        paperChoice = UserDefaults.standard.string(forKey: Key.paper).flatMap(PaperChoice.init(rawValue:)) ?? .automatic
        exportStyle = UserDefaults.standard.string(forKey: Key.exportStyle).flatMap(ExportStyle.init(rawValue:)) ?? .plain
        currencyCode = UserDefaults.standard.string(forKey: Key.currency) ?? ""
        appearance = UserDefaults.standard.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
    }

    func setPaperChoice(_ value: PaperChoice) {
        paperChoice = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.paper)
    }

    func setLetterheadMode(_ value: LetterheadMode) {
        letterheadMode = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.letterheadMode)
    }

    func setLetterheadName(_ value: String) {
        letterheadName = value
        UserDefaults.standard.set(value, forKey: Key.letterheadName)
    }

    func setLetterheadDetails(_ value: String) {
        letterheadDetails = value
        UserDefaults.standard.set(value, forKey: Key.letterheadDetails)
    }

    func logoChanged() { letterheadLogoVersion += 1 }

    func setExportStyle(_ value: ExportStyle) {
        exportStyle = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.exportStyle)
    }

    func setAppearance(_ value: Appearance) {
        appearance = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.appearance)
        applyToApp()
    }

    /// On the Mac the whole app's appearance is set directly. SwiftUI's own setting can't go back to "follow the system"
    /// once it has been forced to light or dark.
    func applyToApp() {
        let named: NSAppearance.Name? = switch appearance {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
        NSApplication.shared.appearance = named.flatMap { NSAppearance(named: $0) }
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
