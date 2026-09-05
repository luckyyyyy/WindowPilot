import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: pixels * 4, bitsPerPixel: 32)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let ctx = graphics.cgContext
        ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let base = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 198, yRadius: 198)
        NSGradient(colors: [NSColor(calibratedRed: 0.12, green: 0.23, blue: 0.66, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.43, blue: 0.91, alpha: 1),
            NSColor(calibratedRed: 0.21, green: 0.68, blue: 0.95, alpha: 1)])!.draw(in: base, angle: 70)
        NSColor.white.withAlphaComponent(0.20).setStroke(); base.lineWidth = 2; base.stroke()
        // Two distinct windows and a switching arrow; readable down to 16 px.
        let rear = NSBezierPath(roundedRect: NSRect(x: 200, y: 396, width: 476, height: 334), xRadius: 43, yRadius: 43)
        NSColor.white.withAlphaComponent(0.57).setFill(); rear.fill()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.17)
        shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -12)
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        let front = NSBezierPath(roundedRect: NSRect(x: 340, y: 258, width: 476, height: 334), xRadius: 43, yRadius: 43)
        NSColor.white.setFill(); front.fill()
        NSGraphicsContext.restoreGraphicsState()
        let blue = NSColor(calibratedRed: 0.12, green: 0.40, blue: 0.85, alpha: 1)
        blue.withAlphaComponent(0.17).setFill()
        NSBezierPath(roundedRect: NSRect(x: 364, y: 513, width: 428, height: 53), xRadius: 16, yRadius: 16).fill()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 438, y: 396)); arrow.line(to: NSPoint(x: 707, y: 396))
        arrow.move(to: NSPoint(x: 645, y: 458)); arrow.line(to: NSPoint(x: 710, y: 396)); arrow.line(to: NSPoint(x: 645, y: 334))
        arrow.lineWidth = 27; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
        blue.setStroke(); arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name))
    }
}
