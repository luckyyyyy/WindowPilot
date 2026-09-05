import AppKit

let destination = CommandLine.arguments[1]
let width: CGFloat = 660, height: CGFloat = 430
var representations: [NSBitmapImageRep] = []
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: Int(width) * scale * 4, bitsPerPixel: 32)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = graphics
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    NSGradient(colors: [NSColor(red: 0.89, green: 0.94, blue: 1, alpha: 1),
                        NSColor(red: 0.98, green: 0.99, blue: 1, alpha: 1)])!.draw(in: bounds, angle: 90)
    let blue = NSColor(red: 0.13, green: 0.40, blue: 0.88, alpha: 1)
    func text(_ value: String, y: CGFloat, font: NSFont, color: NSColor) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (value as NSString).draw(in: NSRect(x: 30, y: y, width: 600, height: 45),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
    text("WindowPilot", y: 339, font: .systemFont(ofSize: 30, weight: .bold), color: NSColor(red: 0.10, green: 0.16, blue: 0.29, alpha: 1))
    text("Drag to Applications", y: 307, font: .systemFont(ofSize: 15, weight: .medium), color: NSColor(calibratedWhite: 0.42, alpha: 1))
    for x: CGFloat in [96, 404] {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = blue.withAlphaComponent(0.10)
        shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -5); shadow.set()
        NSColor.white.withAlphaComponent(0.84).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 119, width: 160, height: 178), xRadius: 24, yRadius: 24).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 292, y: 218)); arrow.line(to: NSPoint(x: 368, y: 218))
    arrow.move(to: NSPoint(x: 353, y: 233)); arrow.line(to: NSPoint(x: 368, y: 218)); arrow.line(to: NSPoint(x: 353, y: 203))
    arrow.lineWidth = 4; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    blue.setStroke(); arrow.stroke()
    text("拖入「应用程序」文件夹即可安装", y: 61, font: .systemFont(ofSize: 13, weight: .medium), color: blue)
    text("首次打开后，按提示开启辅助功能权限", y: 31, font: .systemFont(ofSize: 12), color: NSColor(white: 0.40, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    representations.append(bitmap)
}
let image = NSImage(size: NSSize(width: width, height: height))
representations.forEach { image.addRepresentation($0) }
try image.tiffRepresentation!.write(to: URL(fileURLWithPath: destination))
