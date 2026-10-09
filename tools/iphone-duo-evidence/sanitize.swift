import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Decode pixels, draw into a new sRGB bitmap, encode without copying properties.
// No source metadata, EXIF, GPS, profiles or original encoded bytes are forwarded.
func fail() -> Never {
    fputs("PNG sanitization failed; no evidence upload\n", stderr)
    exit(1)
}
guard CommandLine.arguments.count == 3 else { fail() }
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard !FileManager.default.fileExists(atPath: output.path),
      let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      CGImageSourceGetType(source) as String? == UTType.png.identifier,
      CGImageSourceGetCount(source) == 1,
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
      original.width <= 3072, original.height <= 2700,
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: original.width, height: original.height,
                              bitsPerComponent: 8, bytesPerRow: original.width * 4,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fail() }
context.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fail() }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail() }
