// SPDX-License-Identifier: GPL-3.0-or-later
// Monterey port: generates this fork's OWN icon set (it deliberately shares
// nothing with the upstream app's artwork or trademarks, see TRADEMARKS.md).
//
// usage: swift Tools/MakeMontereyIcon.swift <out-dir>
// writes <out-dir>/AppIcon.iconset/*.png, <out-dir>/AppIcon.icns (via iconutil),
// <out-dir>/MenuBarIcon.png, MenuBarIcon@2x.png and BrandMark.png.

import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let iconset = "\(out)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func canvas(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

/// A teal-to-indigo squircle with a white "M" and a small arrow: a port mark.
func appIcon(px: Int) -> Data {
    let rep = canvas(px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    path.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.05, green: 0.62, blue: 0.62, alpha: 1),
                        NSColor(calibratedRed: 0.27, green: 0.20, blue: 0.64, alpha: 1)])!
        .draw(in: rect, angle: -60)
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let font = NSFont.systemFont(ofSize: s * 0.56, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: style]
    let text = NSAttributedString(string: "M", attributes: attrs)
    let size = text.size()
    text.draw(in: NSRect(x: 0, y: (s - size.height) / 2 - s * 0.02, width: s, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return png(rep)
}

/// A template (black, transparent) mark for the menu bar: 26x20 points, the
/// canvas the app draws every menu bar glyph in (checked by `--selftest`).
func menuBarIcon(scale: Int) -> Data {
    let w = 26 * scale, h = 20 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 26, height: 20)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // The context draws in points (rep.size), so lay out in 26x20 for both scales.
    let sw: CGFloat = 26, sh: CGFloat = 20
    let box = NSBezierPath(roundedRect: NSRect(x: sw * 0.2, y: sh * 0.15, width: sw * 0.6, height: sh * 0.7),
                           xRadius: sh * 0.2, yRadius: sh * 0.2)
    box.lineWidth = max(1, sh * 0.08)
    NSColor.black.setStroke(); box.stroke()
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let font = NSFont.systemFont(ofSize: sh * 0.55, weight: .heavy)
    let text = NSAttributedString(string: "M", attributes: [.font: font, .foregroundColor: NSColor.black,
                                                              .paragraphStyle: style])
    let size = text.size()
    text.draw(in: NSRect(x: 0, y: (sh - size.height) / 2 - sh * 0.01, width: sw, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return png(rep)
}

/// A monochrome (black on transparent) mark: the app tints it like a template image.
func brandMark(px: Int) -> Data {
    let rep = canvas(px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let box = NSBezierPath(roundedRect: NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8),
                           xRadius: s * 0.2, yRadius: s * 0.2)
    box.lineWidth = s * 0.07
    NSColor.black.setStroke(); box.stroke()
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let font = NSFont.systemFont(ofSize: s * 0.52, weight: .heavy)
    let text = NSAttributedString(string: "M", attributes: [.font: font, .foregroundColor: NSColor.black,
                                                              .paragraphStyle: style])
    let size = text.size()
    text.draw(in: NSRect(x: 0, y: (s - size.height) / 2 - s * 0.01, width: s, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return png(rep)
}

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in sizes {
    try appIcon(px: entry.px).write(to: URL(fileURLWithPath: "\(iconset)/\(entry.name).png"))
}
try menuBarIcon(scale: 1).write(to: URL(fileURLWithPath: "\(out)/MenuBarIcon.png"))
try menuBarIcon(scale: 2).write(to: URL(fileURLWithPath: "\(out)/MenuBarIcon@2x.png"))
try brandMark(px: 256).write(to: URL(fileURLWithPath: "\(out)/BrandMark.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "\(out)/AppIcon.icns"]
try task.run(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "icon set written to \(out)" : "iconutil failed")
