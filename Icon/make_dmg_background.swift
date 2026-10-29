// Renders the background for the Pampu.dmg installer window (640×400, plus @2x).
//   swift Icon/make_dmg_background.swift <out.tiff>
// build.sh --dist runs this; icons sit at (160, 190) and (480, 190) in Finder's top-left coordinates.
import AppKit

let w = 640.0, h = 400.0
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let ink = hex(0x1E2559), blue = hex(0x2A8FFF), violet = hex(0x6B4CE6)

func render(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w) * scale, pixelsHigh: Int(h) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    let bg = CGGradient(colorsSpace: nil, colors: [hex(0xD6ECFF).cgColor, hex(0xE6E2FF).cgColor, hex(0xF3EEFF).cgColor] as CFArray,
                        locations: [0, 0.6, 1])!
    cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: .zero, options: [])

    // NameDrop-style rings rolling down from the top edge.
    for (i, r) in [70.0, 120.0, 175.0, 235.0].enumerated() {
        cg.setStrokeColor(blue.withAlphaComponent(0.16 - CGFloat(i) * 0.03).cgColor)
        cg.setLineWidth(2)
        cg.strokeEllipse(in: CGRect(x: w / 2 - r * 1.6, y: h - r * 0.55, width: r * 3.2, height: r * 1.1))
    }

    // A couple of small parachutes drifting down.
    func chute(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ tilt: CGFloat) {
        cg.saveGState()
        cg.translateBy(x: x, y: y)
        cg.rotate(by: tilt)
        let canopy = CGMutablePath()
        canopy.move(to: CGPoint(x: -s, y: 0))
        canopy.addCurve(to: CGPoint(x: s, y: 0), control1: CGPoint(x: -s, y: s * 1.15), control2: CGPoint(x: s, y: s * 1.15))
        for k in stride(from: 1.0, through: -1.0, by: -0.5) {   // scalloped hem
            canopy.addQuadCurve(to: CGPoint(x: s * (k - 0.5), y: 0), control: CGPoint(x: s * (k - 0.25), y: -s * 0.18))
        }
        canopy.closeSubpath()
        cg.addPath(canopy)
        cg.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        cg.fillPath()
        cg.setStrokeColor(violet.withAlphaComponent(0.35).cgColor)
        cg.setLineWidth(1)
        for dx in [-s * 0.9, -s * 0.3, s * 0.3, s * 0.9] {
            cg.move(to: CGPoint(x: dx, y: -s * 0.05))
            cg.addLine(to: CGPoint(x: 0, y: -s * 1.1))
        }
        cg.strokePath()
        cg.setFillColor(blue.withAlphaComponent(0.7).cgColor)
        cg.fill(CGRect(x: -s * 0.22, y: -s * 1.45, width: s * 0.44, height: s * 0.36))
        cg.restoreGState()
    }
    chute(70, h - 70, 20, 0.12)
    chute(574, h - 96, 15, -0.15)

    // Dotted arc from the app to Applications, ending in an arrowhead.
    let y = h - 190
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: 245, y: y))
    arc.addQuadCurve(to: CGPoint(x: 385, y: y), control: CGPoint(x: 315, y: y + 40))
    cg.addPath(arc.copy(dashingWithPhase: 0, lengths: [2, 12]).copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 10))
    cg.move(to: CGPoint(x: 398, y: y - 4))
    cg.addLine(to: CGPoint(x: 376, y: y + 12))
    cg.addLine(to: CGPoint(x: 380, y: y - 12))
    cg.closePath()
    cg.setFillColor(violet.cgColor)
    cg.fillPath()

    // Finder draws icon labels in black (Light Mode) or white (Dark Mode); a mid-grey nameplate
    // under each label keeps both readable on the light background.
    for x in [160.0, 480.0] {
        let plate = CGPath(roundedRect: CGRect(x: x - 75, y: h - 283, width: 150, height: 28),
                           cornerWidth: 14, cornerHeight: 14, transform: nil)
        cg.addPath(plate)
        cg.setFillColor(ink.withAlphaComponent(0.35).cgColor)
        cg.fillPath()
    }

    func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, y: CGFloat, kern: CGFloat = 0) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { font = f }
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para, .kern: kern])
        str.draw(in: CGRect(x: 0, y: y, width: w, height: size * 1.5))
    }
    text("🪂 PAMPU", 14, .heavy, violet, y: h - 104, kern: 2)
    text("Drag Pampu into Applications to install", 17, .bold, ink, y: 84)
    text("First launch blocked? System Settings → Privacy & Security → Open Anyway", 11, .medium,
         ink.withAlphaComponent(0.75), y: 18)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.tiff"
// A multi-representation TIFF lets Finder pick the sharp 2x image on Retina screens.
let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
try! data.write(to: URL(fileURLWithPath: out))
print("✓ wrote \(out)")
