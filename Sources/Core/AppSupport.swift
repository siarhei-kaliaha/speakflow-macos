import AppKit
import AVFoundation
import ApplicationServices
import Carbon
import Foundation

let widgetOuterSize = NSSize(width: 136, height: 40)
let widgetCapsuleSize = NSSize(width: 128, height: 32)

func makePulseImage(size: NSSize, color: NSColor, backgroundColor: NSColor? = nil, template: Bool = false) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    let bounds = NSRect(origin: .zero, size: size)

    if let backgroundColor {
        let outer = NSBezierPath(roundedRect: bounds, xRadius: size.height * 0.28, yRadius: size.height * 0.28)
        backgroundColor.setFill()
        outer.fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        outer.lineWidth = 1
        outer.stroke()
    }

    let centerY = size.height * 0.5
    let lineHeight = max(1.5, size.height * 0.04)
    let lineWidth = size.width * 0.42
    let lineRect = NSRect(x: size.width * 0.29, y: centerY - lineHeight / 2, width: lineWidth, height: lineHeight)
    let line = NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
    color.setFill()
    line.fill()

    let pulseHeights: [CGFloat] = [0.14, 0.26, 0.42, 0.64, 0.42, 0.26, 0.14].map { size.height * $0 }
    let pulseWidth = max(1.8, size.width * 0.028)
    let spacing = max(1.6, size.width * 0.018)
    let totalWidth = CGFloat(pulseHeights.count) * pulseWidth + CGFloat(pulseHeights.count - 1) * spacing
    let startX = size.width * 0.5 - totalWidth / 2
    for (index, height) in pulseHeights.enumerated() {
        let x = startX + CGFloat(index) * (pulseWidth + spacing)
        let rect = NSRect(x: x, y: centerY - height / 2, width: pulseWidth, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: pulseWidth / 2, yRadius: pulseWidth / 2)
        color.setFill()
        path.fill()
    }

    image.unlockFocus()
    image.isTemplate = template
    return image
}

func loadBundledAppIconImage() -> NSImage? {
    if let resourceURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let image = NSImage(contentsOf: resourceURL) {
        return image
    }
    return NSImage(named: "AppIcon")
}
