import AppKit
import CoreGraphics
import Foundation

func makeSquirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func renderIcon(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    let canvas = CGFloat(pixelSize)
    rep.size = NSSize(width: canvas, height: canvas)

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let s = canvas / 1024.0
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // 1. Apple macOS squircle geometry (824x824 inside 1024x1024)
    let iconRect = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let cornerRadius = 186 * s
    let squirclePath = makeSquirclePath(in: iconRect, radius: cornerRadius)

    // Soft ambient drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -20 * s),
        blur: 38 * s,
        color: CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.48)
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // 2. Matte anodized obsidian-titanium surface gradient
    let bgColors = [
        CGColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1.0),
        CGColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1.0),
        CGColor(srgbRed: 0.05, green: 0.055, blue: 0.07, alpha: 1.0),
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.52, 1.0]) {
        ctx.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: 360 * s, y: 924 * s),
            end: CGPoint(x: 660 * s, y: 100 * s),
            options: []
        )
    }

    // Very subtle top-center studio light wash
    let washColors = [
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.055),
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
    ] as CFArray
    if let washGrad = CGGradient(colorsSpace: colorSpace, colors: washColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            washGrad,
            startCenter: CGPoint(x: 512 * s, y: 910 * s),
            startRadius: 0,
            endCenter: CGPoint(x: 512 * s, y: 910 * s),
            endRadius: 560 * s,
            options: []
        )
    }

    // 3. Minimalist sculptural centerpiece:
    //    Left: Precision metallic chevron `>`
    //    Right: Three clean horizontal activity capsules + coral unread beacon dot
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12 * s),
        blur: 28 * s,
        color: CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.55)
    )

    // Metallic Chevron `>`
    let chevPath = CGMutablePath()
    chevPath.move(to: CGPoint(x: 278 * s, y: 632 * s))
    chevPath.addLine(to: CGPoint(x: 416 * s, y: 512 * s))
    chevPath.addLine(to: CGPoint(x: 278 * s, y: 392 * s))

    ctx.saveGState()
    ctx.addPath(chevPath)
    ctx.setLineWidth(64 * s)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()

    let chevColors = [
        CGColor(srgbRed: 0.99, green: 0.995, blue: 1.0, alpha: 1.0),
        CGColor(srgbRed: 0.78, green: 0.82, blue: 0.89, alpha: 1.0),
    ] as CFArray
    if let chevGrad = CGGradient(colorsSpace: colorSpace, colors: chevColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            chevGrad,
            start: CGPoint(x: 278 * s, y: 660 * s),
            end: CGPoint(x: 416 * s, y: 360 * s),
            options: []
        )
    }
    ctx.restoreGState()

    // Helper for drawing a sleek horizontal capsule with linear gradient
    func drawPill(rect: CGRect, c1: CGColor, c2: CGColor) {
        let pillPath = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        ctx.saveGState()
        ctx.addPath(pillPath)
        ctx.clip()
        let colors = [c1, c2] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.midY),
                end: CGPoint(x: rect.maxX, y: rect.midY),
                options: []
            )
        }
        ctx.restoreGState()
    }

    let pillHeight: CGFloat = 54 * s
    let pillX: CGFloat = 496 * s

    // Top capsule (Active Codex Emerald)
    drawPill(
        rect: CGRect(x: pillX, y: 605 * s - pillHeight / 2, width: 252 * s, height: pillHeight),
        c1: CGColor(srgbRed: 0.20, green: 0.91, blue: 0.66, alpha: 1.0),
        c2: CGColor(srgbRed: 0.11, green: 0.76, blue: 0.54, alpha: 1.0)
    )

    // Middle capsule (Active Copilot Cobalt Blue)
    drawPill(
        rect: CGRect(x: pillX, y: 512 * s - pillHeight / 2, width: 184 * s, height: pillHeight),
        c1: CGColor(srgbRed: 0.36, green: 0.68, blue: 1.00, alpha: 1.0),
        c2: CGColor(srgbRed: 0.20, green: 0.50, blue: 0.96, alpha: 1.0)
    )

    // Bottom capsule (Muted Slate / Idle)
    drawPill(
        rect: CGRect(x: pillX, y: 419 * s - pillHeight / 2, width: 122 * s, height: pillHeight),
        c1: CGColor(srgbRed: 0.32, green: 0.35, blue: 0.42, alpha: 0.95),
        c2: CGColor(srgbRed: 0.23, green: 0.26, blue: 0.32, alpha: 0.95)
    )

    ctx.restoreGState()

    // 4. Signature Coral-Rose Completion Dot floating beside the middle/bottom track
    let dotCenter = CGPoint(x: 720 * s, y: 512 * s)
    let dotRadius: CGFloat = 27 * s

    // Subtle coral halo
    let haloColors = [
        CGColor(srgbRed: 1.0, green: 0.22, blue: 0.44, alpha: 0.42),
        CGColor(srgbRed: 1.0, green: 0.22, blue: 0.44, alpha: 0.0),
    ] as CFArray
    if let haloGrad = CGGradient(colorsSpace: colorSpace, colors: haloColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            haloGrad,
            startCenter: dotCenter,
            startRadius: 0,
            endCenter: dotCenter,
            endRadius: 68 * s,
            options: []
        )
    }

    let dotRect = CGRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    )
    ctx.saveGState()
    ctx.addEllipse(in: dotRect)
    ctx.clip()
    let dotColors = [
        CGColor(srgbRed: 1.0, green: 0.42, blue: 0.58, alpha: 1.0),
        CGColor(srgbRed: 1.0, green: 0.19, blue: 0.42, alpha: 1.0),
    ] as CFArray
    if let dotGrad = CGGradient(colorsSpace: colorSpace, colors: dotColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            dotGrad,
            start: CGPoint(x: dotCenter.x, y: dotCenter.y + dotRadius),
            end: CGPoint(x: dotCenter.x, y: dotCenter.y - dotRadius),
            options: []
        )
    }
    ctx.restoreGState()

    // 5. Crisp 1px-equivalent inner specular border
    ctx.addPath(squirclePath)
    ctx.setLineWidth(2.5 * s)
    ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.10))
    ctx.strokePath()

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let projectDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconsetDir = projectDir.appendingPathComponent("Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for spec in specs {
    guard let png = renderIcon(pixelSize: spec.pixels) else {
        fatalError("Failed to render \(spec.name)")
    }
    try png.write(to: iconsetDir.appendingPathComponent(spec.name))
}

let icnsURL = projectDir.appendingPathComponent("Resources/AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(proc.terminationStatus)")
}

try? FileManager.default.removeItem(atPath: "/tmp/agentmeter_icon_preview.png")
try? FileManager.default.copyItem(
    at: iconsetDir.appendingPathComponent("icon_512x512@2x.png"),
    to: URL(fileURLWithPath: "/tmp/agentmeter_icon_preview.png")
)
try? FileManager.default.removeItem(at: iconsetDir)
print("Generated \(icnsURL.path)")
