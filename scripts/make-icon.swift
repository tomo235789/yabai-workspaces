import AppKit

// Draws the ywr app icon (a tiled-window layout on a blue squircle) to a 1024px
// PNG at the path given as argv[1]. scripts/make-icon.sh turns it into an .icns.

let side: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Squircle background with a vertical blue gradient (macOS-style padding).
let inset: CGFloat = 100
let bg = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let squircle = CGPath(roundedRect: bg, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(91, 155, 255), color(59, 111, 224)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bg.maxY), end: CGPoint(x: 0, y: bg.minY), options: [])
ctx.restoreGState()

// Tiled "windows": one tall pane on the left, two stacked on the right.
func window(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    let r = CGRect(x: bg.minX + bg.width * x, y: bg.minY + bg.height * y,
                   width: bg.width * w, height: bg.height * h)
    let path = CGPath(roundedRect: r, cornerWidth: 46, cornerHeight: 46, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0, 0, 0, 0.22))
    ctx.addPath(path)
    ctx.setFillColor(color(255, 255, 255, 0.96))
    ctx.fillPath()
    ctx.restoreGState()
}
window(0.14, 0.16, 0.36, 0.68) // left tall
window(0.54, 0.52, 0.32, 0.32) // right top
window(0.54, 0.16, 0.32, 0.28) // right bottom

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8)); exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
} catch {
    FileHandle.standardError.write(Data("failed to write \(outPath): \(error)\n".utf8)); exit(1)
}
