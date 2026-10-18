// Run from Hasp/: swiftc -parse-as-library Hasp/IconStyle.swift scripts/generate-icons.swift
// -o build/generate-icons && build/generate-icons
import AppKit

@main
struct GenerateIcons {
    static func main() throws {
        let directory = URL(fileURLWithPath: "Hasp/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var entries: [[String: String]] = []
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let name = "icon_\(points)x\(points)@\(scale)x.png"
                try render(size: pixels).write(to: directory.appendingPathComponent(name))
                entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
            }
        }
        let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("Contents.json"))
    }

    private static func render(size: Int) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 184, cornerHeight: 184, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 28,
                          color: NSColor.black.withAlphaComponent(0.16).cgColor)
        context.addPath(tile)
        context.setFillColor(NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.67, alpha: 1).cgColor)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(tile)
        context.clip()
        let colors = [NSColor(calibratedRed: 0.17, green: 0.29, blue: 0.54, alpha: 1).cgColor,
                      NSColor(calibratedRed: 0.31, green: 0.56, blue: 0.89, alpha: 1).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 800, y: 100), end: CGPoint(x: 230, y: 924), options: [])
        context.restoreGState()
        context.addPath(tile)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
        context.setLineWidth(2)
        context.strokePath()
        context.saveGState()
        context.translateBy(x: 232, y: 232)
        context.scaleBy(x: 35, y: 35)
        context.addPath(HaspGlyph.path)
        context.setFillColor(NSColor(calibratedWhite: 0.98, alpha: 1).cgColor)
        // Winding fill keeps overlapping rails and knobs a solid silhouette.
        context.fillPath()
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
}
