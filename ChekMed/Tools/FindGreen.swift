import AppKit
import Foundation

let path = CommandLine.arguments.dropFirst().first ?? "/tmp/checkmed-qa/sim-pinned.png"
guard let img = NSImage(contentsOfFile: path),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff)
else {
    fputs("cannot read \(path)\n", stderr)
    exit(1)
}
let w = rep.pixelsWide
let h = rep.pixelsHigh
var minX = w, maxX = 0, minY = h, maxY = 0, n = 0
for y in Int(Double(h) * 0.70)..<h {
    for x in stride(from: 0, to: w, by: 2) {
        guard let c = rep.colorAt(x: x, y: y) else { continue }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        if g > 0.55, g > r + 0.15, g > b + 0.15 {
            n += 1
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
print("px \(w)x\(h) n=\(n) bbox \(minX),\(minY)-\(maxX),\(maxY)")
if n > 0 {
    let cx = (minX + maxX) / 2
    let cy = (minY + maxY) / 2
    let scale = img.size.width / CGFloat(w)
    print("centerPx \(cx),\(cy)")
    print("centerPt \(Double(cx) * Double(scale)),\(Double(cy) * Double(scale))")
}
