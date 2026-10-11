import AppKit
import Foundation
// Original Voice Input Buddy artwork, GPL-3.0-only.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.10, green: 0.17, blue: 0.35, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 210, yRadius: 210).fill()
NSColor(calibratedRed: 0.25, green: 0.88, blue: 0.78, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 370, y: 400, width: 180, height: 380), xRadius: 90, yRadius: 90).fill()
let cradle = NSBezierPath(); cradle.move(to: NSPoint(x: 285, y: 520)); cradle.line(to: NSPoint(x: 285, y: 445)); cradle.curve(to: NSPoint(x: 635,y: 445), controlPoint1: NSPoint(x: 285,y: 220),controlPoint2: NSPoint(x: 635,y: 220)); cradle.line(to: NSPoint(x:635,y:520)); cradle.lineWidth=48; cradle.lineCapStyle = .round; NSColor.white.setStroke(); cradle.stroke()
let stem=NSBezierPath();stem.move(to:NSPoint(x:460,y:285));stem.line(to:NSPoint(x:460,y:180));stem.move(to:NSPoint(x:365,y:180));stem.line(to:NSPoint(x:555,y:180));stem.lineWidth=48;stem.lineCapStyle = .round;stem.stroke()
NSColor(calibratedRed:1,green:0.72,blue:0.30,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:700,y:570,width:160,height:200),xRadius:48,yRadius:48).fill()
NSColor(calibratedRed:0.1,green:0.17,blue:0.35,alpha:1).setFill()
NSBezierPath(ovalIn:NSRect(x:748,y:643,width:64,height:64)).fill()
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
