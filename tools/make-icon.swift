// Dibuja el icono de Macropad (placa de metacrilato con 3 mandos y 15 teclas con brillo ámbar) y lo exporta como .iconset
import AppKit
let out = CommandLine.arguments[1]
func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)
    let amber = NSColor(red: 1, green: 0.70, blue: 0.28, alpha: 1)
    // fondo (rejilla de iconos de macOS: 824 pt dentro de 1024)
    let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.15, blue: 0.11, alpha: 1), NSColor(red: 0.07, green: 0.055, blue: 0.045, alpha: 1)])!.draw(in: bg, angle: -90)
    // placa
    let plate = NSRect(x: 305, y: 160, width: 414, height: 704)
    let pp = NSBezierPath()
    let r: CGFloat = 40, big: CGFloat = 150
    pp.move(to: NSPoint(x: plate.minX + r, y: plate.minY))
    pp.line(to: NSPoint(x: plate.maxX - r, y: plate.minY)); pp.curve(to: NSPoint(x: plate.maxX, y: plate.minY + r), controlPoint1: NSPoint(x: plate.maxX - r / 2, y: plate.minY), controlPoint2: NSPoint(x: plate.maxX, y: plate.minY + r / 2))
    pp.line(to: NSPoint(x: plate.maxX, y: plate.maxY - big)); pp.curve(to: NSPoint(x: plate.maxX - big, y: plate.maxY), controlPoint1: NSPoint(x: plate.maxX, y: plate.maxY - big / 2.2), controlPoint2: NSPoint(x: plate.maxX - big / 2.2, y: plate.maxY))
    pp.line(to: NSPoint(x: plate.minX + r, y: plate.maxY)); pp.curve(to: NSPoint(x: plate.minX, y: plate.maxY - r), controlPoint1: NSPoint(x: plate.minX + r / 2, y: plate.maxY), controlPoint2: NSPoint(x: plate.minX, y: plate.maxY - r / 2))
    pp.line(to: NSPoint(x: plate.minX, y: plate.minY + r)); pp.curve(to: NSPoint(x: plate.minX + r, y: plate.minY), controlPoint1: NSPoint(x: plate.minX, y: plate.minY + r / 2), controlPoint2: NSPoint(x: plate.minX + r / 2, y: plate.minY))
    pp.close()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 70, color: amber.withAlphaComponent(0.55).cgColor)
    NSColor(white: 1, alpha: 0.10).setFill(); pp.fill()
    ctx.restoreGState()
    NSGradient(colors: [NSColor(white: 1, alpha: 0.20), NSColor(white: 1, alpha: 0.05)])!.draw(in: pp, angle: -60)
    NSColor(white: 1, alpha: 0.35).setStroke(); pp.lineWidth = 3; pp.stroke()
    // mandos
    func knob(_ c: NSPoint, _ rad: CGFloat) {
        let rect = NSRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)
        NSGradient(starting: NSColor(white: 0.36, alpha: 1), ending: NSColor(white: 0.07, alpha: 1))!.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: NSPoint(x: -0.3, y: 0.35))
        NSColor(white: 1, alpha: 0.4).setStroke(); let o = NSBezierPath(ovalIn: rect); o.lineWidth = 4; o.stroke()
        let n = NSBezierPath(); n.move(to: NSPoint(x: c.x - rad * 0.32, y: c.y + rad * 0.34)); n.line(to: NSPoint(x: c.x - rad * 0.62, y: c.y + rad * 0.68))
        NSColor(white: 0.9, alpha: 1).setStroke(); n.lineWidth = 6; n.lineCapStyle = .round; n.stroke()
    }
    knob(NSPoint(x: 400, y: 770), 44); knob(NSPoint(x: 440, y: 650), 44); knob(NSPoint(x: 600, y: 730), 78)
    // teclas
    for row in 0..<5 { for col in 0..<3 {
        let rect = NSRect(x: 340 + CGFloat(col) * 114, y: 190 + CGFloat(row) * 78 + 0, width: 100, height: 64)
        let k = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 26, color: amber.withAlphaComponent(0.8).cgColor)
        NSColor(red: 0.10, green: 0.08, blue: 0.065, alpha: 1).setFill(); k.fill(); ctx.restoreGState()
        amber.withAlphaComponent(0.55).setStroke(); k.lineWidth = 3; k.stroke()
    } }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: out + "/icon_\(name).png"))
}
