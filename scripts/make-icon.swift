import AppKit

// 1024×1024 uygulama ikonu: koyu zemin, kalkan içinde bant + dosya.
let size = 1024.0
// Tam 1024 px, alfasız (App Store ikon gereksinimi) CoreGraphics bağlamı.
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let bg = NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)
bg.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

// Kalkan
let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 900))
shield.curve(to: NSPoint(x: 860, y: 760), controlPoint1: NSPoint(x: 640, y: 860), controlPoint2: NSPoint(x: 760, y: 790))
shield.curve(to: NSPoint(x: 512, y: 120), controlPoint1: NSPoint(x: 860, y: 420), controlPoint2: NSPoint(x: 760, y: 220))
shield.curve(to: NSPoint(x: 164, y: 760), controlPoint1: NSPoint(x: 264, y: 220), controlPoint2: NSPoint(x: 164, y: 420))
shield.curve(to: NSPoint(x: 512, y: 900), controlPoint1: NSPoint(x: 264, y: 790), controlPoint2: NSPoint(x: 384, y: 860))
shield.close()
NSColor(red: 0.25, green: 0.78, blue: 0.98, alpha: 1).setFill(); shield.fill()

// Bant (yatay şerit) ve chevronlar
ctx.saveGState(); shield.addClip()
NSColor(red: 0.12, green: 0.14, blue: 0.20, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 420, width: size, height: 200)).fill()
NSColor(white: 1, alpha: 0.35).setStroke()
for i in 0..<3 {
    let p = NSBezierPath(); p.lineWidth = 26; p.lineCapStyle = .round; p.lineJoinStyle = .round
    let x = 330.0 + Double(i) * 150
    p.move(to: NSPoint(x: x, y: 470)); p.line(to: NSPoint(x: x + 60, y: 520)); p.line(to: NSPoint(x: x, y: 570))
    p.stroke()
}
ctx.restoreGState()

// Dosya
let doc = NSBezierPath(roundedRect: NSRect(x: 420, y: 395, width: 184, height: 250), xRadius: 22, yRadius: 22)
NSColor(red: 0.20, green: 0.65, blue: 0.40, alpha: 1).setFill(); doc.fill()
NSColor(white: 1, alpha: 0.9).setFill()
for i in 0..<3 { NSBezierPath(roundedRect: NSRect(x: 450, y: 560 - Double(i) * 48, width: 124 - Double(i) * 30, height: 18), xRadius: 9, yRadius: 9).fill() }
NSColor(red: 1.0, green: 0.30, blue: 0.32, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 548, y: 410, width: 44, height: 44)).fill()
NSColor.white.setStroke()
let slash = NSBezierPath(); slash.lineWidth = 8; slash.move(to: NSPoint(x: 556, y: 418)); slash.line(to: NSPoint(x: 584, y: 446)); slash.stroke()
NSGraphicsContext.restoreGraphicsState()
let cg = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, nil)
CGImageDestinationFinalize(dest)
print("icon written")
