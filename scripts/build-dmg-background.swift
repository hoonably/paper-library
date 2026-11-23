#!/usr/bin/env swift
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let guideURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("assets/first-open.png")
guard let guide = NSImage(contentsOf: guideURL) else { fatalError("Missing first-open guide") }
let size = NSSize(width: 640, height: 580)
let image = NSImage(size: size)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    color(248, 250, 248).setFill()
    NSRect(origin: .zero, size: size).fill()
    guide.draw(in: NSRect(x: 32, y: 16, width: 576, height: 182))
    let headerTransform = NSAffineTransform()
    headerTransform.translateX(by: 0, yBy: size.height - 420)
    headerTransform.concat()
    ("Paper Library" as NSString).draw(at: NSPoint(x: 40, y: 337), withAttributes: [
        .font: NSFont.systemFont(ofSize: 32, weight: .semibold), .foregroundColor: color(33, 62, 53),
    ])
    ("앱을 응용 프로그램 폴더로 드래그해 설치하세요." as NSString).draw(
        at: NSPoint(x: 42, y: 305), withAttributes: [
            .font: NSFont.systemFont(ofSize: 15), .foregroundColor: color(99, 114, 104),
        ])
    NSColor.white.setFill()
    let panel = NSBezierPath(roundedRect: NSRect(x: 32, y: 65, width: 576, height: 215), xRadius: 12, yRadius: 12)
    panel.fill()
    color(226, 233, 227).setStroke()
    panel.lineWidth = 1
    panel.stroke()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 294, y: 202)); arrow.line(to: NSPoint(x: 346, y: 202))
    arrow.move(to: NSPoint(x: 335, y: 213)); arrow.line(to: NSPoint(x: 346, y: 202)); arrow.line(to: NSPoint(x: 335, y: 191))
    color(37, 107, 84).setStroke()
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}
guard let data = image.tiffRepresentation else { fatalError("Could not render installer background") }
try data.write(to: output)
