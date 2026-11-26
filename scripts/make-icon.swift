// Renders assets/icon.svg into an .iconset folder for iconutil.
// Usage: swift scripts/make-icon.swift assets/icon.svg build/AppIcon.iconset
import AppKit

let args = CommandLine.arguments
let svg = URL(fileURLWithPath: args.count > 1 ? args[1] : "assets/icon.svg")
let out = URL(fileURLWithPath: args.count > 2 ? args[2] : "build/AppIcon.iconset")
guard let image = NSImage(contentsOf: svg) else {
    FileHandle.standardError.write("Could not load \(svg.path)\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(out.path)")
