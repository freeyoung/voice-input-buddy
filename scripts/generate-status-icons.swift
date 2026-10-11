import AppKit
import Foundation

// Original template artwork, GPL-3.0-only. One logical 18-point canvas at both scales.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for active in [false, true] {
    for scale in [1, 2] {
        let pixels = 18 * scale
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSColor.black.setFill()
        NSColor.black.setStroke()
        let capsule = NSBezierPath(roundedRect: NSRect(x: 6, y: 7.5, width: 5, height: 9), xRadius: 2.5, yRadius: 2.5)
        capsule.lineWidth = 1.5
        if active { capsule.fill() } else { capsule.stroke() }
        let cradle = NSBezierPath()
        cradle.move(to: NSPoint(x: 3.5, y: 10))
        cradle.line(to: NSPoint(x: 3.5, y: 8))
        cradle.curve(to: NSPoint(x: 13.5, y: 8), controlPoint1: NSPoint(x: 3.5, y: 2), controlPoint2: NSPoint(x: 13.5, y: 2))
        cradle.line(to: NSPoint(x: 13.5, y: 10))
        cradle.move(to: NSPoint(x: 8.5, y: 3.5))
        cradle.line(to: NSPoint(x: 8.5, y: 1.5))
        cradle.move(to: NSPoint(x: 6, y: 1.5))
        cradle.line(to: NSPoint(x: 11, y: 1.5))
        cradle.lineWidth = 1.5
        cradle.lineCapStyle = .round
        cradle.stroke()
        let button = NSBezierPath(roundedRect: NSRect(x: 14, y: 12, width: 3, height: 4.5), xRadius: 1, yRadius: 1)
        button.lineWidth = 1.25
        if active { button.fill() } else { button.stroke() }
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = NSSize(width: 18, height: 18)
        let name = active ? "StatusIconActiveTemplate" : "StatusIconTemplate"
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: destination.appendingPathComponent("\(name)\(suffix).png")
        )
    }
}
