// 绘制 Doorman 的 App 图标（1024×1024 PNG）：深蓝圆角方块 + 门 + 从门把手发出的信号弧。
// 用法：swift scripts/make-icon.swift <输出路径.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("无法创建绘图上下文") }

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

// macOS 图标网格：1024 画布内 824×824 的圆角方块，四周留出阴影空间
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// 投影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(rgb(0x1A2D6A))
ctx.fillPath()
ctx.restoreGState()

// 背景渐变
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let background = CGGradient(colorsSpace: space, colors: [rgb(0x3A6BE8), rgb(0x152660)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// 顶部高光
let shine = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])

// 门洞（深色门框）
let frame = CGRect(x: 262, y: 236, width: 316, height: 518)
ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 40, cornerHeight: 40, transform: nil))
ctx.setFillColor(rgb(0x0E1A45, 0.55))
ctx.fillPath()

// 门板
let door = CGRect(x: 290, y: 262, width: 260, height: 466)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0x000000, 0.30))
ctx.addPath(CGPath(roundedRect: door, cornerWidth: 26, cornerHeight: 26, transform: nil))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: door, cornerWidth: 26, cornerHeight: 26, transform: nil))
ctx.clip()
let doorShade = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF), rgb(0xD6E2FF)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(doorShade, start: CGPoint(x: 290, y: 728), end: CGPoint(x: 550, y: 262), options: [])
ctx.restoreGState()

// 门上两块嵌板
for panel in [CGRect(x: 330, y: 520, width: 180, height: 160), CGRect(x: 330, y: 306, width: 180, height: 170)] {
    ctx.addPath(CGPath(roundedRect: panel, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setStrokeColor(rgb(0x9DB4EC, 0.55))
    ctx.setLineWidth(8)
    ctx.strokePath()
}

// 门把手
let knob = CGPoint(x: 508, y: 498)
ctx.addEllipse(in: CGRect(x: knob.x - 20, y: knob.y - 20, width: 40, height: 40))
ctx.setFillColor(rgb(0x2F5BD3))
ctx.fillPath()

// 信号弧：从门的右边缘向外
let origin = CGPoint(x: 566, y: 498)
let arcs: [(radius: CGFloat, alpha: CGFloat)] = [(96, 1.0), (172, 0.75), (248, 0.5)]
ctx.setLineCap(.round)
ctx.setLineWidth(40)
for arc in arcs {
    ctx.setStrokeColor(rgb(0x8FE6FF, arc.alpha))
    ctx.addArc(center: origin, radius: arc.radius, startAngle: -.pi / 4, endAngle: .pi / 4, clockwise: false)
    ctx.strokePath()
}
ctx.restoreGState()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("无法写出图片")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("写出失败") }
print("已生成 \(output)")
