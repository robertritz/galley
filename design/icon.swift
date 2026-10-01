import AppKit
import CoreGraphics

// Renders Galley's app icon ("on the table": two editions fanned on warm paper)
// at 1024 px on the macOS icon grid (824 px body).
//
//   swiftc -O design/icon.swift -o /tmp/icon && /tmp/icon design   # → design/icon-1024.png
//
// Then resize into Galley/Assets.xcassets/AppIcon.appiconset and site/img.
let out = CommandLine.arguments[1]
let S: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Apple-style continuous-corner squircle (superellipse) for the icon body.
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(); let n = 5.0; let steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1), y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let pt = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath(); return p
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func withShadow(_ ctx: CGContext, offset: CGSize, blur: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    ctx.saveGState(); ctx.setShadow(offset: offset, blur: blur, color: color(0x1a0e05, alpha)); draw(); ctx.restoreGState()
}

func rounded(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, _ fill: CGColor) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.setFillColor(fill); ctx.fillPath()
}

func text(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .bold, serif: Bool = true, color c: NSColor, kern: CGFloat = 0) {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if serif, let d = font.fontDescriptor.withDesign(.serif) { font = NSFont(descriptor: d, size: size)! }
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c, .kern: kern])
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    str.draw(at: p)
    NSGraphicsContext.restoreGraphicsState()
}

/// A magazine cover in local coordinates (origin bottom-left, w × h).
func cover(_ ctx: CGContext, w: CGFloat, h: CGFloat, photo: [CGColor], accent: UInt32 = 0xc4332a) {
    rounded(ctx, CGRect(x: 0, y: 0, width: w, height: h), 10, color(0xfffdf8))
    let m = w * 0.075
    // Masthead
    text(ctx, "Galley", at: CGPoint(x: m - 4, y: h - m - w * 0.24), size: w * 0.235, weight: .heavy, color: NSColor(cgColor: color(0x141210))!, kern: -w * 0.006)
    ctx.setFillColor(color(0x141210)); ctx.fill(CGRect(x: m, y: h - m - w * 0.285, width: w - 2 * m, height: w * 0.008))
    ctx.setFillColor(color(accent)); ctx.fill(CGRect(x: m, y: h - m - w * 0.325, width: w * 0.16, height: w * 0.022))
    // Photo: dusk sky over hills
    let photoRect = CGRect(x: m, y: h * 0.27, width: w - 2 * m, height: h * 0.40)
    ctx.saveGState(); ctx.clip(to: photoRect)
    linear(ctx, photo, from: CGPoint(x: 0, y: photoRect.maxY), to: CGPoint(x: 0, y: photoRect.minY))
    ctx.setFillColor(color(0xfff1c9, 0.95)); ctx.fillEllipse(in: CGRect(x: photoRect.midX + w * 0.08, y: photoRect.minY + photoRect.height * 0.38, width: w * 0.16, height: w * 0.16))
    let hills = CGMutablePath(); hills.move(to: CGPoint(x: photoRect.minX, y: photoRect.minY))
    hills.addLine(to: CGPoint(x: photoRect.minX, y: photoRect.minY + photoRect.height * 0.42))
    hills.addCurve(to: CGPoint(x: photoRect.midX, y: photoRect.minY + photoRect.height * 0.30), control1: CGPoint(x: photoRect.minX + w * 0.15, y: photoRect.minY + photoRect.height * 0.62), control2: CGPoint(x: photoRect.midX - w * 0.12, y: photoRect.minY + photoRect.height * 0.25))
    hills.addCurve(to: CGPoint(x: photoRect.maxX, y: photoRect.minY + photoRect.height * 0.48), control1: CGPoint(x: photoRect.midX + w * 0.15, y: photoRect.minY + photoRect.height * 0.36), control2: CGPoint(x: photoRect.maxX - w * 0.1, y: photoRect.minY + photoRect.height * 0.55))
    hills.addLine(to: CGPoint(x: photoRect.maxX, y: photoRect.minY)); hills.closeSubpath()
    ctx.addPath(hills); ctx.setFillColor(color(0x1c2433, 0.92)); ctx.fillPath()
    ctx.restoreGState()
    // Headline and deck lines
    ctx.setFillColor(color(0x141210))
    ctx.fill(CGRect(x: m, y: h * 0.185, width: w * 0.70, height: w * 0.045))
    ctx.fill(CGRect(x: m, y: h * 0.125, width: w * 0.48, height: w * 0.045))
    ctx.setFillColor(color(0x8a8378))
    ctx.fill(CGRect(x: m, y: h * 0.075, width: w * 0.80, height: w * 0.018))
}

func render(_ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

/// Body with drop shadow, gradient fill and a soft top sheen, then clipped content.
func tile(_ ctx: CGContext, top: UInt32, bottom: UInt32, content: () -> Void) {
    withShadow(ctx, offset: CGSize(width: 0, height: -10), blur: 26, alpha: 0.35) {
        ctx.addPath(squircle(body)); ctx.setFillColor(color(bottom)); ctx.fillPath()
    }
    ctx.saveGState(); ctx.addPath(squircle(body)); ctx.clip()
    linear(ctx, [color(top), color(bottom)], from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.minY))
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xffffff, 0.22), color(0xffffff, 0)] as CFArray, locations: nil)!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 512, y: 980), startRadius: 0, endCenter: CGPoint(x: 512, y: 980), endRadius: 560, options: [])
    content()
    ctx.restoreGState()
    // Hairline edge, as on Apple's icons
    ctx.addPath(squircle(body.insetBy(dx: 1, dy: 1))); ctx.setStrokeColor(color(0xffffff, 0.18)); ctx.setLineWidth(2); ctx.strokePath()
}

let dusk = [color(0x2c4a77), color(0x8d6aa8), color(0xf0956a)]

render("icon-1024") { ctx in
    tile(ctx, top: 0xf7f1e6, bottom: 0xe9dfcd) {
        ctx.saveGState(); ctx.translateBy(x: 590, y: 520); ctx.rotate(by: 0.20); ctx.translateBy(x: -225, y: -295)
        withShadow(ctx, offset: CGSize(width: 0, height: -12), blur: 30, alpha: 0.3) { rounded(ctx, CGRect(x: 0, y: 0, width: 450, height: 590), 10, color(0xfffdf8)) }
        cover(ctx, w: 450, h: 590, photo: [color(0x1f3d33), color(0x6d9a72), color(0xe8d38a)], accent: 0x1f6f5c)
        ctx.restoreGState()
        ctx.saveGState(); ctx.translateBy(x: 450, y: 500); ctx.rotate(by: -0.10); ctx.translateBy(x: -240, y: -315)
        withShadow(ctx, offset: CGSize(width: 0, height: -16), blur: 34, alpha: 0.4) { rounded(ctx, CGRect(x: 0, y: 0, width: 480, height: 630), 10, color(0xfffdf8)) }
        cover(ctx, w: 480, h: 630, photo: dusk)
        ctx.restoreGState()
    }
}
