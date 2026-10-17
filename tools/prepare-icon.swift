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

// Live Activity snapshots must decode a small icon, not a full-size app artwork.
let islandPath = "Xcode/IslandAssets.xcassets/IslandAppIcon.imageset/IslandAppIcon.png"
guard let small = CGContext(data: nil, width: 60, height: 60, bitsPerComponent: 8,
    bytesPerRow: 240, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Island canvas failed") }
small.interpolationQuality = .high
small.draw(original, in: CGRect(x: 0, y: 0, width: 60, height: 60))
guard let islandImage = small.makeImage(), let islandOutput = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: islandPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Island icon failed") }
CGImageDestinationAddImage(islandOutput, islandImage, nil)
precondition(CGImageDestinationFinalize(islandOutput))
print("PASS: original artwork resized to a 60px Live Activity asset")
