import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let green = CGColor(red: 0.16, green: 0.34, blue: 0.28, alpha: 1)
let cream = CGColor(red: 0.95, green: 0.89, blue: 0.73, alpha: 1)
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Could not create bitmap") }
context.setFillColor(green)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
func roundRect(_ rect: CGRect, radius: CGFloat, color: CGColor) {
    context.setFillColor(color)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}
roundRect(CGRect(x: 204, y: 247, width: 152, height: 555), radius: 22, color: cream)
roundRect(CGRect(x: 400, y: 247, width: 152, height: 477), radius: 22, color: cream)
roundRect(CGRect(x: 600, y: 247, width: 152, height: 520), radius: 22, color: cream)
for x in [236,432,632] { roundRect(CGRect(x: x, y: 310, width: 88, height: 13), radius: 6, color: green) }
roundRect(CGRect(x: 157, y: 180, width: 662, height: 26), radius: 13, color: cream)
let output = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Could not write icon") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("PNG encoding failed") }
