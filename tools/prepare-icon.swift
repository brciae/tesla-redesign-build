import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Asset assembly only: keep the original user artwork and place it at 90% scale.
// Do not use generated/redrawn logo variants or modify the original source file.
let source = "Xcode/IconSource.jpg"
let output = "Xcode/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { fatalError("Cannot decode original icon") }
// RGBX is supported by Quartz bitmap contexts; 24-bit RGB drawing contexts are not.
guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
    bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Cannot create RGBX icon canvas") }
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.interpolationQuality = .high
context.draw(original, in: CGRect(x: 51.2, y: 51.2, width: 921.6, height: 921.6))
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("PNG output failed") }
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
precondition(image.width == 1024 && image.height == 1024 && image.alphaInfo == .noneSkipLast)
print("PASS: original icon at 90% scale, centered on opaque 1024px white canvas")
