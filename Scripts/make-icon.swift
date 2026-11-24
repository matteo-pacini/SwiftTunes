// Draws the iconset for Scripts/make-icon.sh: every member of a macOS
// .iconset, the square art clipped to the app icon's rounded square.
//
// Usage: swift Scripts/make-icon.swift <source.png> <out.iconset>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <source.png> <out.iconset>\n".utf8))
    exit(2)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let iconsetURL = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(source, 0, nil),
      art.width == 1024, art.height == 1024
else {
    FileHandle.standardError.write(Data("make-icon: \(arguments[1]) is not a 1024 px square image\n".utf8))
    exit(1)
}

// Apple's HIG gives no inset or radius for a pre-shaped macOS icon (it
// expects square art and masks it itself), so this is the long-standing
// macOS grid, an assumption: an 824-point rounded square centred in the
// 1024 canvas, corner radius 185, circular corners, no shadow.
// https://developer.apple.com/design/human-interface-guidelines/app-icons
let canvas: CGFloat = 1024
let shape = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

let members: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

for member in members {
    let pixels = member.pixels
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(1) }
    // Each size is drawn from the 1024 art directly rather than from a
    // smaller member, so no size is a resample of a resample.
    let scale = CGFloat(pixels) / canvas
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high
    context.addPath(CGPath(roundedRect: shape, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    context.clip()
    context.draw(art, in: shape)

    guard let image = context.makeImage() else { exit(1) }
    let url = iconsetURL.appendingPathComponent("\(member.name).png")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("make-icon: could not write \(url.path)\n".utf8))
        exit(1)
    }
}
