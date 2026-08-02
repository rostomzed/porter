// Renders the Porter app icon (funnel: many files in, one PDF out) as a PNG.
// Run: swift scripts/make-icon.swift <output.png> <size>
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let sizeArg = Int(args[2]) else {
    print("usage: make-icon.swift <output.png> <size>")
    exit(1)
}
let outputURL = URL(fileURLWithPath: args[1])
let s = CGFloat(sizeArg)

let image = NSImage(size: NSSize(width: s, height: s))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS squircle canvas with dark gradient
let margin = s * 0.09
let rect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225).addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.13, alpha: 1),
])!.draw(in: rect, angle: -90)

/// A document sheet with a folded corner.
func sheet(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
           rotation: CGFloat = 0, color: NSColor) {
    ctx.saveGState()
    ctx.translateBy(x: x + w / 2, y: y + h / 2)
    ctx.rotate(by: rotation)
    ctx.translateBy(x: -(w / 2), y: -(h / 2))
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.03,
                  color: NSColor.black.withAlphaComponent(0.3).cgColor)
    let fold = w * 0.26
    let p = CGMutablePath()
    p.move(to: .init(x: 0, y: 0))
    p.addLine(to: .init(x: 0, y: h))
    p.addLine(to: .init(x: w - fold, y: h))
    p.addLine(to: .init(x: w, y: h - fold))
    p.addLine(to: .init(x: w, y: 0))
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(color.cgColor); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setFillColor(NSColor(calibratedWhite: 0.8, alpha: 1).cgColor)
    let f = CGMutablePath()
    f.move(to: .init(x: w - fold, y: h)); f.addLine(to: .init(x: w - fold, y: h - fold))
    f.addLine(to: .init(x: w, y: h - fold)); f.closeSubpath()
    ctx.addPath(f); ctx.fillPath()
    ctx.restoreGState()
}

// Colorful sheets falling into the funnel
let sw = rect.width * 0.17, sh = sw * 1.25
sheet(x: rect.midX - sw * 1.8, y: rect.maxY - rect.height * 0.30, w: sw, h: sh,
      rotation: 0.32, color: NSColor(calibratedRed: 0.35, green: 0.56, blue: 0.98, alpha: 1))
sheet(x: rect.midX + sw * 0.8, y: rect.maxY - rect.height * 0.31, w: sw, h: sh,
      rotation: -0.35, color: NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.47, alpha: 1))
sheet(x: rect.midX - sw * 0.5, y: rect.maxY - rect.height * 0.26, w: sw, h: sh,
      rotation: 0.06, color: NSColor(calibratedRed: 0.99, green: 0.72, blue: 0.25, alpha: 1))

// Funnel
let fw = rect.width * 0.62, fh = rect.height * 0.30
let fx = rect.midX - fw / 2, fy = rect.midY - rect.height * 0.10
let spout = fw * 0.18
let funnel = CGMutablePath()
funnel.move(to: .init(x: fx, y: fy + fh))
funnel.addLine(to: .init(x: fx + fw, y: fy + fh))
funnel.addLine(to: .init(x: rect.midX + spout / 2, y: fy + fh * 0.35))
funnel.addLine(to: .init(x: rect.midX + spout / 2, y: fy))
funnel.addLine(to: .init(x: rect.midX - spout / 2, y: fy))
funnel.addLine(to: .init(x: rect.midX - spout / 2, y: fy + fh * 0.35))
funnel.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.04,
              color: NSColor.black.withAlphaComponent(0.5).cgColor)
ctx.addPath(funnel)
ctx.setFillColor(NSColor(calibratedWhite: 0.88, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.setFillColor(NSColor(calibratedWhite: 0.97, alpha: 1).cgColor)
ctx.fill(CGRect(x: fx, y: fy + fh - fh * 0.09, width: fw, height: fh * 0.09))

// Red PDF sheet emerging below the spout
let pw = rect.width * 0.30, ph = pw * 1.2
let px = rect.midX - pw / 2, py = fy - ph - rect.height * 0.015
sheet(x: px, y: py, w: pw, h: ph,
      color: NSColor(calibratedRed: 0.91, green: 0.25, blue: 0.21, alpha: 1))

let para = NSMutableParagraphStyle(); para.alignment = .center
let font = NSFont.systemFont(ofSize: pw * 0.32, weight: .heavy)
let label = NSAttributedString(string: "PDF", attributes: [
    .font: font, .foregroundColor: NSColor.white, .paragraphStyle: para,
    .kern: pw * 0.02])
let bounds = label.boundingRect(with: .init(width: 4000, height: 4000))
label.draw(at: NSPoint(x: rect.midX - bounds.width / 2,
                       y: py + ph * 0.42 - (font.ascender + font.descender) / 2))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("failed to encode png")
    exit(1)
}
try! png.write(to: outputURL)
