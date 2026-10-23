import SwiftUI

/// How big the reports are drawn. Every chart and placeholder on the Reports page asks for its height through `h`, so the page can
/// shrink them all together until a tab fits above the status bar without scrolling. 1 is full size; the Reports page lowers it
/// on a short window and puts it back on a tall one.
@MainActor
enum ReportSize {
    static var scale: CGFloat = 1

    /// The smallest scale used: below this the charts would be too small to read, and the tab scrolls instead.
    static let smallest: CGFloat = 0.5

    static func h(_ height: CGFloat) -> CGFloat { max((height * scale).rounded(), 90) }
}
