import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Photos attached to accounts (the car, the house). Stored small so the database stays light.
enum AccountPhoto {
    static let maxPixelSize = 1200

    /// Shrinks any image the user picked to a JPEG no larger than `maxPixelSize` on its long side.
    static func compress(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respects the photo's rotation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    static func image(from data: Data?) -> Image? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}

extension Account {
    /// Loans and owned assets can have a picture of the thing: the car, the house.
    var supportsPhoto: Bool { type.group == .loans || type.group == .assets }

    /// Anything with a VIN.
    var supportsVIN: Bool { Self.typeHasVIN(type) }
    static func typeHasVIN(_ type: AccountType) -> Bool { [.autoLoan, .vehicleLoan, .vehicle].contains(type) }

    static let vinLength = 17

    /// A VIN is 17 letters and digits, never I, O or Q, always uppercase.
    static func cleanVIN(_ text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) && !"IOQ".contains($0) }.prefix(vinLength))
    }
}
