import AppKit
import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let outputURL = rootURL
    .appendingPathComponent("AppResources", isDirectory: true)
    .appendingPathComponent("dmg-background.png")

let size = NSSize(width: 1200, height: 720)
let image = NSImage(size: size)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Missing graphics context")
}

let bounds = CGRect(origin: .zero, size: size)
let paper = NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.84, alpha: 1.0)
let ink = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.18, alpha: 1.0)
let spruce = NSColor(calibratedRed: 0.16, green: 0.29, blue: 0.27, alpha: 1.0)
let clay = NSColor(calibratedRed: 0.83, green: 0.44, blue: 0.27, alpha: 1.0)
let mist = NSColor(calibratedRed: 0.79, green: 0.86, blue: 0.80, alpha: 1.0)
let sand = NSColor(calibratedRed: 0.89, green: 0.77, blue: 0.58, alpha: 1.0)

paper.setFill()
context.fill(bounds)

context.setLineWidth(1)
for x in stride(from: CGFloat(28), through: size.width, by: CGFloat(40)) {
    context.setStrokeColor(ink.withAlphaComponent(0.035).cgColor)
    context.move(to: CGPoint(x: x, y: 0))
    context.addLine(to: CGPoint(x: x, y: size.height))
    context.strokePath()
}

for y in stride(from: CGFloat(24), through: size.height, by: CGFloat(40)) {
    context.setStrokeColor(ink.withAlphaComponent(0.03).cgColor)
    context.move(to: CGPoint(x: 0, y: y))
    context.addLine(to: CGPoint(x: size.width, y: y))
    context.strokePath()
}

let titlePanelRect = NSRect(x: 288, y: 560, width: 624, height: 98)
let titlePanel = NSBezierPath(roundedRect: titlePanelRect, xRadius: 34, yRadius: 34)
spruce.setFill()
titlePanel.fill()

let circle = NSBezierPath(ovalIn: NSRect(x: 1022, y: 536, width: 224, height: 224))
clay.setFill()
circle.fill()

let strip = NSBezierPath(roundedRect: NSRect(x: 0, y: 198, width: 1200, height: 154), xRadius: 0, yRadius: 0)
mist.withAlphaComponent(0.21).setFill()
strip.fill()

let leftDropZoneRect = NSRect(x: 166, y: 230, width: 244, height: 226)
let leftDropZone = NSBezierPath(roundedRect: leftDropZoneRect, xRadius: 34, yRadius: 34)
sand.withAlphaComponent(0.12).setFill()
leftDropZone.fill()
spruce.withAlphaComponent(0.11).setStroke()
leftDropZone.lineWidth = 2
leftDropZone.stroke()

let rightDropZoneRect = NSRect(x: 766, y: 230, width: 244, height: 226)
let rightDropZone = NSBezierPath(roundedRect: rightDropZoneRect, xRadius: 34, yRadius: 34)
NSColor.white.withAlphaComponent(0.24).setFill()
rightDropZone.fill()
spruce.withAlphaComponent(0.10).setStroke()
rightDropZone.lineWidth = 2
rightDropZone.stroke()

let leftMarker = NSBezierPath(roundedRect: NSRect(x: leftDropZoneRect.midX - 42, y: leftDropZoneRect.maxY + 18, width: 84, height: 26), xRadius: 13, yRadius: 13)
sand.withAlphaComponent(0.32).setFill()
leftMarker.fill()

let rightMarker = NSBezierPath(roundedRect: NSRect(x: rightDropZoneRect.midX - 86, y: rightDropZoneRect.maxY + 18, width: 172, height: 26), xRadius: 13, yRadius: 13)
NSColor.white.withAlphaComponent(0.20).setFill()
rightMarker.fill()

let rail = NSBezierPath()
rail.move(to: NSPoint(x: 448, y: 340))
rail.curve(to: NSPoint(x: 758, y: 340), controlPoint1: NSPoint(x: 546, y: 382), controlPoint2: NSPoint(x: 662, y: 382))
rail.lineWidth = 12
rail.lineCapStyle = .round
ink.withAlphaComponent(0.85).setStroke()
rail.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 728, y: 380))
arrowHead.line(to: NSPoint(x: 782, y: 340))
arrowHead.line(to: NSPoint(x: 728, y: 300))
arrowHead.lineWidth = 12
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.stroke()

let accentStroke = NSBezierPath()
accentStroke.move(to: NSPoint(x: titlePanelRect.maxX - 134, y: titlePanelRect.midY - 2))
accentStroke.line(to: NSPoint(x: titlePanelRect.maxX - 92, y: titlePanelRect.midY - 2))
accentStroke.line(to: NSPoint(x: titlePanelRect.maxX - 72, y: titlePanelRect.maxY - 18))
accentStroke.lineWidth = 14
accentStroke.lineCapStyle = .round
accentStroke.lineJoinStyle = .round
sand.setStroke()
accentStroke.stroke()

let helperAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
    .foregroundColor: ink.withAlphaComponent(0.82)
]

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 56, weight: .heavy),
    .foregroundColor: paper
]
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold),
    .foregroundColor: paper.withAlphaComponent(0.88)
]
let detailAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 23, weight: .medium),
    .foregroundColor: ink.withAlphaComponent(0.84)
]
let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .bold),
    .foregroundColor: ink.withAlphaComponent(0.70)
]

let titleSize = NSAttributedString(string: "MacClipper", attributes: titleAttrs).size()
NSAttributedString(string: "MacClipper", attributes: titleAttrs)
    .draw(at: NSPoint(x: titlePanelRect.midX - (titleSize.width / 2), y: 584))

let subtitleString = "MENU BAR CLIPPER FOR FAST SAVES"
let subtitleSize = NSAttributedString(string: subtitleString, attributes: subtitleAttrs).size()
NSAttributedString(string: subtitleString, attributes: subtitleAttrs)
    .draw(at: NSPoint(x: titlePanelRect.midX - (subtitleSize.width / 2), y: 566))

let helperString = "Drag MacClipper into Applications"
let helperSize = NSAttributedString(string: helperString, attributes: helperAttrs).size()
NSAttributedString(string: helperString, attributes: helperAttrs)
    .draw(at: NSPoint(x: titlePanelRect.midX - (helperSize.width / 2), y: 508))

NSAttributedString(string: "APP", attributes: labelAttrs)
    .draw(at: NSPoint(x: 267, y: 474))
NSAttributedString(string: "INSTALL", attributes: labelAttrs)
    .draw(at: NSPoint(x: 568, y: 390))
NSAttributedString(string: "APPLICATIONS", attributes: labelAttrs)
    .draw(at: NSPoint(x: 821, y: 474))

let footerBar = NSBezierPath(roundedRect: NSRect(x: 54, y: 52, width: 1092, height: 56), xRadius: 18, yRadius: 18)
spruce.withAlphaComponent(0.10).setFill()
footerBar.fill()

NSAttributedString(
    string: "macOS menu bar clipper  /  drag to install",
    attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: ink.withAlphaComponent(0.72)
    ]
).draw(at: NSPoint(x: 78, y: 70))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode background image")
}

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: outputURL)
print("Generated \(outputURL.path)")
