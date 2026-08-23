import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

func generateShortcutIcon(for trigger: Trigger) -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)
    image.lockFocus()
    
    // 1. Clean squircle background (Apple standard macOS app / document icon squircle)
    let bgRect = NSRect(origin: .zero, size: size)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 110, yRadius: 110)
    NSColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0).set()
    bgPath.fill()
    
    // 2. Gather keycaps to draw
    var keys: [String] = []
    if trigger.requireControl { keys.append("⌃") }
    if trigger.requireOption  { keys.append("⌥") }
    if trigger.requireShift   { keys.append("⇧") }
    if trigger.requireCmd     { keys.append("⌘") }
    
    let keyName = KeyMap.name(for: trigger.keyCode)
    if keyName != "None" && !keyName.isEmpty {
        keys.append(keyName.uppercased())
    }
    
    if keys.isEmpty {
        keys.append("👑")
    }
    
    // 3. Draw keycaps horizontally centered
    let keycapWidth: CGFloat = keys.count > 3 ? 90 : 115
    let keycapHeight: CGFloat = keys.count > 3 ? 90 : 115
    let spacing: CGFloat = 16
    let totalWidth = CGFloat(keys.count) * keycapWidth + CGFloat(keys.count - 1) * spacing
    var startX = (size.width - totalWidth) / 2
    let y = (size.height - keycapHeight) / 2
    
    for key in keys {
        let rect = NSRect(x: startX, y: y, width: keycapWidth, height: keycapHeight)
        let path = NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22)
        
        // Keycap background
        NSColor(white: 0.22, alpha: 1.0).set()
        path.fill()
        
        // Keycap subtle border
        path.lineWidth = 2.5
        NSColor(white: 0.35, alpha: 1.0).set()
        path.stroke()
        
        // Keycap text with exact mathematical centering
        let fontSize: CGFloat = keycapWidth > 100 ? 52 : 40
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: style
        ]
        
        let attrString = NSAttributedString(string: key, attributes: attrs)
        let stringSize = attrString.size()
        let textRect = NSRect(
            x: rect.origin.x,
            y: rect.origin.y + (rect.height - stringSize.height) / 2,
            width: rect.width,
            height: stringSize.height
        )
        attrString.draw(in: textRect)
        
        startX += keycapWidth + spacing
    }
    
    image.unlockFocus()
    return image
}

// ==========================================
// MARK: - Folder Finder Icon Generator
// ==========================================
func nsColor(for colorName: String) -> NSColor {
    switch colorName.lowercased() {
    case "blue":   return NSColor(red: 0.25, green: 0.65, blue: 0.95, alpha: 1.0)
    case "purple": return NSColor(red: 0.68, green: 0.45, blue: 0.95, alpha: 1.0)
    case "orange": return NSColor(red: 0.98, green: 0.58, blue: 0.20, alpha: 1.0)
    case "green":  return NSColor(red: 0.30, green: 0.80, blue: 0.45, alpha: 1.0)
    case "pink":   return NSColor(red: 0.98, green: 0.45, blue: 0.65, alpha: 1.0)
    case "indigo": return NSColor(red: 0.42, green: 0.38, blue: 0.88, alpha: 1.0)
    case "red":    return NSColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1.0)
    case "yellow": return NSColor(red: 0.98, green: 0.80, blue: 0.20, alpha: 1.0)
    case "teal":   return NSColor(red: 0.20, green: 0.75, blue: 0.80, alpha: 1.0)
    case "gray":   return NSColor(white: 0.60, alpha: 1.0)
    default:       return NSColor(red: 0.25, green: 0.65, blue: 0.95, alpha: 1.0)
    }
}

