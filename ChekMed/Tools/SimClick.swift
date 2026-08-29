import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]) else {
    fputs("usage: SimClick x y\n", stderr)
    exit(1)
}
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
let events: [CGEvent?] = [
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left),
]
for event in events {
    event?.post(tap: .cghidEventTap)
    usleep(40_000)
}
print("clicked \(Int(x)),\(Int(y))")
