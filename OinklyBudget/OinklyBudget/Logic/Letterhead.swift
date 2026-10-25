import AppKit

/// What goes at the top of the first page of a printed or exported PDF.
enum LetterheadMode: String, CaseIterable, Identifiable {
    /// The Oinkly Budget pig and name.
    case oinkly
    /// A logo, name and details you give, such as a small business's.
    case custom
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .oinkly: "Oinkly Budget"
        case .custom: "My own logo and name"
        case .off: "None"
        }
    }
}

/// The letterhead for a PDF: a picture, a name and a line of details, chosen in Settings and worked out once when the PDF is made.
enum Letterhead {
    /// The biggest logo a letterhead keeps, in pixels: a standard letterhead logo, about 2 inches wide and 0.65 inch tall at 300 dpi. A bigger
    /// picture is reduced to fit, keeping its shape. It is drawn on the page no larger than that.
    static let logoBox = CGSize(width: 600, height: 200)
    /// How long the name and the line of details can be, so each stays on one line of the letterhead.
    static let maxNameLength = 40
    static let maxDetailsLength = 90
    /// A picture file bigger than this is turned away, so a huge one is never opened.
    static let maxFileBytes = 25_000_000

    struct Resolved {
        var image: NSImage?
        var name: String
        var details: String
    }

    /// The letterhead to draw now, or nil when there is none.
    @MainActor
    static func current() -> Resolved? {
        let settings = AppSettings.shared
        switch settings.letterheadMode {
        case .off:
            return nil
        case .oinkly:
            return Resolved(image: NSApp?.applicationIconImage, name: "Oinkly Budget", details: "")
        case .custom:
            let resolved = Resolved(image: customLogo(), name: settings.letterheadName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    details: settings.letterheadDetails.trimmingCharacters(in: .whitespacesAndNewlines))
            return resolved.image == nil && resolved.name.isEmpty && resolved.details.isEmpty ? nil : resolved
        }
    }

    // MARK: The logo you choose

    /// Kept in a small file on this Mac, not in the database: it is a setting, like the paper size, and is not part of backups.
    private static var logoURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Letterhead", isDirectory: true).appendingPathComponent("logo.png")
    }

    static func customLogo() -> NSImage? { NSImage(contentsOf: logoURL) }

    /// Saves a picture as the logo, reduced to fit the standard logo size (never enlarged) so it stays small. False when the file isn't a
    /// picture or is too big to open.
    @discardableResult
    static func saveLogo(from data: Data, box: CGSize = logoBox) -> Bool {
        guard data.count <= maxFileBytes, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return false }
        let scale = min(box.width / image.size.width, box.height / image.size.height, 1)
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        try? FileManager.default.createDirectory(at: logoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? png.write(to: logoURL, options: .atomic)) != nil
    }

    static func removeLogo() { try? FileManager.default.removeItem(at: logoURL) }
}
