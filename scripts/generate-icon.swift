import AppKit
import Foundation

let folder = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func draw(_ size: Int) throws {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
    let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 208, yRadius: 208)
    NSColor(calibratedRed: 0.24, green: 0.39, blue: 0.30, alpha: 1).setFill(); background.fill()
    let book = NSBezierPath(roundedRect: NSRect(x: 252, y: 180, width: 530, height: 650), xRadius: 56, yRadius: 56)
    NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.90, alpha: 1).setFill(); book.fill()
    NSColor(calibratedRed: 0.80, green: 0.82, blue: 0.71, alpha: 1).setStroke()
    let spine = NSBezierPath(); spine.move(to: NSPoint(x: 340, y: 200)); spine.line(to: NSPoint(x: 340, y: 810)); spine.lineWidth = 7; spine.stroke()
    NSColor(calibratedRed: 0.24, green: 0.39, blue: 0.30, alpha: 1).setFill()
    let leaf = NSBezierPath(); leaf.move(to: NSPoint(x: 453, y: 438)); leaf.curve(to: NSPoint(x: 664, y: 678), controlPoint1: NSPoint(x: 418, y: 638), controlPoint2: NSPoint(x: 580, y: 718)); leaf.curve(to: NSPoint(x: 453, y: 438), controlPoint1: NSPoint(x: 730, y: 470), controlPoint2: NSPoint(x: 530, y: 398)); leaf.fill()
    NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.90, alpha: 1).setStroke()
    let vein = NSBezierPath(); vein.move(to: NSPoint(x: 473, y: 451)); vein.line(to: NSPoint(x: 637, y: 639)); vein.lineWidth = 7; vein.stroke()
    NSColor(calibratedRed: 0.74, green: 0.67, blue: 0.48, alpha: 1).setStroke()
    let lines = NSBezierPath(); for y in [300, 345] { lines.move(to: NSPoint(x: 430, y: y)); lines.line(to: NSPoint(x: 650, y: y)) }; lines.lineWidth = 10; lines.lineCapStyle = .round; lines.stroke()
    image.unlockFocus()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    let names: [Int: [String]] = [16: ["icon_16x16.png"], 32: ["icon_16x16@2x.png", "icon_32x32.png"], 64: ["icon_32x32@2x.png"], 128: ["icon_128x128.png"], 256: ["icon_128x128@2x.png", "icon_256x256.png"], 512: ["icon_256x256@2x.png", "icon_512x512.png"], 1024: ["icon_512x512@2x.png"]]
    for name in names[size] ?? [] { try data.write(to: folder.appendingPathComponent(name)) }
}
for size in [16, 32, 64, 128, 256, 512, 1024] { try draw(size) }
func integer(_ value: Int) -> Data { var be = UInt32(value).bigEndian; return withUnsafeBytes(of: &be) { Data($0) } }
var chunks = Data()
for (kind, name) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: folder.appendingPathComponent(name))
    chunks.append(Data(kind.utf8)); chunks.append(integer(png.count + 8)); chunks.append(png)
}
var icns = Data("icns".utf8); icns.append(integer(chunks.count + 8)); icns.append(chunks)
try icns.write(to: URL(fileURLWithPath: "Resources/AppIcon.icns"))
