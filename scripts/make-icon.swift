#!/usr/bin/env swift
// Renders a 1024x1024 master AppIcon PNG, then shells out to `sips` and
// `iconutil` to produce Resources/AppIcon.icns. Run from the repo root:
//   swift scripts/make-icon.swift

import AppKit
import CoreGraphics
import Foundation

// MARK: - Tunables

let masterSize: CGFloat = 1024
// macOS app icons use a squircle slightly inset from the canvas edge.
// Apple's standard inset is ~100/1024 px and corner radius ~22.37% of the
// inscribed square. We keep the same proportions for native-feeling polish.
let iconInset: CGFloat = 100
let iconSide: CGFloat = masterSize - iconInset * 2
let cornerRadius: CGFloat = iconSide * 0.2237

// Pulse waveform (EKG-ish): list of normalised (x, y) points in [0,1].
// y=0.5 is centre line; spikes go up (negative dy) for the QRS complex.
let pulse: [(CGFloat, CGFloat)] = [
    (0.05, 0.55),
    (0.18, 0.55),
    (0.24, 0.50),
    (0.28, 0.62),
    (0.33, 0.18),
    (0.38, 0.78),
    (0.44, 0.55),
    (0.55, 0.55),
    (0.62, 0.55),
    (0.68, 0.42),
    (0.74, 0.65),
    (0.80, 0.55),
    (0.95, 0.55),
]

// MARK: - Drawing

func drawMaster() -> NSImage {
    let image = NSImage(size: NSSize(width: masterSize, height: masterSize))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // Transparent canvas (so the squircle has no background outside).
    ctx.clear(CGRect(x: 0, y: 0, width: masterSize, height: masterSize))

    let iconRect = CGRect(x: iconInset, y: iconInset, width: iconSide, height: iconSide)
    let squircle = CGPath(roundedRect: iconRect,
                          cornerWidth: cornerRadius,
                          cornerHeight: cornerRadius,
                          transform: nil)

    // Soft drop shadow under the icon body (subtle premium lift).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12),
                  blur: 36,
                  color: NSColor(white: 0, alpha: 0.45).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for everything that follows.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Vertical gradient: deep navy → near-black.
    let bgColors = [
        CGColor(red: 0.115, green: 0.145, blue: 0.205, alpha: 1.0), // top
        CGColor(red: 0.035, green: 0.050, blue: 0.085, alpha: 1.0)  // bottom
    ]
    let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: bgColors as CFArray,
                                locations: [0, 1])!
    ctx.drawLinearGradient(bgGradient,
                           start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
                           end:   CGPoint(x: iconRect.midX, y: iconRect.minY),
                           options: [])

    // Soft radial highlight at upper-left.
    let highlightColors = [
        CGColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 0.28),
        CGColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 0.0)
    ]
    let highlightGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: highlightColors as CFArray,
                                       locations: [0, 1])!
    let highlightCenter = CGPoint(x: iconRect.minX + iconRect.width * 0.32,
                                  y: iconRect.maxY - iconRect.height * 0.25)
    ctx.drawRadialGradient(highlightGradient,
                           startCenter: highlightCenter, startRadius: 0,
                           endCenter:   highlightCenter, endRadius: iconRect.width * 0.7,
                           options: [])

    // Faint horizontal grid lines (very subtle, like an oscilloscope).
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.045))
    ctx.setLineWidth(1.5)
    let gridLines = 5
    for i in 1..<gridLines {
        let y = iconRect.minY + (iconRect.height / CGFloat(gridLines)) * CGFloat(i)
        ctx.move(to: CGPoint(x: iconRect.minX, y: y))
        ctx.addLine(to: CGPoint(x: iconRect.maxX, y: y))
    }
    ctx.strokePath()

    // Build the pulse path in absolute coordinates.
    let pulsePath = CGMutablePath()
    for (i, p) in pulse.enumerated() {
        let pt = CGPoint(x: iconRect.minX + p.0 * iconRect.width,
                         y: iconRect.minY + (1 - p.1) * iconRect.height)
        if i == 0 { pulsePath.move(to: pt) } else { pulsePath.addLine(to: pt) }
    }

    // Glow under the pulse line.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 28,
                  color: CGColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 0.85))
    ctx.addPath(pulsePath)
    ctx.setLineWidth(36)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1))
    ctx.strokePath()
    ctx.restoreGState()

    // Crisp white pulse line on top of the glow.
    ctx.addPath(pulsePath)
    ctx.setLineWidth(22)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.strokePath()

    // Inner stroke to give the squircle a clean edge.
    ctx.addPath(squircle)
    ctx.setLineWidth(2)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.strokePath()

    ctx.restoreGState()
    return image
}

// MARK: - Pipeline

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try png.write(to: url)
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let resources = cwd.appendingPathComponent("Resources")
try? fm.createDirectory(at: resources, withIntermediateDirectories: true)

let masterPNG = resources.appendingPathComponent("AppIcon-1024.png")
try writePNG(drawMaster(), to: masterPNG)
print("✓ master  \(masterPNG.path)")

// Build .iconset and run iconutil.
let iconset = resources.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, size: Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024)
]

for v in variants {
    let out = iconset.appendingPathComponent(v.name)
    let task = Process()
    task.launchPath = "/usr/bin/sips"
    task.arguments = ["-z", "\(v.size)", "\(v.size)", masterPNG.path, "--out", out.path]
    task.standardOutput = Pipe()
    task.standardError = Pipe()
    try task.run()
    task.waitUntilExit()
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let icnsTask = Process()
icnsTask.launchPath = "/usr/bin/iconutil"
icnsTask.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try icnsTask.run()
icnsTask.waitUntilExit()
print("✓ icns    \(icns.path)")

try? fm.removeItem(at: iconset)
print("done.")
