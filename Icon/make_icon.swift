// Renders the app icon: a white parachute gently dropping a photo card, under a NameDrop-style glow wave,
// on a sky-to-indigo tile.
//   swift Icon/make_icon.swift   → writes Icon/AppIcon.icns, Icon/AppIcon.png (Mac, squircle)
//                                   and iPhone/Phone/Assets.xcassets/AppIcon.appiconset/AppIcon.png (full bleed)
import AppKit

let size = 1024.0

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let white = hex(0xFFFFFF), canopyTint = hex(0xD9E9FF), ink = hex(0x24308A)
let sun = hex(0xFFC94A), hill = hex(0x2BC4A0), hill2 = hex(0x1C9C86), skyCard = hex(0xBFE4FF)

func renderFull(_ px: Int, ios: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: CGFloat(px) / size, y: CGFloat(px) / size)
    draw(cg, ios: ios)
    NSGraphicsContext.restoreGraphicsState()
    guard ios else { return rep.representation(using: .png, properties: [:])! }
    // iOS icons must be opaque: redraw without an alpha channel.
    let flat = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    flat.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: px, height: px))
    return NSBitmapImageRep(cgImage: flat.makeImage()!).representation(using: .png, properties: [:])!
}

// Every size is shrunk from one full-size drawing. Shadow and glow blur are measured in device pixels, so
// drawing straight at 16–64 px would spill them over the whole image as a faint grey square.
enum Full {
    static let png = renderFull(1024, ios: false)
    static let image = NSBitmapImageRep(data: png)!.cgImage!
}

