import AppKit
import Foundation

enum IconError: Error {
    case pngEncodingFailed
    case iconUtilFailed(Int32)
}

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let resourcesURL = rootURL.appendingPathComponent("AppResources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("MacClipper.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try? fileManager.removeItem(at: iconsetURL)
try? fileManager.removeItem(at: icnsURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let canvas = NSRect(origin: .zero, size: image.size)
    let inset = size * 0.06
    let baseRect = canvas.insetBy(dx: inset, dy: inset)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: size * 0.22, yRadius: size * 0.22)

    let ink = NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.17, alpha: 1.0)
    let teal = NSColor(calibratedRed: 0.18, green: 0.43, blue: 0.38, alpha: 1.0)
    let clay = NSColor(calibratedRed: 0.86, green: 0.42, blue: 0.24, alpha: 1.0)
    let cream = NSColor(calibratedRed: 0.97, green: 0.93, blue: 0.87, alpha: 1.0)
    let sand = NSColor(calibratedRed: 0.90, green: 0.79, blue: 0.56, alpha: 1.0)

    ink.setFill()
    basePath.fill()

    NSColor.white.withAlphaComponent(0.07).setStroke()
    basePath.lineWidth = max(2, size * 0.012)
    basePath.stroke()

    NSGraphicsContext.saveGraphicsState()
    basePath.addClip()

    let topShape = NSBezierPath()
    topShape.move(to: NSPoint(x: baseRect.minX, y: baseRect.maxY))
    topShape.line(to: NSPoint(x: baseRect.minX + baseRect.width * 0.76, y: baseRect.maxY))
    topShape.line(to: NSPoint(x: baseRect.minX + baseRect.width * 0.46, y: baseRect.minY + baseRect.height * 0.45))
    topShape.line(to: NSPoint(x: baseRect.minX, y: baseRect.minY + baseRect.height * 0.62))
    topShape.close()
    teal.setFill()
    topShape.fill()

    let bottomShape = NSBezierPath()
    bottomShape.move(to: NSPoint(x: baseRect.minX + baseRect.width * 0.30, y: baseRect.minY))
    bottomShape.line(to: NSPoint(x: baseRect.maxX, y: baseRect.minY))
    bottomShape.line(to: NSPoint(x: baseRect.maxX, y: baseRect.minY + baseRect.height * 0.50))
    bottomShape.line(to: NSPoint(x: baseRect.minX + baseRect.width * 0.56, y: baseRect.minY + baseRect.height * 0.26))
    bottomShape.close()
    clay.setFill()
    bottomShape.fill()

    NSColor.white.withAlphaComponent(0.05).setFill()
    let washPath = NSBezierPath(ovalIn: NSRect(x: size * 0.12, y: size * 0.08, width: size * 0.76, height: size * 0.76))
    washPath.fill()

    let frameShadow = NSBezierPath()
    frameShadow.move(to: NSPoint(x: size * 0.31, y: size * 0.36))
    frameShadow.line(to: NSPoint(x: size * 0.31, y: size * 0.69))
    frameShadow.line(to: NSPoint(x: size * 0.61, y: size * 0.69))
    frameShadow.move(to: NSPoint(x: size * 0.41, y: size * 0.29))
    frameShadow.line(to: NSPoint(x: size * 0.71, y: size * 0.29))
    frameShadow.line(to: NSPoint(x: size * 0.71, y: size * 0.60))
    NSColor.black.withAlphaComponent(0.18).setStroke()
    frameShadow.lineWidth = size * 0.10
    frameShadow.lineCapStyle = .round
    frameShadow.lineJoinStyle = .round
    frameShadow.stroke()

    let framePath = NSBezierPath()
    framePath.move(to: NSPoint(x: size * 0.29, y: size * 0.38))
    framePath.line(to: NSPoint(x: size * 0.29, y: size * 0.70))
    framePath.line(to: NSPoint(x: size * 0.59, y: size * 0.70))
    framePath.move(to: NSPoint(x: size * 0.41, y: size * 0.30))
    framePath.line(to: NSPoint(x: size * 0.71, y: size * 0.30))
    framePath.line(to: NSPoint(x: size * 0.71, y: size * 0.60))
    cream.setStroke()
    framePath.lineWidth = size * 0.082
    framePath.lineCapStyle = .round
    framePath.lineJoinStyle = .round
    framePath.stroke()

    let bladeShadow = NSBezierPath()
    bladeShadow.move(to: NSPoint(x: size * 0.41, y: size * 0.23))
    bladeShadow.line(to: NSPoint(x: size * 0.54, y: size * 0.23))
    bladeShadow.line(to: NSPoint(x: size * 0.67, y: size * 0.57))
    bladeShadow.line(to: NSPoint(x: size * 0.54, y: size * 0.57))
    bladeShadow.close()
    NSColor.black.withAlphaComponent(0.18).setFill()
    bladeShadow.fill()

    let blade = NSBezierPath()
    blade.move(to: NSPoint(x: size * 0.39, y: size * 0.25))
    blade.line(to: NSPoint(x: size * 0.52, y: size * 0.25))
    blade.line(to: NSPoint(x: size * 0.65, y: size * 0.59))
    blade.line(to: NSPoint(x: size * 0.52, y: size * 0.59))
    blade.close()
    sand.setFill()
    blade.fill()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    blade.lineWidth = max(1.5, size * 0.01)
    blade.stroke()

    NSGraphicsContext.restoreGraphicsState()

    image.unlockFocus()
    return image
}

func writePNG(named name: String, size: CGFloat) throws {
    let image = makeIcon(size: size)
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let pngData = rep.representation(using: .png, properties: [:])
    else {
        throw IconError.pngEncodingFailed
    }

    try pngData.write(to: iconsetURL.appendingPathComponent(name))
}

let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconSizes {
    try writePNG(named: name, size: size)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw IconError.iconUtilFailed(process.terminationStatus)
}

print("Generated \(icnsURL.path)")
