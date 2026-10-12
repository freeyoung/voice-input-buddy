import AppKit
import Foundation
// Vector redraw of the supplied remote-and-buddy design, GPL-3.0-only.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 212, yRadius: 212)
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.29, green: 0.77, blue: 1, alpha: 1),
                          ending: NSColor(calibratedRed: 0.01, green: 0.27, blue: 0.98, alpha: 1))!
gradient.draw(in: background, angle: -80)
NSColor.white.setStroke(); NSColor.white.setFill()
func stroke(_ points: [NSPoint], width: CGFloat) {
    let path = NSBezierPath(); path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
}
let remote = NSBezierPath(roundedRect: NSRect(x: 194, y: 248, width: 168, height: 366), xRadius: 68, yRadius: 68)
remote.lineWidth = 32; remote.stroke()
NSBezierPath(ovalIn: NSRect(x: 253, y: 333, width: 50, height: 50)).fill()
for (height, halfWidth) in [(CGFloat(684), CGFloat(52)), (CGFloat(736), CGFloat(90))] {
    let arc = NSBezierPath(); arc.move(to: NSPoint(x: 278 - halfWidth, y: height))
    arc.curve(to: NSPoint(x: 278 + halfWidth, y: height), controlPoint1: NSPoint(x: 278 - halfWidth * 0.5, y: height + 46), controlPoint2: NSPoint(x: 278 + halfWidth * 0.5, y: height + 46))
    arc.lineWidth = 30; arc.lineCapStyle = .round; arc.stroke()
}
NSBezierPath(ovalIn: NSRect(x: 260, y: 640, width: 36, height: 30)).fill()
for x in [CGFloat(415), CGFloat(465)] { NSBezierPath(ovalIn: NSRect(x: x, y: 423, width: 30, height: 30)).fill() }
NSBezierPath(roundedRect: NSRect(x: 570, y: 344, width: 202, height: 394), xRadius: 101, yRadius: 101).fill()
let cradle = NSBezierPath(); cradle.move(to: NSPoint(x: 522, y: 521)); cradle.line(to: NSPoint(x: 522, y: 481))
cradle.curve(to: NSPoint(x: 820, y: 481), controlPoint1: NSPoint(x: 522, y: 236), controlPoint2: NSPoint(x: 820, y: 236))
cradle.line(to: NSPoint(x: 820, y: 521)); cradle.lineWidth = 34; cradle.lineCapStyle = .round; cradle.stroke()
stroke([NSPoint(x: 671, y: 297), NSPoint(x: 671, y: 232)], width: 34)
stroke([NSPoint(x: 594, y: 232), NSPoint(x: 748, y: 232)], width: 34)
NSColor(calibratedRed: 0.02, green: 0.37, blue: 0.97, alpha: 1).setFill()
NSColor(calibratedRed: 0.02, green: 0.37, blue: 0.97, alpha: 1).setStroke()
for x in [CGFloat(621), CGFloat(702)] { NSBezierPath(ovalIn: NSRect(x: x, y: 581, width: 30, height: 34)).fill() }
let smile = NSBezierPath(); smile.move(to: NSPoint(x: 626, y: 541))
smile.curve(to: NSPoint(x: 716, y: 541), controlPoint1: NSPoint(x: 648, y: 504), controlPoint2: NSPoint(x: 694, y: 504))
smile.lineWidth = 20; smile.lineCapStyle = .round; smile.stroke()
image.unlockFocus()
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent("AppIcon.png"))
let iconset=destination.appendingPathComponent("AppIcon.iconset",isDirectory:true)
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        image.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels));NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using:.png,properties:[:])!.write(to:iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}

try Data(contentsOf: iconset.appendingPathComponent("icon_512x512@2x.png")).write(to: destination.appendingPathComponent("AppIcon.png"))
