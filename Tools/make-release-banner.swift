#!/usr/bin/env swift
// Makes a release's banner: the social preview with the version and the build name across the top left.
//
//     swift Tools/make-release-banner.swift Documents/social-preview.png Documents/social-preview-1.1.png 1.1 "Laser Focused, You Idiot"
//
// The banner goes at the top of the GitHub release notes (see the release checklist) and in the app's Release Notes window.
import AppKit

let args = CommandLine.arguments
guard args.count == 5, let source = NSImage(contentsOfFile: args[1]) else {
    print("usage: make-release-banner.swift <social-preview.png> <output.png> <version> <name>")
    exit(1)
}
let version = args[3], name = args[4]
let width = 1280, height = 640

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
source.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)

// The navy of the "Oinkly Budget" title.
let navy = NSColor(srgbRed: 0.05, green: 0.16, blue: 0.36, alpha: 1)
let left: CGFloat = 75
let pillHeight: CGFloat = 58
let pillBottom = CGFloat(height) - 52 - pillHeight

let pillText = NSAttributedString(string: "Version \(version)", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white])
let pillRect = NSRect(x: left, y: pillBottom, width: pillText.size().width + 46, height: pillHeight)
navy.setFill()
NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2).fill()
pillText.draw(at: NSPoint(x: pillRect.minX + 23, y: pillRect.midY - pillText.size().height / 2))

// The build name, as wide as the room beside the pig allows.
var fontSize: CGFloat = 40
var nameText: NSAttributedString
let room = 780 - pillRect.maxX - 24
repeat {
    var font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    if let rounded = font.fontDescriptor.withDesign(.rounded), let found = NSFont(descriptor: rounded, size: fontSize) { font = found }
    nameText = NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: navy])
    fontSize -= 2
} while nameText.size().width > room && fontSize > 16
nameText.draw(at: NSPoint(x: pillRect.maxX + 24, y: pillRect.midY - nameText.size().height / 2))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2])")
