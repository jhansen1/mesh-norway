// Draws the app icon: an original mark for Mesh Norway.
//
// A slanted "N" (for Norway) drawn as a mesh path: three links joining four
// nodes, with a radio signal leaving the top node, over a night-blue ground.
// The slanted strokes nod to the angular lettering common to mesh-radio
// projects without using anyone's logo: the shape is a letter N with nodes,
// and the colours are this app's own (teal to blue on navy).
//
// Usage: swift Tools/make-icon.swift MeshtasticNorwayMap/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// No alpha channel: the App Store rejects icons that have one.
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha])!
}
func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

// Ground: night sky, lighter towards the top.
ctx.drawLinearGradient(gradient([rgb(0x1a3555), rgb(0x0b1626)]), start: CGPoint(x: size * 0.3, y: size), end: CGPoint(x: size * 0.7, y: 0),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// A soft glow behind the top node, where the signal leaves.
ctx.drawRadialGradient(gradient([rgb(0x38d6b0, 0.30), rgb(0x38d6b0, 0)]), startCenter: CGPoint(x: 690, y: 700), startRadius: 0,
                       endCenter: CGPoint(x: 690, y: 700), endRadius: 430, options: [])

// The N: its four corners, leaning to the right.
let lean: CGFloat = 0.16
func corner(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x + (y - 512) * lean, y: y) }
let bottomLeft = corner(300, 250), topLeft = corner(300, 706), bottomRight = corner(652, 250), topRight = corner(652, 706)

// The signal: arcs leaving the top-right node, drawn first so the node sits on them.
ctx.setLineCap(.round)
for (radius, alpha) in [(146.0, 0.60), (226.0, 0.32)] as [(CGFloat, CGFloat)] {
    ctx.setStrokeColor(rgb(0xbdf5e6, alpha))
    ctx.setLineWidth(30)
    ctx.addArc(center: topRight, radius: radius, startAngle: -.pi * 0.16, endAngle: .pi * 0.66, clockwise: false)
    ctx.strokePath()
}

// The links, in one stroke with a teal-to-blue run along the letter.
let links = CGMutablePath()
links.move(to: bottomLeft)
links.addLine(to: topLeft)
links.addLine(to: bottomRight)
links.addLine(to: topRight)
ctx.saveGState()
ctx.addPath(links)
ctx.setLineWidth(96)
ctx.setLineJoin(.round)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x35e0b2), rgb(0x3aa8f5)]), start: CGPoint(x: 250, y: 760), end: CGPoint(x: 780, y: 250), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// The nodes: one at each corner.
for point in [bottomLeft, topLeft, bottomRight, topRight] {
    ctx.setFillColor(rgb(0x0b1626))
    ctx.fillEllipse(in: CGRect(x: point.x - 76, y: point.y - 76, width: 152, height: 152))
    ctx.setFillColor(rgb(0xf4fbff))
    ctx.fillEllipse(in: CGRect(x: point.x - 50, y: point.y - 50, width: 100, height: 100))
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out.path)") }
print("wrote \(out.path)")
