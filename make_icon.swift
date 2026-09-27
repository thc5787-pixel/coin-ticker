import AppKit

// 生成 AppIcon.iconset（10 个尺寸），随后用 iconutil 打包成 .icns
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let dir = "AppIcon.iconset"
try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

for (name, px) in sizes {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("rep") }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("ctx") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.translateBy(x: 0, y: CGFloat(px))   // 翻转为左上角原点
    cg.scaleBy(x: 1, y: -1)

    let s = CGFloat(px)
    let inset = s * 0.02
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = s * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // 金色渐变背景（中性币价风格）
    let top = NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.18, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.87, green: 0.53, blue: 0.08, alpha: 1)
    if let gradient = NSGradient(colors: [top, bottom]) {
        gradient.draw(in: path, angle: -90)
    }

    // 白色 $ 符号
    let font = NSFont.systemFont(ofSize: s * 0.58, weight: .bold)
    let str = NSAttributedString(string: "$", attributes: [
        .font: font, .foregroundColor: NSColor.white
    ])
    let sz = str.size()
    str.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2 - sz.height * 0.04))

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try! png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
print("iconset 生成完成")
