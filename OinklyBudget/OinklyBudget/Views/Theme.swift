import SwiftUI

extension Color {
    /// A color that switches with the interface style.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

enum Theme {
    static let background = Color(light: Color(white: 0.95), dark: Color(white: 0.09))
    static let panel = Color(light: .white, dark: Color(white: 0.14))
    /// The side panel: a step darker than the page in light mode, so you can see where one ends and the other starts.
    static let sidebar = Color(light: Color(white: 0.88), dark: Color(white: 0.12))
    /// A line between two areas that has to be seen. The system's own divider nearly vanishes in light mode.
    static let separator = Color(light: Color(white: 0, opacity: 0.30), dark: Color(white: 1, opacity: 0.20))
    static let green = Color(light: Color(red: 0.12, green: 0.60, blue: 0.22), dark: Color(red: 0.62, green: 0.89, blue: 0.40))
    static let red = Color(light: Color(red: 0.80, green: 0.17, blue: 0.22), dark: Color(red: 0.94, green: 0.47, blue: 0.49))
}

extension View {
    /// Applies the Light / Dark / System choice from Settings. Reads the setting, so changing it updates every window at once.
    func appAppearance() -> some View {
        onAppear { AppSettings.shared.applyToApp() }
    }
}

/// A line between two areas of the window, dark enough to see in light mode.
struct EdgeLine: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The card look: the panel color in a rounded shape with a thin edge, so a card stands out from the page behind it.
    func panelBackground(cornerRadius: CGFloat, continuous: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: continuous ? .continuous : .circular)
        return background(Theme.panel, in: shape)
            .overlay(shape.strokeBorder(Theme.separator.opacity(0.45), lineWidth: 1))
    }
}
