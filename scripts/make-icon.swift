// Renders Resources/AppIcon.icns. Run with: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // macOS icon grid: 824pt tile inside a 1024 canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    color(0x141518).setFill()
    NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s).fill()

    let phone = NSRect(x: 352 * s, y: 190 * s, width: 320 * s, height: 644 * s)
    color(0x4A4A4D).setFill()
    NSBezierPath(roundedRect: phone, xRadius: 70 * s, yRadius: 70 * s).fill()
    color(0x000000).setFill()
    NSBezierPath(roundedRect: phone.insetBy(dx: 8 * s, dy: 8 * s), xRadius: 62 * s, yRadius: 62 * s).fill()

    let screen = phone.insetBy(dx: 24 * s, dy: 24 * s)
    let gradient = NSGradient(colors: [color(0xFF6B4A), color(0xE8A94B), color(0x1FB6A6)], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
    gradient.draw(in: NSBezierPath(roundedRect: screen, xRadius: 46 * s, yRadius: 46 * s), angle: -80)

    color(0x000000).setFill()
    let island = NSRect(x: phone.midX - 46 * s, y: screen.maxY - 44 * s, width: 92 * s, height: 26 * s)
    NSBezierPath(roundedRect: island, xRadius: 13 * s, yRadius: 13 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print(iconset.path)