func render(_ px: Int) -> Data {
    if px == Full.image.width { return Full.png }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    ctx.draw(Full.image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return rep.representation(using: .png, properties: [:])!
}

func draw(_ cg: CGContext, ios: Bool) {
    // Mac: Apple's icon grid, an 824pt squircle centred in a 1024 canvas. iPhone: full bleed (iOS masks it).
    let body = ios ? CGRect(x: 0, y: 0, width: 1024, height: 1024) : CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = CGPath(roundedRect: body, cornerWidth: ios ? 0 : 185, cornerHeight: ios ? 0 : 185, transform: nil)
    if !ios {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: hex(0x000000, 0.3))
        cg.addPath(tile)
        cg.setFillColor(white)
        cg.fillPath()
        cg.restoreGState()
    }

    cg.saveGState()
    cg.addPath(tile)
    cg.clip()
    let sky = CGGradient(colorsSpace: nil, colors: [hex(0x37A2FF), hex(0x4F6BF0), hex(0x5A3BD6)] as CFArray,
                         locations: [0, 0.55, 1])!
    cg.drawLinearGradient(sky, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // The content is laid out for the Mac tile; on iPhone it's scaled up a little to fill the bigger tile.
    if ios {
        cg.translateBy(x: 512, y: 512)
        cg.scaleBy(x: 1.14, y: 1.14)
        cg.translateBy(x: -512, y: -512)
    }

    // NameDrop-style glow wave rolling out of the top edge.
    let top = CGPoint(x: 512, y: ios ? 1010 : 924)
    let glow = CGGradient(colorsSpace: nil, colors: [hex(0xFFFFFF, 0.55), hex(0xA9D8FF, 0.18), hex(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 0.5, 1])!
    cg.drawRadialGradient(glow, startCenter: top, startRadius: 0, endCenter: top, endRadius: 360, options: [])
    cg.setLineCap(.round)
    for (r, a) in [(150.0, 0.55), (230.0, 0.35), (310.0, 0.18)] {
        cg.setStrokeColor(hex(0xFFFFFF, a))
        cg.setLineWidth(14)
        cg.addArc(center: top, radius: r, startAngle: .pi * 1.18, endAngle: .pi * 1.82, clockwise: false)
        cg.strokePath()
    }

    // Parachute canopy: a dome with a scalloped hem, alternate panels lightly tinted.
    let cx = 512.0, hemY = 560.0, half = 250.0, domeH = 210.0
    let scallops = 4
    let w = half * 2 / Double(scallops)
    func hemPoint(_ i: Int) -> CGPoint { CGPoint(x: cx - half + Double(i) * w, y: hemY) }

    let canopy = CGMutablePath()
    canopy.move(to: hemPoint(0))
    canopy.addCurve(to: CGPoint(x: cx, y: hemY + domeH), control1: CGPoint(x: cx - half, y: hemY + domeH * 0.9),
                    control2: CGPoint(x: cx - half * 0.55, y: hemY + domeH))
    canopy.addCurve(to: hemPoint(scallops), control1: CGPoint(x: cx + half * 0.55, y: hemY + domeH),
                    control2: CGPoint(x: cx + half, y: hemY + domeH * 0.9))
    for i in stride(from: scallops, to: 0, by: -1) {
        let a = hemPoint(i), b = hemPoint(i - 1)
        canopy.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: hemY + 46))
    }
    canopy.closeSubpath()

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: hex(0x1B1660, 0.35))
    cg.addPath(canopy)
    cg.setFillColor(white)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(canopy)
    cg.clip()
    for i in [1, 3] {
        let p = CGMutablePath()
        let a = hemPoint(i), b = hemPoint(i + 1)
        p.move(to: CGPoint(x: cx, y: hemY + domeH + 20))
        p.addLine(to: CGPoint(x: a.x, y: hemY - 10))
        p.addLine(to: CGPoint(x: b.x, y: hemY - 10))
        p.closeSubpath()
        cg.addPath(p)
        cg.setFillColor(canopyTint)
        cg.fillPath()
    }
    cg.restoreGState()

    // Photo card hanging underneath, slightly tilted as if it's swaying down.
    let card = CGRect(x: -130, y: -110, width: 260, height: 220)
    let cardCenter = CGPoint(x: 512, y: 300)
    let tilt = -0.07
    func onCard(_ p: CGPoint) -> CGPoint {
        CGPoint(x: cardCenter.x + p.x * cos(tilt) - p.y * sin(tilt), y: cardCenter.y + p.x * sin(tilt) + p.y * cos(tilt))
    }

    // Lines from the hem to the card's top corners.
    cg.setStrokeColor(hex(0xFFFFFF, 0.9))
    cg.setLineWidth(9)
    let left = onCard(CGPoint(x: card.minX + 24, y: card.maxY - 6)), right = onCard(CGPoint(x: card.maxX - 24, y: card.maxY - 6))
    for (i, end) in [(0, left), (1, left), (3, right), (4, right)] {
        cg.move(to: hemPoint(i))
        cg.addLine(to: end)
    }
    cg.strokePath()

    cg.saveGState()
    cg.translateBy(x: cardCenter.x, y: cardCenter.y)
    cg.rotate(by: tilt)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 26, color: hex(0x1B1660, 0.4))
    cg.addPath(CGPath(roundedRect: card, cornerWidth: 30, cornerHeight: 30, transform: nil))
    cg.setFillColor(white)
    cg.fillPath()
    cg.restoreGState()
    // The photo: sky, sun, two hills.
    let photo = card.insetBy(dx: 20, dy: 20)
    cg.addPath(CGPath(roundedRect: photo, cornerWidth: 16, cornerHeight: 16, transform: nil))
    cg.clip()
    cg.setFillColor(skyCard)
    cg.fill(photo)
    cg.setFillColor(sun)
    cg.fillEllipse(in: CGRect(x: photo.maxX - 78, y: photo.maxY - 78, width: 50, height: 50))
    let h1 = CGMutablePath()
    h1.move(to: CGPoint(x: photo.minX, y: photo.minY))
    h1.addLine(to: CGPoint(x: photo.minX, y: photo.minY + 60))
    h1.addQuadCurve(to: CGPoint(x: photo.maxX, y: photo.minY + 40), control: CGPoint(x: photo.minX + 90, y: photo.minY + 170))
    h1.addLine(to: CGPoint(x: photo.maxX, y: photo.minY))
    cg.addPath(h1)
    cg.setFillColor(hill)
    cg.fillPath()
    let h2 = CGMutablePath()
    h2.move(to: CGPoint(x: photo.minX, y: photo.minY))
    h2.addQuadCurve(to: CGPoint(x: photo.maxX, y: photo.minY + 80), control: CGPoint(x: photo.midX + 60, y: photo.minY + 10))
    h2.addLine(to: CGPoint(x: photo.maxX, y: photo.minY))
    cg.addPath(h2)
    cg.setFillColor(hill2)
    cg.fillPath()
    cg.restoreGState()

    cg.restoreGState()
}

let iconset = URL(fileURLWithPath: "Icon/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! Full.png.write(to: URL(fileURLWithPath: "Icon/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Icon/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

let iosDir = URL(fileURLWithPath: "iPhone/Phone/Assets.xcassets/AppIcon.appiconset")
try! FileManager.default.createDirectory(at: iosDir, withIntermediateDirectories: true)
try! renderFull(1024, ios: true).write(to: iosDir.appendingPathComponent("AppIcon.png"))
print("✓ Icon/AppIcon.icns + iPhone app icon")
