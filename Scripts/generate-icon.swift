import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let green = CGColor(colorSpace: colorSpace, components: [18 / 255.0, 63 / 255.0, 53 / 255.0, 1])!
let cream = CGColor(colorSpace: colorSpace, components: [244 / 255.0, 236 / 255.0, 217 / 255.0, 1])!
let brass = CGColor(colorSpace: colorSpace, components: [217 / 255.0, 185 / 255.0, 108 / 255.0, 1])!
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Could not create bitmap") }
context.setFillColor(green)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Approved Regent mark, 256-unit SVG geometry. Keep the outer tile square:
// iOS applies the icon mask. The PNG is opaque and uses the sRGB palette.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)
context.translateBy(x: 51.2, y: 51.2)
context.scaleBy(x: 3.6, y: 3.6)
context.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.125, d: 1, tx: 16, ty: 0))

func addPolygon(_ points: [(CGFloat, CGFloat)], to path: CGMutablePath) {
    guard let first = points.first else { return }
    path.move(to: CGPoint(x: first.0, y: first.1))
    for point in points.dropFirst() {
        path.addLine(to: CGPoint(x: point.0, y: point.1))
    }
    path.closeSubpath()
}

let letter = CGMutablePath()
addPolygon([(48, 32), (168, 32), (216, 80), (216, 112), (200, 128),
            (216, 144), (216, 176), (168, 224), (48, 224)], to: letter)
// Slightly larger counters compensate for the light mark on a dark tile.
addPolygon([(86, 70), (86, 114), (170, 114), (170, 87), (153, 70)], to: letter)
addPolygon([(86, 142), (86, 186), (153, 186), (170, 169), (170, 142)], to: letter)
context.setFillColor(cream)
context.addPath(letter)
context.drawPath(using: .eoFill)

let facets = CGMutablePath()
addPolygon([(168, 32), (216, 80), (168, 80)], to: facets)
addPolygon([(168, 176), (216, 176), (168, 224)], to: facets)
context.setFillColor(brass)
context.addPath(facets)
context.fillPath()

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Could not write icon") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("PNG encoding failed") }
