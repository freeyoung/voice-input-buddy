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
        let capsule = NSBezierPath(roundedRect: NSRect(x: 5, y: 5.5, width: 8, height: 11.5), xRadius: 4, yRadius: 4)
        capsule.fill()
        // Cut the face out of the opaque template so it survives either system tint.
        context.cgContext.setBlendMode(.destinationOut)
        for x in [CGFloat(6.9), CGFloat(10.1)] {
            NSBezierPath(ovalIn: NSRect(x: x, y: 11, width: 1.2, height: 1.5)).fill()
        }
        let smile = NSBezierPath(); smile.move(to: NSPoint(x: 7, y: 9.5))
        smile.curve(to: NSPoint(x: 11, y: 9.5), controlPoint1: NSPoint(x: 8, y: 7.5), controlPoint2: NSPoint(x: 10, y: 7.5))
        smile.lineWidth = 1; smile.lineCapStyle = .round; smile.stroke()
        context.cgContext.setBlendMode(.normal)
        let cradle = NSBezierPath(); cradle.move(to: NSPoint(x: 2.6, y: 9))
        cradle.curve(to: NSPoint(x: 15.4, y: 9), controlPoint1: NSPoint(x: 2.6, y: 0.6), controlPoint2: NSPoint(x: 15.4, y: 0.6))
        cradle.move(to: NSPoint(x: 9, y: 2.7)); cradle.line(to: NSPoint(x: 9, y: 1))
        cradle.move(to: NSPoint(x: 5.7, y: 1)); cradle.line(to: NSPoint(x: 12.3, y: 1))
        cradle.lineWidth = active ? 1.8 : 1.4; cradle.lineCapStyle = .round; cradle.stroke()
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = NSSize(width: 18, height: 18)
        let name = active ? "StatusIconActiveTemplate" : "StatusIconTemplate"
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: destination.appendingPathComponent("\(name)\(suffix).png")
        )
    }
}
