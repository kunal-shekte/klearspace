import AppKit
import Foundation

let build = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build")
let root = build.appendingPathComponent("Klearspace.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let mint = NSColor(calibratedRed: 0.67, green: 0.91, blue: 0.72, alpha: 1)
let dark = NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.063, alpha: 1)
let shadow = NSShadow(); shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 28; shadow.shadowColor = .black.withAlphaComponent(0.25); shadow.set()
let shape = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 195, yRadius: 195)
dark.setFill(); shape.fill()
NSShadow().set()
let orbit = NSBezierPath(ovalIn: NSRect(x: 210, y: 210, width: 604, height: 604))
orbit.lineWidth = 25; mint.withAlphaComponent(0.18).setStroke(); orbit.stroke()
let arc = NSBezierPath(); arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 302, startAngle: 40, endAngle: 292, clockwise: false); arc.lineWidth = 25; arc.lineCapStyle = .round; mint.setStroke(); arc.stroke()
func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    let path = NSBezierPath(); path.move(to: NSPoint(x: x, y: y + r))
    path.curve(to: NSPoint(x: x + r, y: y), controlPoint1: NSPoint(x: x + r * 0.22, y: y + r * 0.22), controlPoint2: NSPoint(x: x + r * 0.22, y: y + r * 0.22))
    path.curve(to: NSPoint(x: x, y: y - r), controlPoint1: NSPoint(x: x + r * 0.22, y: y - r * 0.22), controlPoint2: NSPoint(x: x + r * 0.22, y: y - r * 0.22))
    path.curve(to: NSPoint(x: x - r, y: y), controlPoint1: NSPoint(x: x - r * 0.22, y: y - r * 0.22), controlPoint2: NSPoint(x: x - r * 0.22, y: y - r * 0.22))
    path.curve(to: NSPoint(x: x, y: y + r), controlPoint1: NSPoint(x: x - r * 0.22, y: y + r * 0.22), controlPoint2: NSPoint(x: x - r * 0.22, y: y + r * 0.22)); path.close(); mint.setFill(); path.fill()
}
sparkle(485, 482, 155); sparkle(657, 651, 65); sparkle(330, 663, 33)
image.unlockFocus()
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size)); NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name + ".png"))
}
