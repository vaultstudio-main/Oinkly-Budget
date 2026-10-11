import SwiftUI

extension Color {
    /// A color that switches with the interface style.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #endif
    }
}

enum Theme {
    static let background = Color(light: Color(white: 0.95), dark: Color(white: 0.09))
    static let panel = Color(light: .white, dark: Color(white: 0.14))
    static let green = Color(light: Color(red: 0.12, green: 0.60, blue: 0.22), dark: Color(red: 0.62, green: 0.89, blue: 0.40))
    static let red = Color(light: Color(red: 0.80, green: 0.17, blue: 0.22), dark: Color(red: 0.94, green: 0.47, blue: 0.49))
}

extension View {
    /// Applies the Light / Dark / System choice from Settings. Reads the setting, so changing it updates every window at once.
    func appAppearance() -> some View {
        #if os(macOS)
        onAppear { AppSettings.shared.applyToApp() }
        #else
        preferredColorScheme(AppSettings.shared.appearance.colorScheme)
        #endif
    }
}
