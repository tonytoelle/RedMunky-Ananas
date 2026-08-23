import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

class InputSimulator {
    @_silgen_name("DisplayServicesGetBrightness")
    static func DisplayServicesGetBrightness(_ displayID: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

    @_silgen_name("DisplayServicesSetBrightness")
    static func DisplayServicesSetBrightness(_ displayID: CGDirectDisplayID, _ brightness: Float) -> Int32

    static func adjustBrightness(delta: Float) {
        let mainDisplay = CGMainDisplayID()
        var current: Float = 0.0
        let statusGet = DisplayServicesGetBrightness(mainDisplay, &current)
        if statusGet == 0 {
            let newBrightness = max(0.0, min(1.0, current + delta))
            _ = DisplayServicesSetBrightness(mainDisplay, newBrightness)
        }
    }

    static let source = CGEventSource(stateID: .hidSystemState)
    static var isEmergencyStopped = false

    /// Clears any lingering modifier keys from physical hotkey presses
    static func releaseModifiers() {
        let modifierKeys: [CGKeyCode] = [54, 55, 56, 57, 58, 59, 60, 61, 62] // Cmd, Shift, Caps, Opt, Ctrl, Right variants
        for code in modifierKeys {
            if let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
                up.flags = []
                up.post(tap: .cghidEventTap)
            }
        }
    }

