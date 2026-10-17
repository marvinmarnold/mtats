// SPDX-License-Identifier: MIT
// Usage: swift Scripts/render-icon.swift <out-dir>
// Writes <out-dir>/AppIcon.iconset/*.png (10 members, with Apple's 100 px margin), and the margin-free
// site assets favicon-32.png, apple-touch-icon.png (180) and og.png (1200x630).
// Same primitives and constants as Resources/AppIcon.svg; keep the two in sync.
import AppKit

let K: CGFloat = 1024
let inset: CGFloat = 100      // squircle origin in the 1024 canvas
let tile: CGFloat = 824       // squircle side
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((h >> 16) & 0xFF) / 255, CGFloat((h >> 8) & 0xFF) / 255, CGFloat(h & 0xFF) / 255, a])!
}
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Draws the icon with its top-left at `origin` (in the context's y-up pixel space), `size` pixels square.
func drawIcon(_ c: CGContext, size: CGFloat, origin: CGPoint) {
    c.saveGState()
    c.translateBy(x: origin.x, y: origin.y)
    c.scaleBy(x: size / K, y: size / K)
    c.translateBy(x: 0, y: K); c.scaleBy(x: 1, y: -1)        // SVG coordinates from here on
    c.addPath(rrect(100, 100, 824, 824, 186)); c.clip()
    let grad = CGGradient(colorsSpace: space, colors: [rgb(0x2C3645), rgb(0x151B24)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(grad, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    c.setFillColor(rgb(0xFFFFFF, 0.06)); c.fillEllipse(in: CGRect(x: -8, y: -80, width: 1040, height: 480))
    c.setFillColor(rgb(0x000000, 0.28)); c.addPath(rrect(192, 388, 640, 280, 64)); c.fillPath()
    c.setFillColor(rgb(0xF2F4F7));       c.addPath(rrect(192, 372, 640, 280, 64)); c.fillPath()
    let pts = [(300, 552), (392, 484), (484, 524), (576, 440), (668, 490), (736, 432)].map { CGPoint(x: $0.0, y: $0.1) }
    c.setStrokeColor(rgb(0x15803D)); c.setLineWidth(56); c.setLineCap(.round); c.setLineJoin(.round)
    c.addLines(between: pts); c.strokePath()
    c.restoreGState()
}

/// Draws only the squircle, scaled so it fills `size` pixels square with its top-left at `origin` (D8).
func drawTile(_ c: CGContext, size: CGFloat, origin: CGPoint) {
    let s = size / tile
    drawIcon(c, size: K * s, origin: CGPoint(x: origin.x - inset * s, y: origin.y - inset * s))
}

func render(width: Int, height: Int, _ draw: (CGContext) -> Void) -> Data {
    let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.clear(CGRect(x: 0, y: 0, width: width, height: height))
    c.setShouldAntialias(true); c.setAllowsAntialiasing(true)
    draw(c)
    return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) throws {
    try data.write(to: URL(fileURLWithPath: path)); print("wrote \(path)")
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/icon"
let iconset = "\(out)/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let members: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in members {
    try write(render(width: px, height: px) { drawIcon($0, size: CGFloat(px), origin: .zero) }, "\(iconset)/\(name).png")
}
try write(render(width: 32, height: 32) { drawTile($0, size: 32, origin: .zero) }, "\(out)/favicon-32.png")
try write(render(width: 180, height: 180) { drawTile($0, size: 180, origin: .zero) }, "\(out)/apple-touch-icon.png")

// Open Graph card: dark ground, 360 px icon tile at left, wordmark and two-line tagline at right.
// Text is drawn in the context's y-up space: draw(at:) puts the string's bottom-left at the point;
// draw(in:) lays lines from the rect's top edge downward. Explicit "\n" so no wrapping is needed.
try write(render(width: 1200, height: 630) { c in
    c.setFillColor(rgb(0x0E1218)); c.fill(CGRect(x: 0, y: 0, width: 1200, height: 630))
    drawTile(c, size: 360, origin: CGPoint(x: 120, y: 135))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    let title = NSAttributedString(string: "mtats", attributes: [
        .font: NSFont.systemFont(ofSize: 120, weight: .bold),
        .foregroundColor: NSColor(cgColor: rgb(0xEDEFF2))!, .kern: -3.0])
    let tagline = NSAttributedString(string: "Mac stats you wear\non your sleeve.", attributes: [
        .font: NSFont.systemFont(ofSize: 44, weight: .regular),
        .foregroundColor: NSColor(cgColor: rgb(0x9AA3AF))!])
    title.draw(at: NSPoint(x: 540, y: 320))
    tagline.draw(in: NSRect(x: 540, y: 150, width: 640, height: 140))
    NSGraphicsContext.restoreGraphicsState()
}, "\(out)/og.png")