func generateFinderFolderIcon(config: FolderConfig) -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let finalImage = NSImage(size: size)
    
    // 1. Get base macOS folder and guarantee solid 512x512 CGImage
    let baseFolder = NSImage(named: NSImage.folderName) ?? NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
    
    var folderCG: CGImage?
    let baseBitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 512,
        pixelsHigh: 512,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    if let rep = baseBitmap {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        baseFolder.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        folderCG = rep.cgImage
    }
    
    finalImage.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        finalImage.unlockFocus()
        return finalImage
    }
    
    let folderRect = NSRect(origin: .zero, size: size)
    
    if config.colorName.lowercased() == "blue" {
        baseFolder.draw(in: folderRect)
    } else if let folderCG = folderCG {
        // Tint folder using CoreImage Monochrome filter
        let ciImage = CIImage(cgImage: folderCG)
        let mono = CIFilter.colorMonochrome()
        mono.inputImage = ciImage
        mono.color = CIColor(color: nsColor(for: config.colorName)) ?? CIColor.red
        mono.intensity = 0.92
        
        let ciContext = CIContext()
        if let outCI = mono.outputImage, let tintedCG = ciContext.createCGImage(outCI, from: outCI.extent) {
            context.draw(tintedCG, in: folderRect)
        } else {
            baseFolder.draw(in: folderRect)
        }
    } else {
        baseFolder.draw(in: folderRect)
    }
    
    // 2. Draw embossed SF Symbol icon badge on the front of the folder
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: 130, weight: .semibold)
    if let symbolImage = NSImage(systemSymbolName: config.iconName, accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
        let symbolSize = symbolImage.size
        let flapCenterY: CGFloat = 205
        let flapCenterX: CGFloat = 256
        let symRect = NSRect(
            x: flapCenterX - symbolSize.width / 2,
            y: flapCenterY - symbolSize.height / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        
        // Tint symbol white
        if let tintedSym = symbolImage.copy() as? NSImage {
            tintedSym.lockFocus()
            NSColor.white.withAlphaComponent(0.95).set()
            NSRect(origin: .zero, size: tintedSym.size).fill(using: .sourceAtop)
            tintedSym.unlockFocus()
            tintedSym.draw(in: symRect)
        }
        
        context.restoreGState()
    }
    
    finalImage.unlockFocus()
    return finalImage
}

func updateFinderFolderIcon(for folderURL: URL, config: FolderConfig) {
    DispatchQueue.main.async {
        let iconImage = generateFinderFolderIcon(config: config)
        NSWorkspace.shared.setIcon(iconImage, forFile: folderURL.path, options: [])
        NSWorkspace.shared.noteFileSystemChanged(folderURL.path)
        
        // Tell macOS Finder to instantly refresh the folder item
        let script = "tell application \"Finder\" to update item (POSIX file \"\(folderURL.path)\" as alias)"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

func updateMacroFinderIcon(for fileURL: URL, trigger: Trigger) {
    DispatchQueue.main.async {
        let iconImage = generateShortcutIcon(for: trigger)
        NSWorkspace.shared.setIcon(iconImage, forFile: fileURL.path, options: [])
        NSWorkspace.shared.noteFileSystemChanged(fileURL.path)
    }
}

// ==========================================
// MARK: - File System Hierarchy Tree
// ==========================================

func generateAppIcon() -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)
    image.lockFocus()
    
    // 1. Clean squircle background (Apple standard macOS app / document icon squircle)
    let bgRect = NSRect(origin: .zero, size: size)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 110, yRadius: 110)
    NSColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0).set()
    bgPath.fill()
    
    // 2. Center keycap (larger than the ones in shortcut files to look like a main app icon)
    let keycapWidth: CGFloat = 240
    let keycapHeight: CGFloat = 240
    let x = (size.width - keycapWidth) / 2
    let y = (size.height - keycapHeight) / 2
    
    let rect = NSRect(x: x, y: y, width: keycapWidth, height: keycapHeight)
    let path = NSBezierPath(roundedRect: rect, xRadius: 46, yRadius: 46)
    
    // Keycap background
    NSColor(white: 0.22, alpha: 1.0).set()
    path.fill()
    
    // Keycap subtle border
    path.lineWidth = 5.0
    NSColor(white: 0.35, alpha: 1.0).set()
    path.stroke()
    
    // Crown emoji
    let fontSize: CGFloat = 110
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: style
    ]
    
    let attrString = NSAttributedString(string: "👑", attributes: attrs)
    let stringSize = attrString.size()
    let textRect = NSRect(
        x: rect.origin.x,
        y: rect.origin.y + (rect.height - stringSize.height) / 2,
        width: rect.width,
        height: stringSize.height
    )
    attrString.draw(in: textRect)
    
    image.unlockFocus()
    return image
}
