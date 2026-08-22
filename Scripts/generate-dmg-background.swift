#!/usr/bin/env swift
// Draws the DMG window background.
//
//   swift Scripts/generate-dmg-background.swift dist/dmg-background.png
//
// Writes both a PNG and a TIFF next to each other whatever extension you pass.
// The TIFF is the one that ships; the PNG exists so the result can be looked at
// without mounting anything.
//
// The load-bearing detail is `rep.size = logicalSize` at the end. The bitmap is
// built at 2x pixels and then tagged with the logical size, which makes both
// encoders write 144 DPI metadata. Finder reads that and draws the image at
// 660x400 points. Without the tag it draws it at 1320x800 and the bottom right of
// the window is clipped, which is a confusing failure because the image file
// itself looks perfect.
import AppKit
import Foundation

let logicalSize = CGSize(width: 660, height: 400)
let scale: CGFloat = 2.0
let pixelSize = CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale)

let outputPath = CommandLine.arguments.dropFirst().first ?? "dist/dmg-background.png"

// Obsidian and bone, the same pair the app icon and the docs backdrops use. The
// ground is not pure black: the app icon sits on it, and a black icon on a black
// field loses its edge.
let ground = NSColor(srgbRed: 0.043, green: 0.043, blue: 0.047, alpha: 1)
let lift = NSColor(srgbRed: 0.094, green: 0.094, blue: 0.106, alpha: 1)
let bone = NSColor(srgbRed: 0.937, green: 0.929, blue: 0.914, alpha: 1)
let quiet = NSColor(srgbRed: 0.529, green: 0.525, blue: 0.545, alpha: 1)
let hairline = NSColor(white: 1.0, alpha: 0.10)

/// Flips a logical y measured from the top into the bitmap's bottom-left space,
/// and scales into pixels. Every coordinate below is written top-down because
/// that is how the Finder window reads.
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x * scale, y: (logicalSize.height - y) * scale)
}

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size * scale, weight: weight)
}

func draw(_ text: String, centeredAt x: CGFloat, baseline y: CGFloat,
          font f: NSFont, color: NSColor, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: f, .foregroundColor: color, .kern: tracking * scale,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let width = string.size().width
    string.draw(at: CGPoint(x: x * scale - width / 2, y: point(0, y).y))
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("cannot allocate bitmap\n".utf8))
    exit(1)
}
rep.size = pixelSize

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let full = NSRect(origin: .zero, size: pixelSize)
ground.setFill()
full.fill()

// One quiet lift centred behind where the two icons sit, so the ground reads as a
// surface rather than as a flat slab. Kept very low contrast: the icons are the
// subject and a visible gradient competes with them.
NSGradient(colors: [lift, ground])?.draw(
    in: full, relativeCenterPosition: NSPoint(x: 0, y: 0.1)
)

let centre = logicalSize.width / 2

draw("Marker", centeredAt: centre, baseline: 62, font: font(30, .semibold),
     color: bone, tracking: -0.6)

// Read from the built app rather than hardcoded, so a release cannot ship a
// background naming the previous version. Wave's generator hardcodes it and has
// to be hand edited every time.
let version = ProcessInfo.processInfo.environment["MARKER_VERSION"] ?? "1.0.0"
draw("Version \(version)", centeredAt: centre, baseline: 86,
     font: font(12, .regular), color: quiet)

hairline.setStroke()
let rule = NSBezierPath()
rule.move(to: point(centre - 26, 104))
rule.line(to: point(centre + 26, 104))
rule.lineWidth = 1
rule.stroke()

// The instruction sits under the icons, not between them, because the arrow
// between them is doing that job already.
draw("Drag Marker into your Applications folder", centeredAt: centre, baseline: 330,
     font: font(12, .medium), color: quiet, tracking: 0.2)

// The arrow runs between the two icon slots, at their vertical centre. Icon
// positions are set in Scripts/build-dmg.sh and these numbers have to agree with
// them, so both live in comments in both files.
let arrowY: CGFloat = 205
let arrowFrom: CGFloat = 258
let arrowTo: CGFloat = 402
quiet.withAlphaComponent(0.55).setStroke()
let shaft = NSBezierPath()
shaft.move(to: point(arrowFrom, arrowY))
shaft.line(to: point(arrowTo - 6, arrowY))
shaft.lineWidth = 1.5 * scale
shaft.lineCapStyle = .round
shaft.stroke()

let head = NSBezierPath()
head.move(to: point(arrowTo - 9, arrowY - 5))
head.line(to: point(arrowTo, arrowY))
head.line(to: point(arrowTo - 9, arrowY + 5))
head.lineWidth = 1.5 * scale
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

NSGraphicsContext.restoreGraphicsState()

// Tag as 2x. Everything above drew in pixels; this is what makes Finder treat the
// result as a 660x400 point image.
rep.size = logicalSize

let base = URL(fileURLWithPath: outputPath).deletingPathExtension()
let pngURL = base.appendingPathExtension("png")
let tiffURL = base.appendingPathExtension("tiff")
try? FileManager.default.createDirectory(
    at: base.deletingLastPathComponent(), withIntermediateDirectories: true
)

func writeOrDie(_ data: Data?, to url: URL, label: String) {
    guard let data else {
        FileHandle.standardError.write(Data("cannot encode \(label)\n".utf8))
        exit(1)
    }
    do { try data.write(to: url) } catch {
        FileHandle.standardError.write(Data("cannot write \(url.path): \(error)\n".utf8))
        exit(1)
    }
}

writeOrDie(rep.representation(using: .png, properties: [:]), to: pngURL, label: "PNG")
writeOrDie(rep.tiffRepresentation, to: tiffURL, label: "TIFF")
print("wrote \(pngURL.path) and \(tiffURL.path) (\(Int(pixelSize.width))x\(Int(pixelSize.height)) at 144 DPI)")
