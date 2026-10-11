import AppKit

// Original schematic. Coordinates share the mapping canvas's normalized anchors.
let size = NSSize(width: 508, height: 1030)
let image = NSImage(size: size)
image.lockFocusFlipped(true)
func round(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
round(NSRect(x: 76, y: 4, width: 356, height: 1022), radius: 68,
      color: NSColor(calibratedWhite: 0.19, alpha: 1))
round(NSRect(x: 81, y: 8, width: 346, height: 1012), radius: 65,
      color: NSColor(calibratedWhite: 0.24, alpha: 1))
// Direction ring; ordinary buttons below it.
round(NSRect(x: 133, y: 163, width: 244, height: 183), radius: 91,
      color: NSColor(calibratedWhite: 0.13, alpha: 1))
let buttons: [(CGFloat, CGFloat, String)] = [
    (0.386, 0.099, "⏻"), (0.630, 0.099, "mic.fill"),
    (0.502, 0.179, "chevron.up"), (0.362, 0.246, "chevron.left"),
    (0.638, 0.246, "chevron.right"), (0.502, 0.317, "chevron.down"),
    (0.502, 0.246, "OK"), (0.406, 0.389, "arrow.uturn.backward"),
    (0.604, 0.390, "+"), (0.406, 0.479, "house"),
    (0.604, 0.480, "−"), (0.406, 0.569, "line.3.horizontal"),
    (0.604, 0.569, "TV")
]
for (x, y, label) in buttons {
    let rect = NSRect(x: x * size.width - 28, y: y * size.height - 28, width: 56, height: 56)
    round(rect, radius: 28, color: NSColor(calibratedWhite: 0.32, alpha: 1))
    if let symbol = NSImage(systemSymbolName: label, accessibilityDescription: nil) {
        symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 23, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white])))?
            .draw(in: rect.insetBy(dx: 15, dy: 15))
    } else {
        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white
        ])
        let measured = text.size()
        text.draw(at: NSPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2))
    }
}
let label = NSAttributedString(string: "VOICE INPUT BUDDY", attributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.6, alpha: 1)
])
label.draw(at: NSPoint(x: (size.width - label.size().width) / 2, y: 875))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: CommandLine.arguments[1]))