    static func postMediaKey(key: Int32) {
        // Press
        let eventDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xa << 8)),
            data2: 0
        )
        eventDown?.cgEvent?.post(tap: .cghidEventTap)
        
        // Release
        let eventUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xb << 8)),
            data2: 0
        )
        eventUp?.cgEvent?.post(tap: .cghidEventTap)
    }

    static func execute(items: [MacroActionItem], preRecordedOrigin: CGPoint? = nil, preRecordedWindowRect: CGRect? = nil) {
        isEmergencyStopped = false
        
        // Use pre-recorded origin if provided (captured on main thread before dispatch),
        // otherwise capture now as fallback.
        var originQuartzPos: CGPoint = preRecordedOrigin ?? {
            if let loc = CGEvent(source: nil)?.location, loc != .zero {
                return loc
            }
            let cocoaPt = NSEvent.mouseLocation
            let screenH = NSScreen.main?.frame.height ?? 1080
            return CGPoint(x: cocoaPt.x, y: screenH - cocoaPt.y)
        }()
        
        // Keep absolute start cursor position to restore it at the end of the macro
        let macroStartCursorPos = originQuartzPos
        
        var originWindowRect: CGRect? = preRecordedWindowRect ?? {
            return InputSimulator.getFrontmostWindowRect()
        }()
        
        // Show ghost cursor at origin position for the duration of execution
        ExecutionCursorOverlayWindow.show(at: originQuartzPos)
        
        // Warp real cursor off-screen to make it look invisible during execution
        CGWarpMouseCursorPosition(CGPoint(x: 99999, y: 99999))
        
        defer {
            // Restore real cursor back to its absolute original position before macro started
            CGWarpMouseCursorPosition(macroStartCursorPos)
            ExecutionCursorOverlayWindow.hide()
        }
        
        // Initial delay allowing user to release physical hotkey combination
        usleep(60000) // 60ms
        releaseModifiers()

        executeSubActions(items: items, originQuartzPos: &originQuartzPos, originWindowRect: &originWindowRect)
    }

    private static func executeSubActions(items: [MacroActionItem], originQuartzPos: inout CGPoint, originWindowRect: inout CGRect?) {
        for item in items {
            let repeats = max(1, item.repeatCount)
            for _ in 0..<repeats {
                guard !isEmergencyStopped else { return }
                switch item.action {
                case .group(_, let subActions):
                    executeSubActions(items: subActions, originQuartzPos: &originQuartzPos, originWindowRect: &originWindowRect)
                    
                case .click(let point, let button):
                    let dT: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
                    let uT: CGEventType = button == .left ? .leftMouseUp   : .rightMouseUp
                    let d = CGEvent(mouseEventSource: source, mouseType: dT, mouseCursorPosition: point, mouseButton: button)
                    let u = CGEvent(mouseEventSource: source, mouseType: uT, mouseCursorPosition: point, mouseButton: button)
                    d?.flags = []
                    u?.flags = []
                    d?.post(tap: .cghidEventTap)
                    usleep(25000)
                    u?.post(tap: .cghidEventTap)
                    usleep(30000)

                case .drag(let start, let end):
                    let d = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)
                    d?.flags = []
                    d?.post(tap: .cghidEventTap)
                    usleep(40000)
                    for i in 1...15 {
                        guard !isEmergencyStopped else { return }
                        let p = CGFloat(i)/15
                        let pt = CGPoint(x: start.x + (end.x-start.x)*p, y: start.y + (end.y-start.y)*p)
                        let m = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: pt, mouseButton: .left)
                        m?.flags = []
                        m?.post(tap: .cghidEventTap)
                        usleep(12000)
                    }
                    let u = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
                    u?.flags = []
                    u?.post(tap: .cghidEventTap)
                    usleep(30000)

                case .path(let points):
                    guard !points.isEmpty else { break }
                    var lastPt = points[0].point
                    CGWarpMouseCursorPosition(lastPt)
                    usleep(30000)
                    
                    var isMouseDown = false
                    
                    for i in 0..<points.count {
                        guard !isEmergencyStopped else { return }
                        let cur = points[i]
                        let reps = max(1, cur.repeatCount)
                        
                        for rIdx in 0..<reps {
                            guard !isEmergencyStopped else { return }
                            
                            switch cur.type {
                            case .move:
                                if isMouseDown {
                                    let u = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: lastPt, mouseButton: .left)
                                    u?.flags = []
                                    u?.post(tap: .cghidEventTap)
                                    usleep(20000)
                                    isMouseDown = false
                                }
                                CGWarpMouseCursorPosition(cur.point)
                                usleep(25000)
                                
                            case .click:
                                if isMouseDown {
                                    let u = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: lastPt, mouseButton: .left)
                                    u?.flags = []
                                    u?.post(tap: .cghidEventTap)
                                    usleep(20000)
                                    isMouseDown = false
                                }
                                CGWarpMouseCursorPosition(cur.point)
                                usleep(20000)
                                let d = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: cur.point, mouseButton: .left)
                                let u = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: cur.point, mouseButton: .left)
                                d?.flags = []
                                u?.flags = []
                                d?.post(tap: .cghidEventTap)
                                usleep(20000)
                                u?.post(tap: .cghidEventTap)
                                usleep(25000)
                                
                            case .drag:
                                if !isMouseDown {
                                    // Start dragging: move to this position, and press down mouse button
                                    CGWarpMouseCursorPosition(cur.point)
                                    usleep(20000)
                                    let d = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: cur.point, mouseButton: .left)
                                    d?.flags = []
                                    d?.post(tap: .cghidEventTap)
                                    usleep(30000)
                                    isMouseDown = true
                                } else {
                                    // Drag continuation: drag from lastPt to cur.point smoothly
                                    let start = lastPt
                                    let end = cur.point
                                    for s in 1...12 {
                                        guard !isEmergencyStopped else { return }
                                        let p = CGFloat(s)/12
                                        let pt = CGPoint(x: start.x + (end.x - start.x)*p, y: start.y + (end.y - start.y)*p)
                                        let m = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: pt, mouseButton: .left)
                                        m?.flags = []
                                        m?.post(tap: .cghidEventTap)
                                        usleep(12000)
                                    }
                                }
                            }
                            if reps > 1 && rIdx < reps - 1 {
                                usleep(30000) // Brief delay between internal point repetitions
                            }
                        }
                        lastPt = cur.point
                    }
                    
                    // Safety: Release mouse if it's still down at the end of the path
                    if isMouseDown {
                        let u = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: lastPt, mouseButton: .left)
                        u?.flags = []
                        u?.post(tap: .cghidEventTap)
                        usleep(25000)
                    }

                case .delay(let ms):
                    var rem = ms
                    while rem > 0 { guard !isEmergencyStopped else { return }; let c=min(rem,50); usleep(c*1000); rem -= c }

                case .typeText(let text):
                    releaseModifiers()
                    for character in text.utf16 {
                        guard !isEmergencyStopped else { return }
                        var ch = character
                        let d = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                        let u = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                        d?.flags = []
                        u?.flags = []
                        d?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
                        u?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
                        d?.post(tap: .cghidEventTap)
                        usleep(15000)
                        u?.post(tap: .cghidEventTap)
                        usleep(15000)
                    }

                case .pasteText(let text):
                    releaseModifiers()
                    let pasteboard = NSPasteboard.general
                    let oldText = pasteboard.string(forType: .string)
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)

                    usleep(20000)
                    let vKeyCode: CGKeyCode = 9
                    let d = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
                    let u = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
                    d?.flags = .maskCommand
                    u?.flags = .maskCommand
                    d?.post(tap: .cghidEventTap)
                    usleep(25000)
                    u?.post(tap: .cghidEventTap)
                    usleep(60000)

                    if let old = oldText {
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(old, forType: .string)
                        }
                    }

                case .pressKey(let keyCode):
                    guard !isEmergencyStopped else { return }
                    let d = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
                    let u = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
                    d?.flags = []
                    u?.flags = []
                    d?.post(tap: .cghidEventTap)
                    usleep(15000)
                    u?.post(tap: .cghidEventTap)
                    usleep(15000)

                case .pressShortcut(let trig):
                    guard !isEmergencyStopped else { return }
                    var flags = CGEventFlags()
                    if trig.requireCmd     { flags.insert(.maskCommand) }
                    if trig.requireShift   { flags.insert(.maskShift) }
                    if trig.requireOption  { flags.insert(.maskAlternate) }
                    if trig.requireControl { flags.insert(.maskControl) }
                    let d = CGEvent(keyboardEventSource: source, virtualKey: trig.keyCode, keyDown: true)
                    let u = CGEvent(keyboardEventSource: source, virtualKey: trig.keyCode, keyDown: false)
                    d?.flags = flags; u?.flags = flags
                    d?.post(tap: .cghidEventTap); usleep(20000)
                    u?.post(tap: .cghidEventTap); usleep(20000)

                case .doAgain(let target):
                    guard !isEmergencyStopped else { return }
                    if case .originWindow = target {
                        if let rect = originWindowRect {
                            InputSimulator.transformFrontmostWindow(origin: rect.origin, size: rect.size)
                            usleep(50000)
                        } else {
                            print("🪟 No original window rect captured")
                        }
                    } else {
                        var targetPos = originQuartzPos
                        switch target {
                        case .origin:
                            targetPos = originQuartzPos
                        case .originWindow:
                            break // Handled above
                        case .step(let idx):
                            let targetIdx = idx - 1
                            if targetIdx >= 0 && targetIdx < items.count {
                                let targetItem = items[targetIdx]
                                if case .click(let point, _) = targetItem.action {
                                    targetPos = point
                                } else if case .drag(let start, _) = targetItem.action {
                                    targetPos = start
                                } else if case .moveCursor(let point) = targetItem.action {
                                    targetPos = point
                                }
                            }
                        case .action(let tid):
                            if let targetItem = items.first(where: { $0.id == tid }) {
                                if case .click(let point, _) = targetItem.action {
                                    targetPos = point
                                } else if case .drag(let start, _) = targetItem.action {
                                    targetPos = start
                                } else if case .moveCursor(let point) = targetItem.action {
                                    targetPos = point
                                }
                            }
                        }
                        let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: targetPos, mouseButton: .left)
                        moveEvent?.flags = []
                        moveEvent?.post(tap: .cghidEventTap)
                        usleep(30000)
                    }

                case .moveCursor(let point):
                    guard !isEmergencyStopped else { return }
                    let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
                    moveEvent?.flags = []
                    moveEvent?.post(tap: .cghidEventTap)
                    usleep(30000)
                    
                case .openFile(let path):
                    guard !isEmergencyStopped else { return }
                    if !path.isEmpty {
                        let url = URL(fileURLWithPath: path)
                        NSWorkspace.shared.open(url)
                    }
                    usleep(150000)
                    
                case .customAction(let script):
                    guard !isEmergencyStopped else { return }
                    print("💻 Executing custom action: \(script)")
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    process.arguments = ["-c", script]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    do {
                        try process.run()
                        process.waitUntilExit()
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                            print("💻 Output/Error: \(output)")
                        }
                    } catch {
                        print("💻 Failed to run process: \(error)")
                    }
                    
                case .volumeUp:
                    guard !isEmergencyStopped else { return }
                    postMediaKey(key: 0) // NX_KEYTYPE_SOUND_UP
                    
                case .volumeDown:
                    guard !isEmergencyStopped else { return }
                    postMediaKey(key: 1) // NX_KEYTYPE_SOUND_DOWN
                    
                case .brightnessUp:
                    guard !isEmergencyStopped else { return }
                    InputSimulator.adjustBrightness(delta: 0.0625)
                    
                case .brightnessDown:
                    guard !isEmergencyStopped else { return }
                    InputSimulator.adjustBrightness(delta: -0.0625)
                    
                case .windowTransform(let p1, let p2, let p3, _):
                    guard !isEmergencyStopped else { return }
                    // p1 = top-left, p2 = top-right, p3 = bottom-right, p4 = bottom-left
                    let origin = CGPoint(x: p1.x, y: p1.y)
                    let size = CGSize(width: abs(p2.x - p1.x), height: abs(p3.y - p1.y))
                    InputSimulator.transformFrontmostWindow(origin: origin, size: size)
                    
                case .originAction(let type):
                    guard !isEmergencyStopped else { return }
                    if type == .cursor {
                        if let loc = CGEvent(source: nil)?.location, loc != .zero {
                            originQuartzPos = loc
                        } else {
                            let cp = NSEvent.mouseLocation
                            let sh = NSScreen.main?.frame.height ?? 1080
                            originQuartzPos = CGPoint(x: cp.x, y: sh - cp.y)
                        }
                        print("📍 Cursor origin recorded manually at \(originQuartzPos)")
                    } else if type == .window {
                        if let rect = InputSimulator.getFrontmostWindowRect() {
                            originWindowRect = rect
                            print("🪟 Window origin recorded manually at \(rect)")
                        }
                    }
                }
            }
        }
    }

    static func execute(actions: [MacroAction]) {
        let items = actions.map { MacroActionItem(action: $0) }
        execute(items: items)
    }
    
    // MARK: - Window Transform via Accessibility API
    
    static func transformFrontmostWindow(origin: CGPoint, size: CGSize) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            print("🪟 No frontmost app found")
            return
        }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        // Get the focused window
        var windowValue: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        
        if windowResult != .success {
            // Fallback: try to get the first window from windows list
            var windowsValue: AnyObject?
            let listResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
            guard listResult == .success, let windowsList = windowsValue as? [AXUIElement], let firstWindow = windowsList.first else {
                print("🪟 Could not get any window from app: \(frontApp.localizedName ?? "unknown")")
                return
            }
            windowValue = firstWindow
        }
        
        guard let window = windowValue else {
            print("🪟 Window value is nil")
            return
        }
        
        let windowElement = window as! AXUIElement
        
        // Set position
        var position = origin
        if let posValue = AXValueCreate(.cgPoint, &position) {
            let posResult = AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, posValue)
            if posResult != .success {
                print("🪟 Failed to set position: \(posResult.rawValue)")
            }
        }
        
        // Set size
        var windowSize = size
        if let sizeValue = AXValueCreate(.cgSize, &windowSize) {
            let sizeResult = AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
            if sizeResult != .success {
                print("🪟 Failed to set size: \(sizeResult.rawValue)")
            }
        }
        
        print("🪟 Window transformed to origin: \(origin), size: \(size)")
    }
    
    static func getFrontmostWindowRect() -> CGRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        var windowValue: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        
        let windowElement: AXUIElement
        if windowResult == .success, let win = windowValue {
            windowElement = win as! AXUIElement
        } else {
            var windowsValue: AnyObject?
            let listResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
            guard listResult == .success, let windowsList = windowsValue as? [AXUIElement], let firstWindow = windowsList.first else {
                return nil
            }
            windowElement = firstWindow
        }
        
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }
        
        var position: CGPoint = .zero
        var size: CGSize = .zero
        
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        return CGRect(origin: position, size: size)
    }
}

// ==========================================
// MARK: - Shortcut Icon Generator
// ==========================================
