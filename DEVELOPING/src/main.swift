import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins

// ==========================================
// MARK: - KeyCode Mapping Helper
// ==========================================
struct KeyMap {
    static let keyNames: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "tab": 48, "space": 49, "`": 50, "delete": 51, "enter": 36, "return": 36, "esc": 53,
        "escape": 53, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]
    static func keyCode(for key: String) -> CGKeyCode? { keyNames[key.lowercased()] }
    static func name(for keyCode: CGKeyCode) -> String {
        keyNames.first(where: { $0.value == keyCode })?.key.uppercased() ?? "Key(\(keyCode))"
    }
}

// ==========================================
// MARK: - Models (with stable IDs for drag-drop)
// ==========================================
struct Trigger: Hashable, Equatable, Codable {
    var keyCode: CGKeyCode
    var requireCmd: Bool
    var requireShift: Bool
    var requireOption: Bool
    var requireControl: Bool

    var displayString: String {
        var p: [String] = []
        if requireControl { p.append("⌃Ctrl") }
        if requireOption  { p.append("⌥Opt") }
        if requireShift   { p.append("⇧Shift") }
        if requireCmd     { p.append("⌘Cmd") }
        p.append(KeyMap.name(for: keyCode))
        return p.joined(separator: " + ")
    }
    var scriptString: String {
        var p: [String] = []
        if requireCmd     { p.append("cmd") }
        if requireShift   { p.append("shift") }
        if requireOption  { p.append("opt") }
        if requireControl { p.append("ctrl") }
        p.append(KeyMap.name(for: keyCode).lowercased())
        return p.joined(separator: "+")
    }
}

// CRITICAL FIX: MacroAction now has a STABLE UUID stored as a constant
// This is essential for SwiftUI List drag-drop to work correctly
struct MacroActionItem: Identifiable, Equatable {
    let id: UUID   // stable — created once, never regenerated
    var action: MacroAction

    init(action: MacroAction) {
        self.id = UUID()
        self.action = action
    }

    init(id: UUID, action: MacroAction) {
        self.id = id
        self.action = action
    }
}

enum DoAgainTarget: Equatable {
    case origin
    case step(Int)
    case action(UUID)
    
    var isOrigin: Bool {
        if case .origin = self { return true }
        return false
    }
}

enum MacroAction: Equatable {
    case click(point: CGPoint, button: CGMouseButton)
    case drag(start: CGPoint, end: CGPoint)
    case delay(ms: UInt32)
    case typeText(text: String)
    case pasteText(text: String)
    case pressKey(keyCode: CGKeyCode)
    case pressShortcut(trigger: Trigger)
    case doAgain(target: DoAgainTarget)

    var iconName: String {
        switch self {
        case .click:        return "cursorarrow.click"
        case .drag:         return "hand.draw"
        case .delay:        return "timer"
        case .typeText:     return "text.cursor"
        case .pasteText:    return "doc.on.clipboard"
        case .pressKey, .pressShortcut: return "keyboard"
        case .doAgain:      return "arrow.counterclockwise"
        }
    }
    var color: Color {
        switch self {
        case .click(_, let button): return button == .left ? Color(red: 0.08, green: 0.45, blue: 0.82) : Color(red: 0.04, green: 0.52, blue: 0.54)
        case .drag:         return Color(red: 0.52, green: 0.22, blue: 0.75)
        case .delay:        return Color(red: 0.88, green: 0.42, blue: 0.04)
        case .typeText:     return Color(red: 0.12, green: 0.58, blue: 0.24)
        case .pasteText:    return Color(red: 0.04, green: 0.52, blue: 0.54)
        case .pressKey, .pressShortcut: return Color(red: 0.32, green: 0.28, blue: 0.72)
        case .doAgain:      return Color(red: 0.12, green: 0.58, blue: 0.65)
        }
    }
    var title: String {
        switch self {
        case .click(_, let b):      return "\(b == .left ? "Left" : "Right") Click"
        case .drag:                 return "Drag"
        case .delay:                return "Delay"
        case .typeText:             return "Type"
        case .pasteText:            return "Paste"
        case .pressKey, .pressShortcut: return "Key Press"
        case .doAgain:              return "Do Again"
        }
    }
    var details: String {
        switch self {
        case .click(let p, let b):  return "Click \(b == .left ? "Left Button" : "Right Button") at coordinates (\(Int(p.x)), \(Int(p.y)))"
        case .drag(let s, let e):   return "Drag cursor from (\(Int(s.x)), \(Int(s.y))) to (\(Int(e.x)), \(Int(e.y)))"
        case .delay(let ms):        return "Wait \(ms) milliseconds before next step"
        case .typeText(let t):      return "Type: \"\(t)\""
        case .pasteText(let t):     return "Paste: \"\(t)\""
        case .pressKey(let k):      return "Press key: \(KeyMap.name(for: k))"
        case .pressShortcut(let t): return "Hotkey combo: \(t.displayString)"
        case .doAgain(let target):
            switch target {
            case .origin:
                return "Move cursor back to position before macro started"
            case .step(let idx):
                return "Move cursor to coordinates of Action \(idx)"
            case .action:
                return "Move cursor to target action coordinates"
            }
        }
    }
    var parameterString: String {
        switch self {
        case .click(let point, _):
            return "\(Int(point.x)), \(Int(point.y))"
        case .drag(let start, let end):
            return "(\(Int(start.x)), \(Int(start.y))) → (\(Int(end.x)), \(Int(end.y)))"
        case .delay(let ms):
            return "\(ms) ms"
        case .typeText(let text), .pasteText(let text):
            return "\"\(text)\""
        case .pressKey(let keyCode):
            return KeyMap.name(for: keyCode)
        case .pressShortcut(let trigger):
            return trigger.displayString
        case .doAgain(let target):
            switch target {
            case .origin:
                return "Origin"
            case .step(let idx):
                return "Action \(idx)"
            case .action:
                return "Action"
            }
        }
    }
    var scriptLine: String {
        switch self {
        case .click(let p, let b):  return b == .left ? "ACTION: click \(Int(p.x)) \(Int(p.y))" : "ACTION: right_click \(Int(p.x)) \(Int(p.y))"
        case .drag(let s, let e):   return "ACTION: drag \(Int(s.x)) \(Int(s.y)) to \(Int(e.x)) \(Int(e.y))"
        case .delay(let ms):        return "ACTION: delay \(ms)"
        case .typeText(let t):      return "ACTION: type \"\(t)\""
        case .pasteText(let t):     return "ACTION: paste \"\(t)\""
        case .pressKey(let k):      return "ACTION: press \(KeyMap.name(for: k).lowercased())"
        case .pressShortcut(let t): return "ACTION: press_shortcut \(t.scriptString)"
        case .doAgain(let target):
            switch target {
            case .origin:
                return "ACTION: do_again"
            case .step(let idx):
                return "ACTION: do_again step_\(idx)"
            case .action:
                return "ACTION: do_again"
            }
        }
    }
    
    var hasCoordinates: Bool {
        switch self {
        case .click, .drag:
            return true
        default:
            return false
        }
    }
}

// ==========================================
// MARK: - Folder Configuration & App Targeting
// ==========================================
struct TargetApp: Codable, Identifiable, Equatable {
    var id: String { bundleId }
    let name: String
    let bundleId: String
}

struct FolderConfig: Codable, Equatable {
    var iconName: String = "folder.fill"
    var colorName: String = "blue"
    var isRestrictedToApps: Bool = false
    var targetApps: [TargetApp] = []
    
    var color: Color {
        switch colorName.lowercased() {
        case "blue":   return Color(red: 0.25, green: 0.65, blue: 0.95)
        case "purple": return Color(red: 0.68, green: 0.45, blue: 0.95)
        case "orange": return Color(red: 0.98, green: 0.58, blue: 0.20)
        case "green":  return Color(red: 0.30, green: 0.80, blue: 0.45)
        case "pink":   return Color(red: 0.98, green: 0.45, blue: 0.65)
        case "indigo": return Color(red: 0.42, green: 0.38, blue: 0.88)
        case "red":    return Color(red: 0.95, green: 0.30, blue: 0.30)
        case "yellow": return Color(red: 0.98, green: 0.80, blue: 0.20)
        case "teal":   return Color(red: 0.20, green: 0.75, blue: 0.80)
        case "gray":   return Color(white: 0.60)
        default:       return Color(red: 0.25, green: 0.65, blue: 0.95)
        }
    }
}

// MacroItem uses @Published for reactive updates
class MacroItem: Identifiable, ObservableObject {
    let id: UUID
    @Published var fileName: String
    @Published var fileURL: URL
    @Published var trigger: Trigger
    @Published var actionItems: [MacroActionItem]  // items have stable IDs for drag-drop
    var parentFolderConfig: FolderConfig?

    var actions: [MacroAction] { actionItems.map(\.action) }

    init(fileName: String, fileURL: URL, trigger: Trigger, actionItems: [MacroActionItem], parentFolderConfig: FolderConfig? = nil) {
        self.id = UUID()
        self.fileName = fileName
        self.fileURL = fileURL
        self.trigger = trigger
        self.actionItems = actionItems
        self.parentFolderConfig = parentFolderConfig
    }
}

// ==========================================
// MARK: - Carbon HotKey Manager
// ==========================================
private func carbonHotKeyCallback(
    nextHandler: EventHandlerCallRef?, theEvent: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let theEvent = theEvent else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let s = GetEventParameter(theEvent, EventParamName(kEventParamDirectObject),
                               EventParamType(typeEventHotKeyID), nil,
                               MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    if s == noErr {
        CarbonHotKeyManager.shared.dispatch(hotKeyID: hotKeyID.id)
        return noErr
    }
    return OSStatus(eventNotHandledErr)
}

class CarbonHotKeyManager {
    static let shared = CarbonHotKeyManager()

    private var registeredRefs: [UInt32: EventHotKeyRef] = [:]
    private var actionClosures: [UInt32: () -> Void] = [:]
    private var isHandlerInstalled = false
    private var currentID: UInt32 = 100
    private var emergencyRef: EventHotKeyRef?
    private let lock = NSLock()

    func installHandlerIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !isHandlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), carbonHotKeyCallback, 1, &eventType, nil, nil)
        isHandlerInstalled = true
        registerEmergencyKillSwitch()
    }

    func registerEmergencyKillSwitch() {
        let eID = EventHotKeyID(signature: OSType(0x4B494C4C), id: 9999)
        RegisterEventHotKey(7, UInt32(cmdKey | shiftKey | controlKey), eID, GetApplicationEventTarget(), 0, &emergencyRef)
        print("🛑 [Emergency] Cmd+Ctrl+Shift+X aktif")
    }

    func unregisterAll() {
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { self.unregisterAll() }
            return
        }
        lock.lock()
        let refs = Array(registeredRefs.values)
        registeredRefs.removeAll()
        actionClosures.removeAll()
        lock.unlock()
        
        refs.forEach { UnregisterEventHotKey($0) }
    }

    func register(trigger: Trigger, action: @escaping () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.register(trigger: trigger, action: action) }
            return
        }
        installHandlerIfNeeded()
        var mods: UInt32 = 0
        if trigger.requireCmd     { mods |= UInt32(cmdKey) }
        if trigger.requireShift   { mods |= UInt32(shiftKey) }
        if trigger.requireOption  { mods |= UInt32(optionKey) }
        if trigger.requireControl { mods |= UInt32(controlKey) }

        lock.lock()
        let id = currentID
        currentID += 1
        lock.unlock()

        let hkID = EventHotKeyID(signature: OSType(0x534B494E), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(trigger.keyCode), mods, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            lock.lock()
            registeredRefs[id] = ref
            actionClosures[id] = action
            lock.unlock()
            print("👑 HotKey registered: \(trigger.displayString) [ID:\(id)]")
        } else {
            print("⚠️ HotKey FAILED: \(trigger.displayString) OSStatus=\(status)")
        }
    }

    func dispatch(hotKeyID: UInt32) {
        if hotKeyID == 9999 {
            print("🚨 EMERGENCY KILL")
            InputSimulator.isEmergencyStopped = true
            NSSound.beep()
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }
        lock.lock()
        let closure = actionClosures[hotKeyID]
        lock.unlock()
        if let closure = closure {
            DispatchQueue.global(qos: .userInitiated).async { closure() }
        }
    }
}

// ==========================================
// MARK: - Parser & Serializer
// ==========================================
class ShortKingParser {
    static func parseTrigger(_ s: String) -> Trigger? {
        let parts = s.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var cmd = false, shift = false, opt = false, ctrl = false, key: String?
        for p in parts {
            switch p {
            case "cmd","command": cmd = true
            case "shift":         shift = true
            case "opt","option","alt": opt = true
            case "ctrl","control": ctrl = true
            default: key = p
            }
        }
        guard let k = key, let code = KeyMap.keyCode(for: k) else { return nil }
        return Trigger(keyCode: code, requireCmd: cmd, requireShift: shift, requireOption: opt, requireControl: ctrl)
    }

    static func parseFile(at url: URL) -> MacroItem? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var trigger: Trigger?
        var items: [MacroActionItem] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            if line.uppercased().hasPrefix("TRIGGER:") {
                trigger = parseTrigger(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces))
            } else if line.uppercased().hasPrefix("ACTION:") {
                if let a = parseAction(String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)) {
                    items.append(MacroActionItem(action: a))
                }
            }
        }
        
        // Resolve step references to action IDs
        for i in 0..<items.count {
            if case .doAgain(let target) = items[i].action, case .step(let idx) = target {
                let targetIdx = idx - 1
                if targetIdx >= 0 && targetIdx < items.count {
                    items[i].action = .doAgain(target: .action(items[targetIdx].id))
                } else {
                    items[i].action = .doAgain(target: .origin)
                }
            }
        }
        
        guard let t = trigger else { return nil }
        return MacroItem(fileName: url.lastPathComponent, fileURL: url, trigger: t, actionItems: items)
    }

    static func parseAction(_ s: String) -> MacroAction? {
        let parts = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let cmd = parts.first?.lowercased() else { return nil }
        switch cmd {
        case "click":
            if parts.count >= 3, let x = Double(parts[1]), let y = Double(parts[2]) {
                return .click(point: CGPoint(x: x, y: y), button: .left)
            }
        case "right_click":
            if parts.count >= 3, let x = Double(parts[1]), let y = Double(parts[2]) {
                return .click(point: CGPoint(x: x, y: y), button: .right)
            }
        case "delay","sleep":
            if parts.count >= 2, let ms = UInt32(parts[1]) { return .delay(ms: ms) }
        case "drag":
            let f = parts.filter { $0.lowercased() != "to" }
            if f.count >= 5, let x1=Double(f[1]),let y1=Double(f[2]),let x2=Double(f[3]),let y2=Double(f[4]) {
                return .drag(start: CGPoint(x: x1, y: y1), end: CGPoint(x: x2, y: y2))
            }
        case "type":
            var t = s.dropFirst(cmd.count).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 { t = String(t.dropFirst().dropLast()) }
            return .typeText(text: t)
        case "paste", "insert":
            var t = s.dropFirst(cmd.count).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 { t = String(t.dropFirst().dropLast()) }
            return .pasteText(text: t)
        case "press":
            if parts.count >= 2, let code = KeyMap.keyCode(for: parts[1]) { return .pressKey(keyCode: code) }
        case "press_shortcut":
            if parts.count >= 2, let trig = parseTrigger(parts[1]) { return .pressShortcut(trigger: trig) }
        case "restore_cursor", "restore_origin", "move_to_origin", "do_again":
            if parts.count >= 2, let last = parts.last, last.hasPrefix("step_") {
                let numStr = last.replacingOccurrences(of: "step_", with: "")
                if let idx = Int(numStr) {
                    return .doAgain(target: .step(idx))
                }
            }
            return .doAgain(target: .origin)
        default: break
        }
        return nil
    }

    static func generateScript(trigger: Trigger, actionItems: [MacroActionItem]) -> String {
        var lines = ["# ShortKing Macro Script", "TRIGGER: \(trigger.scriptString)", "", "# Actions:"]
        for item in actionItems {
            switch item.action {
            case .doAgain(let target):
                switch target {
                case .origin:
                    lines.append("ACTION: do_again")
                case .step(let idx):
                    lines.append("ACTION: do_again step_\(idx)")
                case .action(let tid):
                    if let idx = actionItems.firstIndex(where: { $0.id == tid }) {
                        lines.append("ACTION: do_again step_\(idx + 1)")
                    } else {
                        lines.append("ACTION: do_again")
                    }
                }
            default:
                lines.append(item.action.scriptLine)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func generateScript(trigger: Trigger, actions: [MacroAction]) -> String {
        let items = actions.map { MacroActionItem(action: $0) }
        return generateScript(trigger: trigger, actionItems: items)
    }
}

// ==========================================
// MARK: - Input Simulator (Robust & Timing-Correct)
// ==========================================
class InputSimulator {
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

    static func execute(items: [MacroActionItem]) {
        isEmergencyStopped = false
        
        // Initial delay allowing user to release physical hotkey combination
        usleep(60000) // 60ms
        releaseModifiers()

        // Record cursor origin position in Quartz screen coordinates
        let originQuartzPos = CGEvent(source: nil)?.location ?? .zero

        for item in items {
            guard !isEmergencyStopped else { return }
            switch item.action {
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
                    usleep(15000) // 15ms key down
                    u?.post(tap: .cghidEventTap)
                    usleep(15000) // 15ms key up before next char
                }

            case .pasteText(let text):
                releaseModifiers()
                let pasteboard = NSPasteboard.general
                let oldText = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)

                usleep(20000)
                // Cmd + V
                let vKeyCode: CGKeyCode = 9 // 'v'
                let d = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
                let u = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
                d?.flags = .maskCommand
                u?.flags = .maskCommand
                d?.post(tap: .cghidEventTap)
                usleep(25000)
                u?.post(tap: .cghidEventTap)
                usleep(60000)

                // Restore previous clipboard content
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
                var targetPos = originQuartzPos
                switch target {
                case .origin:
                    targetPos = originQuartzPos
                case .step(let idx):
                    let targetIdx = idx - 1
                    if targetIdx >= 0 && targetIdx < items.count {
                        let targetItem = items[targetIdx]
                        if case .click(let point, _) = targetItem.action {
                            targetPos = point
                        } else if case .drag(let start, _) = targetItem.action {
                            targetPos = start
                        }
                    }
                case .action(let tid):
                    if let targetItem = items.first(where: { $0.id == tid }) {
                        if case .click(let point, _) = targetItem.action {
                            targetPos = point
                        } else if case .drag(let start, _) = targetItem.action {
                            targetPos = start
                        }
                    }
                }
                let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: targetPos, mouseButton: .left)
                moveEvent?.flags = []
                moveEvent?.post(tap: .cghidEventTap)
                usleep(30000)
            }
        }
    }

    static func execute(actions: [MacroAction]) {
        let items = actions.map { MacroActionItem(action: $0) }
        execute(items: items)
    }
}

// ==========================================
// MARK: - Shortcut Icon Generator
// ==========================================
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
    let iconImage = generateFinderFolderIcon(config: config)
    DispatchQueue.main.async {
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
    let iconImage = generateShortcutIcon(for: trigger)
    DispatchQueue.main.async {
        NSWorkspace.shared.setIcon(iconImage, forFile: fileURL.path, options: [])
        NSWorkspace.shared.noteFileSystemChanged(fileURL.path)
    }
}

// ==========================================
// MARK: - File System Hierarchy Tree
// ==========================================
enum FileSystemNode: Identifiable {
    case folder(name: String, url: URL, config: FolderConfig, children: [FileSystemNode])
    case macro(item: MacroItem)

    var id: String {
        switch self {
        case .folder(_, let url, _, _): return "folder:" + url.path
        case .macro(let item): return "macro:" + item.fileURL.path
        }
    }

    var name: String {
        switch self {
        case .folder(let name, _, _, _): return name
        case .macro(let item): return item.fileName.replacingOccurrences(of: ".shortking", with: "")
        }
    }

    var isFolder: Bool {
        switch self {
        case .folder: return true
        case .macro: return false
        }
    }

    var folderURL: URL? {
        switch self {
        case .folder(_, let url, _, _): return url
        case .macro: return nil
        }
    }

    var folderConfig: FolderConfig? {
        switch self {
        case .folder(_, _, let config, _): return config
        case .macro: return nil
        }
    }
}

// ==========================================
// MARK: - Macro Store with Hierarchical Folder Tree
// ==========================================
class MacroStore: ObservableObject {
    static let shared = MacroStore()

    let undoManager = UndoManager()

    func registerUndoState(for macro: MacroItem) {
        let oldActions = macro.actionItems
        let oldTrigger = macro.trigger
        
        undoManager.registerUndo(withTarget: macro) { [weak self] target in
            guard let self = self else { return }
            self.registerUndoState(for: target)
            
            target.actionItems = oldActions
            target.trigger = oldTrigger
            self.saveMacro(target)
            self.objectWillChange.send()
        }
    }

    @Published var treeNodes: [FileSystemNode] = []
    @Published var macros: [MacroItem] = []
    @Published var selectedFilePath: String?
    @Published var selectedFolderPath: String?
    @Published var watchDirectoryURL: URL

    var selectedMacroID: UUID? {
        get { selectedMacro?.id }
        set {
            if let id = newValue {
                selectedFilePath = macros.first(where: { $0.id == id })?.fileURL.path
                selectedFolderPath = nil
            } else {
                selectedFilePath = nil
            }
        }
    }

    var selectedFileName: String? {
        get { selectedMacro?.fileName }
        set {
            if let name = newValue {
                selectedFilePath = macros.first(where: { $0.fileName == name })?.fileURL.path
                selectedFolderPath = nil
            }
        }
    }

    var selectedMacro: MacroItem? {
        get {
            guard let path = selectedFilePath else { return nil }
            return macros.first(where: { $0.fileURL.path == path })
        }
    }

    func loadFolderConfig(at folderURL: URL) -> FolderConfig {
        let configFile = folderURL.appendingPathComponent(".folder_config.json")
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(FolderConfig.self, from: data) else {
            return FolderConfig()
        }
        return config
    }

    func saveFolderConfig(_ config: FolderConfig, for folderURL: URL) {
        let configFile = folderURL.appendingPathComponent(".folder_config.json")
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configFile, options: .atomic)
        }
        
        self.treeNodes = updateTreeNodeConfig(nodes: self.treeNodes, folderURL: folderURL, newConfig: config)
        self.objectWillChange.send()
        
        updateFinderFolderIcon(for: folderURL, config: config)
        loadMacros()
    }

    private func updateTreeNodeConfig(nodes: [FileSystemNode], folderURL: URL, newConfig: FolderConfig) -> [FileSystemNode] {
        return nodes.map { node in
            switch node {
            case .folder(let name, let url, let config, let children):
                let isMatch = url.standardizedFileURL.path == folderURL.standardizedFileURL.path
                let updatedChildren = updateTreeNodeConfig(nodes: children, folderURL: folderURL, newConfig: newConfig)
                return .folder(name: name, url: url, config: isMatch ? newConfig : config, children: updatedChildren)
            case .macro(let item):
                if item.fileURL.deletingLastPathComponent().standardizedFileURL.path == folderURL.standardizedFileURL.path {
                    item.parentFolderConfig = newConfig
                }
                return .macro(item: item)
            }
        }
    }

    private var dirFD: CInt = -1
    private var watchSource: DispatchSourceFileSystemObject?

    init() {
        let defaultPath = "/Users/tonytoelle/Documents/PROJECTS/RedMunky - ShortKing/INPUT/ShortKing Documents"
        let savedPath = UserDefaults.standard.string(forKey: "watchDirectoryPath") ?? defaultPath
        self.watchDirectoryURL = URL(fileURLWithPath: savedPath)

        loadMacros()
        startWatching()
    }

    private func scanDirectory(at url: URL, loadedMacros: inout [MacroItem], parentConfig: FolderConfig? = nil) -> [FileSystemNode] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        
        var nodes: [FileSystemNode] = []
        let sorted = items.sorted {
            let isDir0 = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let isDir1 = (try? $1.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir0 != isDir1 {
                return isDir0 // Folders on top like Finder / Obsidian
            }
            return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        
        for item in sorted {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let config = loadFolderConfig(at: item)
                let children = scanDirectory(at: item, loadedMacros: &loadedMacros, parentConfig: config)
                nodes.append(.folder(name: item.lastPathComponent, url: item, config: config, children: children))
            } else if item.pathExtension.lowercased() == "shortking" {
                if let macro = ShortKingParser.parseFile(at: item) {
                    macro.parentFolderConfig = parentConfig
                    loadedMacros.append(macro)
                    nodes.append(.macro(item: macro))
                }
            }
        }
        return nodes
    }

    func loadMacros() {
        try? FileManager.default.createDirectory(at: watchDirectoryURL, withIntermediateDirectories: true)
        var loaded: [MacroItem] = []
        let tree = scanDirectory(at: watchDirectoryURL, loadedMacros: &loaded)
        
        DispatchQueue.main.async {
            self.treeNodes = tree
            self.macros = loaded
            if let current = self.selectedFilePath, loaded.contains(where: { $0.fileURL.path == current }) {
                // Keep current selection
            } else if let currentFolder = self.selectedFolderPath, FileManager.default.fileExists(atPath: currentFolder) {
                // Keep folder selection
            } else if let firstMacro = loaded.first {
                self.selectedFilePath = firstMacro.fileURL.path
                self.selectedFolderPath = nil
            } else {
                self.selectedFilePath = nil
            }
            self.registerAllCarbonHotKeys()
        }
    }

    func setWatchDirectory(_ url: URL) {
        stopWatching()
        self.watchDirectoryURL = url
        UserDefaults.standard.set(url.path, forKey: "watchDirectoryPath")
        loadMacros()
        startWatching()
    }

    func registerAllCarbonHotKeys() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.registerAllCarbonHotKeys() }
            return
        }
        CarbonHotKeyManager.shared.unregisterAll()
        for macro in macros {
            let items = macro.actionItems
            let folderConfig = macro.parentFolderConfig
            CarbonHotKeyManager.shared.register(trigger: macro.trigger) {
                // App targeting restriction check
                if let cfg = folderConfig, cfg.isRestrictedToApps && !cfg.targetApps.isEmpty {
                    if let frontApp = NSWorkspace.shared.frontmostApplication {
                        let activeBundle = frontApp.bundleIdentifier ?? ""
                        let activeName = frontApp.localizedName ?? ""
                        let matches = cfg.targetApps.contains { target in
                            target.bundleId == activeBundle || target.name.localizedCaseInsensitiveCompare(activeName) == .orderedSame
                        }
                        if !matches {
                            print("⏭️ Skipping macro '\(macro.fileName)' because frontmost app '\(activeName)' is not in folder target list.")
                            return
                        }
                    }
                }
                print("🚀 Executing: \(macro.fileName)")
                InputSimulator.execute(items: items)
            }
        }
    }

    func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
        if dirFD >= 0 {
            close(dirFD)
            dirFD = -1
        }
    }

    private var isReloading = false

    func startWatching() {
        stopWatching()
        dirFD = open(watchDirectoryURL.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self = self, !self.isReloading else { return }
            self.isReloading = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.loadMacros()
                self.isReloading = false
            }
        }
        watchSource = src
        src.resume()
    }

    func saveMacro(_ macro: MacroItem) {
        let content = ShortKingParser.generateScript(trigger: macro.trigger, actions: macro.actions)
        try? content.write(to: macro.fileURL, atomically: true, encoding: .utf8)
        registerAllCarbonHotKeys()
        
        // Update Finder custom icon based on shortcut trigger safely
        updateMacroFinderIcon(for: macro.fileURL, trigger: macro.trigger)
    }

    func renameMacro(_ macro: MacroItem, newBaseName: String) {
        let cleanName = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
                                   .replacingOccurrences(of: ".shortking", with: "")
        guard !cleanName.isEmpty else { return }
        
        let newFileName = cleanName + ".shortking"
        let oldURL = macro.fileURL
        let parentDir = oldURL.deletingLastPathComponent()
        let newURL = parentDir.appendingPathComponent(newFileName)
        
        guard oldURL.path != newURL.path else { return }
        
        do {
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } else {
                let content = ShortKingParser.generateScript(trigger: macro.trigger, actions: macro.actions)
                try content.write(to: newURL, atomically: true, encoding: .utf8)
            }
            macro.fileURL = newURL
            macro.fileName = newFileName
            self.selectedFilePath = newURL.path
            
            // Update Finder icon on new file safely
            updateMacroFinderIcon(for: newURL, trigger: macro.trigger)
            
            loadMacros()
        } catch {
            print("❌ Failed to rename file: \(error)")
        }
    }

    func createFolder(name: String, parentURL: URL? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let targetDir = parentURL ?? watchDirectoryURL
        let folderURL = targetDir.appendingPathComponent(clean)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        loadMacros()
    }

    func deleteFolder(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        loadMacros()
    }

    func renameFolder(at url: URL, newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let parent = url.deletingLastPathComponent()
        let dest = parent.appendingPathComponent(clean)
        guard dest != url else { return }
        try? FileManager.default.moveItem(at: url, to: dest)
        loadMacros()
    }

    func createNewMacro(inFolder parentURL: URL? = nil) {
        let targetDir = parentURL ?? watchDirectoryURL
        let count = macros.count + 1
        let fileName = "macro_\(count).shortking"
        let url = targetDir.appendingPathComponent(fileName)
        self.selectedFilePath = url.path
        let t = Trigger(keyCode: 40, requireCmd: true, requireShift: true, requireOption: false, requireControl: false)
        let a: [MacroAction] = [.delay(ms: 500), .typeText(text: "Hello ShortKing!")]
        try? ShortKingParser.generateScript(trigger: t, actions: a).write(to: url, atomically: true, encoding: .utf8)
        loadMacros()
    }

    func duplicateMacro(_ macro: MacroItem) {
        let baseName = macro.fileName.replacingOccurrences(of: ".shortking", with: "")
        let parentDir = macro.fileURL.deletingLastPathComponent()
        var newName = "\(baseName) copy"
        var newURL = parentDir.appendingPathComponent("\(newName).shortking")
        var copyIndex = 2
        while FileManager.default.fileExists(atPath: newURL.path) {
            newName = "\(baseName) copy \(copyIndex)"
            newURL = parentDir.appendingPathComponent("\(newName).shortking")
            copyIndex += 1
        }
        
        self.selectedFilePath = newURL.path
        
        saveMacro(macro)
        
        do {
            try FileManager.default.copyItem(at: macro.fileURL, to: newURL)
            loadMacros()
        } catch {
            print("❌ Failed to duplicate macro: \(error)")
        }
    }

    func deleteMacro(_ macro: MacroItem) {
        do {
            if FileManager.default.fileExists(atPath: macro.fileURL.path) {
                try FileManager.default.removeItem(at: macro.fileURL)
            }
            loadMacros()
        } catch {
            print("❌ Failed to delete macro: \(error)")
        }
    }

    func revealInFinder(_ macro: MacroItem) {
        NSWorkspace.shared.activateFileViewerSelecting([macro.fileURL])
    }

    func revealFolderInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func moveItems(paths: [String], toFolder targetFolderURL: URL) {
        for path in paths {
            let sourceURL = URL(fileURLWithPath: path)
            let fileName = sourceURL.lastPathComponent
            let destURL = targetFolderURL.appendingPathComponent(fileName)
            
            guard sourceURL.standardizedFileURL.path != destURL.standardizedFileURL.path else { continue }
            
            // Avoid moving a parent folder into its own subfolder
            if targetFolderURL.path.hasPrefix(sourceURL.path + "/") { continue }
            
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    let base = sourceURL.deletingPathExtension().lastPathComponent
                    let ext = sourceURL.pathExtension
                    var newName = "\(base) copy"
                    if !ext.isEmpty { newName += ".\(ext)" }
                    var uniqueDest = targetFolderURL.appendingPathComponent(newName)
                    var idx = 2
                    while FileManager.default.fileExists(atPath: uniqueDest.path) {
                        newName = "\(base) copy \(idx)"
                        if !ext.isEmpty { newName += ".\(ext)" }
                        uniqueDest = targetFolderURL.appendingPathComponent(newName)
                        idx += 1
                    }
                    try FileManager.default.moveItem(at: sourceURL, to: uniqueDest)
                } else {
                    try FileManager.default.moveItem(at: sourceURL, to: destURL)
                }
            } catch {
                print("❌ Failed to move item: \(error)")
            }
        }
        loadMacros()
    }

    func deleteItems(paths: [String]) {
        for path in paths {
            let url = URL(fileURLWithPath: path)
            try? FileManager.default.removeItem(at: url)
        }
        loadMacros()
    }

    func runMacro(_ macro: MacroItem) {
        let items = macro.actionItems
        DispatchQueue.global(qos: .userInitiated).async { InputSimulator.execute(items: items) }
    }
}

// ==========================================
// MARK: - Permission Manager (macOS Accessibility & Input Monitoring)
// ==========================================
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var isAccessibilityGranted: Bool = false
    @Published var isInputMonitoringGranted: Bool = false

    private var timer: Timer?

    init() {
        checkStatus()
        startPolling()
    }

    func checkStatus() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let axGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        let inputGranted: Bool
        if #available(macOS 10.15, *) {
            inputGranted = CGPreflightListenEventAccess()
        } else {
            inputGranted = true
        }

        DispatchQueue.main.async {
            self.isAccessibilityGranted = axGranted
            self.isInputMonitoringGranted = inputGranted
        }
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }

    func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        checkStatus()
    }

    func requestInputMonitoringPrompt() {
        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }
        checkStatus()
    }

    func requestAllPermissions() {
        requestAccessibilityPrompt()
        requestInputMonitoringPrompt()
        // Buka setting jika belum diberikan
        if !isAccessibilityGranted {
            openAccessibilitySettings()
        }
    }

    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// ==========================================
// MARK: - Shortcut Badge View
// ==========================================
struct ShortcutBadgeView: View {
    let trigger: Trigger
    var isDimmedMini: Bool = false

    var body: some View {
        HStack(spacing: isDimmedMini ? 2 : 4) {
            if trigger.requireControl {
                keycap(symbol: "⌃", text: "Ctrl")
            }
            if trigger.requireOption {
                keycap(symbol: "⌥", text: "Opt")
            }
            if trigger.requireShift {
                keycap(symbol: "⇧", text: "Shift")
            }
            if trigger.requireCmd {
                keycap(symbol: "⌘", text: "Cmd")
            }
            
            if trigger.requireControl || trigger.requireOption || trigger.requireShift || trigger.requireCmd {
                Text("+")
                    .foregroundColor(isDimmedMini ? Color(white: 0.35) : .secondary)
                    .font(.system(size: isDimmedMini ? 8 : 11, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
            }
            
            Text(KeyMap.name(for: trigger.keyCode))
                .font(.system(size: isDimmedMini ? 8 : 10, weight: .bold))
                .foregroundColor(isDimmedMini ? Color(white: 0.6) : .accentColor)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, isDimmedMini ? 4 : 6)
                .padding(.vertical, isDimmedMini ? 1.5 : 2.5)
                .background(isDimmedMini ? Color(white: 0.16) : Color(white: 0.22))
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isDimmedMini ? Color(white: 0.22) : Color(white: 0.3), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    func keycap(symbol: String, text: String) -> some View {
        HStack(spacing: isDimmedMini ? 1 : 2) {
            Text(symbol)
                .foregroundColor(isDimmedMini ? Color(white: 0.45) : Color.gray)
                .font(.system(size: isDimmedMini ? 8 : 11, weight: .bold))
                .lineLimit(1)
                .fixedSize()
            Text(text)
                .foregroundColor(isDimmedMini ? Color(white: 0.55) : .white)
                .font(.system(size: isDimmedMini ? 7 : 10, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, isDimmedMini ? 4 : 6)
        .padding(.vertical, isDimmedMini ? 1.5 : 2.5)
        .background(isDimmedMini ? Color(white: 0.16) : Color(white: 0.22))
        .cornerRadius(3)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isDimmedMini ? Color(white: 0.22) : Color(white: 0.3), lineWidth: 0.5)
        )
    }
}

// ==========================================
// MARK: - HotKey Recorder
// ==========================================
struct HotKeyRecorder: View {
    @Binding var trigger: Trigger
    var onChanged: () -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            HStack(spacing: 8) {
                if isRecording {
                    Image(systemName: "record.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 13))

                    Text("Press shortcut... (Esc to cancel)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                } else {
                    ShortcutBadgeView(trigger: trigger)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isRecording ? Color.red.opacity(0.12) : Color(white: 0.22))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isRecording ? Color.red : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let f = event.modifierFlags
            let kc = event.keyCode
            let isCmd = f.contains(.command), isShift = f.contains(.shift), isOpt = f.contains(.option), isCtrl = f.contains(.control)
            
            // Esc alone = cancel
            if kc == 53 && !isCmd && !isShift && !isOpt && !isCtrl {
                DispatchQueue.main.async { self.stopRecording() }
                return nil
            }
            let newTrigger = Trigger(keyCode: kc, requireCmd: isCmd, requireShift: isShift, requireOption: isOpt, requireControl: isCtrl)
            DispatchQueue.main.async {
                if let selected = MacroStore.shared.selectedMacro {
                    MacroStore.shared.registerUndoState(for: selected)
                }
                self.trigger = newTrigger
                self.stopRecording()
                self.onChanged()
            }
            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

// ==========================================
// MARK: - Interactive Coordinate Capture Overlay Window (Screenshot HUD Style)
// ==========================================
class CaptureOverlayState: ObservableObject {
    @Published var mode: CaptureOverlayWindow.Mode = .click(button: .left)
    @Published var currentLocation: CGPoint = .zero       // In Cocoa window coordinates (bottom-left origin)
    @Published var quartzLocation: CGPoint = .zero        // In Quartz display coordinates (top-left origin)
    @Published var dragStep: Int = 1                     // 1: Start point, 2: End point
    @Published var dragStartLocation: CGPoint? = nil      // Start in Cocoa window coordinates
    @Published var dragStartQuartz: CGPoint? = nil        // Start in Quartz coordinates
}

struct CaptureOverlaySwiftUIView: View {
    @ObservedObject var state: CaptureOverlayState
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Subtle dark transparent backdrop
                Color.black.opacity(0.05)
                    .edgesIgnoringSafeArea(.all)
                
                // Crosshair guide lines (hidden for Left Click and Drag)
                if shouldShowCrosshair {
                    Path { path in
                        // Horizontal hairline
                        path.move(to: CGPoint(x: 0, y: geo.size.height - state.currentLocation.y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - state.currentLocation.y))
                        // Vertical hairline
                        path.move(to: CGPoint(x: state.currentLocation.x, y: 0))
                        path.addLine(to: CGPoint(x: state.currentLocation.x, y: geo.size.height))
                    }
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                
                // If Drag Step 2: Draw connecting line and start point pin
                if case .drag = state.mode, state.dragStep == 2, let start = state.dragStartLocation {
                    let startCocoaY = geo.size.height - start.y
                    let currentCocoaY = geo.size.height - state.currentLocation.y
                    
                    Path { path in
                        path.move(to: CGPoint(x: start.x, y: startCocoaY))
                        path.addLine(to: CGPoint(x: state.currentLocation.x, y: currentCocoaY))
                    }
                    .stroke(Color.purple.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4]))
                    
                    // Pin marker at Start Point
                    ZStack {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                        Text("1")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .position(x: start.x, y: startCocoaY)
                }
                
                // Custom Crosshair Reticle Center
                let curCocoaY = geo.size.height - state.currentLocation.y
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    
                    Circle()
                        .fill(cursorAccentColor)
                        .frame(width: 6, height: 6)
                }
                .position(x: state.currentLocation.x, y: curCocoaY)
                
                // Floating Coordinates HUD Pill (Ekor kursor mirip macOS screenshot)
                cursorHUD
                    .position(hudPosition(in: geo.size))
            }
        }
    }
    
    private var cursorAccentColor: Color {
        switch state.mode {
        case .click(let b):
            return b == .left ? Color(red: 0.08, green: 0.45, blue: 0.82) : Color(red: 0.04, green: 0.52, blue: 0.54)
        case .drag:
            return Color.purple
        }
    }
    
    private func hudPosition(in size: CGSize) -> CGPoint {
        let curY = size.height - state.currentLocation.y
        var x = state.currentLocation.x + 95
        var y = curY - 38
        
        // Clamping to screen bounds so HUD is never cut off
        if x + 100 > size.width {
            x = state.currentLocation.x - 95
        }
        if y - 30 < 0 {
            y = curY + 45
        }
        return CGPoint(x: x, y: y)
    }
    
    private var cursorHUD: some View {
        HStack(spacing: 8) {
            // Mode Icon or Step Badge
            if case .drag = state.mode {
                ZStack {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 22, height: 22)
                    Text("\(state.dragStep)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            } else if case .click(let b) = state.mode {
                Image(systemName: b == .left ? "cursorarrow.click" : "cursorarrow.click")
                    .foregroundColor(b == .left ? Color(red: 0.35, green: 0.7, blue: 1.0) : Color.teal)
                    .font(.system(size: 14, weight: .semibold))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                // Coordinate Display
                HStack(spacing: 6) {
                    Text("X: \(Int(state.quartzLocation.x))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Y: \(Int(state.quartzLocation.y))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                // Instruction tip
                Text(tipText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(white: 0.75))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 6, x: 0, y: 3)
    }
    
    private var tipText: String {
        switch state.mode {
        case .click(let b):
            return "Click to set \(b == .left ? "left" : "right") click • Esc to cancel"
        case .drag:
            if state.dragStep == 1 {
                return "Click start point (1) • Esc to cancel"
            } else {
                return "Click or Enter end point (2) • Esc to cancel"
            }
        }
    }

    private var shouldShowCrosshair: Bool {
        switch state.mode {
        case .click(let b):
            return b != .left
        case .drag:
            return false
        }
    }
}

class CaptureOverlayHostingView: NSView {
    var mode: CaptureOverlayWindow.Mode
    var onFinishClick: (CGPoint) -> Void
    var onFinishDrag: (CGPoint, CGPoint) -> Void
    var onCancel: () -> Void
    
    private var trackingArea: NSTrackingArea?
    private var stateModel = CaptureOverlayState()
    
    init(mode: CaptureOverlayWindow.Mode,
         onFinishClick: @escaping (CGPoint) -> Void,
         onFinishDrag: @escaping (CGPoint, CGPoint) -> Void,
         onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onFinishClick = onFinishClick
        self.onFinishDrag = onFinishDrag
        self.onCancel = onCancel
        super.init(frame: .zero)
        
        stateModel.mode = mode
        let swiftUIView = CaptureOverlaySwiftUIView(state: stateModel)
        let host = NSHostingView(rootView: swiftUIView)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let ta = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }
    
    private func updateMouse(event: NSEvent) {
        let winLoc = event.locationInWindow
        let screenHeight = window?.screen?.frame.height ?? NSScreen.main?.frame.height ?? bounds.height
        let quartzPt = CGPoint(x: winLoc.x, y: screenHeight - winLoc.y)
        stateModel.currentLocation = winLoc
        stateModel.quartzLocation = quartzPt
    }
    
    override func mouseMoved(with event: NSEvent) {
        updateMouse(event: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateMouse(event: event)
    }
    
    override func mouseDown(with event: NSEvent) {
        updateMouse(event: event)
        switch mode {
        case .click:
            onFinishClick(stateModel.quartzLocation)
        case .drag:
            if stateModel.dragStep == 1 {
                stateModel.dragStartLocation = stateModel.currentLocation
                stateModel.dragStartQuartz = stateModel.quartzLocation
                stateModel.dragStep = 2
            } else {
                if let startQ = stateModel.dragStartQuartz {
                    onFinishDrag(startQ, stateModel.quartzLocation)
                }
            }
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        updateMouse(event: event)
        switch mode {
        case .click:
            onFinishClick(stateModel.quartzLocation)
        case .drag:
            if stateModel.dragStep == 1 {
                stateModel.dragStartLocation = stateModel.currentLocation
                stateModel.dragStartQuartz = stateModel.quartzLocation
                stateModel.dragStep = 2
            } else {
                if let startQ = stateModel.dragStartQuartz {
                    onFinishDrag(startQ, stateModel.quartzLocation)
                }
            }
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel()
        } else if event.keyCode == 36 { // Enter
            if case .drag = mode, stateModel.dragStep == 2, let startQ = stateModel.dragStartQuartz {
                onFinishDrag(startQ, stateModel.quartzLocation)
            }
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
}

class CaptureOverlayWindow: NSWindow {
    static var shared: CaptureOverlayWindow?
    
    enum Mode {
        case click(button: CGMouseButton = .left)
        case drag
    }
    
    private var mode: Mode
    private var onClickCaptured: ((CGPoint) -> Void)?
    private var onDragCaptured: ((CGPoint, CGPoint) -> Void)?
    
    init(mode: Mode = .click(button: .left), onClickCaptured: @escaping (CGPoint) -> Void) {
        self.mode = mode
        self.onClickCaptured = onClickCaptured
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(contentRect: screenRect,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        setupWindow()
    }
    
    init(mode: Mode = .drag, onDragCaptured: @escaping (CGPoint, CGPoint) -> Void) {
        self.mode = mode
        self.onDragCaptured = onDragCaptured
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(contentRect: screenRect,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        setupWindow()
    }
    
    private func setupWindow() {
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let overlayView = CaptureOverlayHostingView(
            mode: mode,
            onFinishClick: { [weak self] pt in
                self?.closeWindow()
                self?.onClickCaptured?(pt)
            },
            onFinishDrag: { [weak self] start, end in
                self?.closeWindow()
                self?.onDragCaptured?(start, end)
            },
            onCancel: { [weak self] in
                self?.closeWindow()
            }
        )
        
        self.contentView = overlayView
        NSCursor.hide()
        self.makeKeyAndOrderFront(nil)
    }
    
    func closeWindow() {
        NSCursor.unhide()
        self.orderOut(nil)
        CaptureOverlayWindow.shared = nil
    }
}

// ==========================================
// MARK: - Action Card View (macOS System Settings Card Style)
// ==========================================
struct ClickEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var xStr = ""
    @State private var yStr = ""
    @State private var buttonType: CGMouseButton = .left

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Button:").font(.system(size: 11)).foregroundColor(.secondary)
                Picker("", selection: $buttonType) {
                    Text("Left Click").tag(CGMouseButton.left)
                    Text("Right Click").tag(CGMouseButton.right)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                
                Spacer()
                
                Button("📍 Recapture") {
                    CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .click(button: buttonType)) { newPoint in
                        let xv = Int(newPoint.x)
                        let yv = Int(newPoint.y)
                        xStr = String(xv)
                        yStr = String(yv)
                        save()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("X:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $xStr)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
                HStack(spacing: 4) {
                    Text("Y:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $yStr)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
        }
        .onAppear {
            if case .click(let point, let button) = action {
                let xv = Int(point.x)
                let yv = Int(point.y)
                xStr = String(xv)
                yStr = String(yv)
                buttonType = button
            }
        }
        .onChange(of: xStr) { _, _ in save() }
        .onChange(of: yStr) { _, _ in save() }
        .onChange(of: buttonType) { _, _ in save() }
    }

    private func save() {
        let x = Double(xStr) ?? 0
        let y = Double(yStr) ?? 0
        action = .click(point: CGPoint(x: x, y: y), button: buttonType)
        onSave()
    }
}

struct DragEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var xStr = ""
    @State private var yStr = ""
    @State private var x2Str = ""
    @State private var y2Str = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Coordinates").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                Button("📍 Recapture") {
                    CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .drag) { ns, ne in
                        let xs = Int(ns.x)
                        let ys = Int(ns.y)
                        let xe = Int(ne.x)
                        let ye = Int(ne.y)
                        xStr = String(xs)
                        yStr = String(ys)
                        x2Str = String(xe)
                        y2Str = String(ye)
                        save()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Start X:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $xStr)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
                HStack(spacing: 4) {
                    Text("Y:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $yStr)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("End X:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $x2Str)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
                HStack(spacing: 4) {
                    Text("Y:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $y2Str)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
        }
        .onAppear {
            if case .drag(let start, let end) = action {
                let sx = Int(start.x)
                let sy = Int(start.y)
                let ex = Int(end.x)
                let ey = Int(end.y)
                xStr = String(sx)
                yStr = String(sy)
                x2Str = String(ex)
                y2Str = String(ey)
            }
        }
        .onChange(of: xStr) { _, _ in save() }
        .onChange(of: yStr) { _, _ in save() }
        .onChange(of: x2Str) { _, _ in save() }
        .onChange(of: y2Str) { _, _ in save() }
    }

    private func save() {
        let x1 = Double(xStr) ?? 0
        let y1 = Double(yStr) ?? 0
        let x2 = Double(x2Str) ?? 0
        let y2 = Double(y2Str) ?? 0
        action = .drag(start: CGPoint(x: x1, y: y1), end: CGPoint(x: x2, y: y2))
        onSave()
    }
}

struct DelayEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var delayStr = ""

    var body: some View {
        HStack(spacing: 10) {
            Text("Duration (ms):").font(.system(size: 11)).foregroundColor(.secondary)
            TextField("", text: $delayStr)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
        .onAppear {
            if case .delay(let ms) = action {
                let mv = Int(ms)
                delayStr = String(mv)
            }
        }
        .onChange(of: delayStr) { _, _ in save() }
    }

    private func save() {
        let ms = UInt32(delayStr) ?? 0
        action = .delay(ms: ms)
        onSave()
    }
}

struct TextEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var textStr = ""
    @State private var textMode = 0 // 0: type, 1: paste

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $textMode) {
                Text("⌨️ Type").tag(0)
                Text("📋 Paste").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            
            HStack(spacing: 10) {
                Text("Text:").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("", text: $textStr)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onAppear {
            if case .typeText(let text) = action {
                textStr = text
                textMode = 0
            } else if case .pasteText(let text) = action {
                textStr = text
                textMode = 1
            }
        }
        .onChange(of: textStr) { _, _ in save() }
        .onChange(of: textMode) { _, _ in save() }
    }

    private func save() {
        action = (textMode == 0) ? .typeText(text: textStr) : .pasteText(text: textStr)
        onSave()
    }
}

struct KeyEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var keyStr = ""

    var body: some View {
        HStack(spacing: 10) {
            Text("Key name:").font(.system(size: 11)).foregroundColor(.secondary)
            TextField("enter/space/a-z...", text: $keyStr)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
        }
        .onAppear {
            if case .pressKey(let keyCode) = action {
                keyStr = KeyMap.name(for: keyCode)
            }
        }
        .onChange(of: keyStr) { _, _ in save() }
    }

    private func save() {
        if let code = KeyMap.keyCode(for: keyStr) {
            action = .pressKey(keyCode: code)
            onSave()
        }
    }
}

// ==========================================
// MARK: - Inline Action Parameter Editors
// ==========================================
struct InlineTextEditView: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    
    @State private var textValue: String = ""
    
    var body: some View {
        TextField("Text", text: $textValue)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: 160)
            .multilineTextAlignment(.trailing)
            .onSubmit {
                save()
            }
            .onAppear {
                if case .typeText(let text) = action {
                    textValue = text
                } else if case .pasteText(let text) = action {
                    textValue = text
                }
            }
            .onChange(of: action) { _, newValue in
                if case .typeText(let text) = newValue {
                    textValue = text
                } else if case .pasteText(let text) = newValue {
                    textValue = text
                }
            }
    }
    
    private func save() {
        onPreSave()
        if case .typeText = action {
            action = .typeText(text: textValue)
        } else if case .pasteText = action {
            action = .pasteText(text: textValue)
        }
        onSave()
    }
}

struct InlineDelayEditView: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    
    @State private var msValue: String = ""
    
    var body: some View {
        HStack(spacing: 2) {
            TextField("ms", text: $msValue)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
                .onSubmit {
                    save()
                }
                .onAppear {
                    if case .delay(let ms) = action {
                        msValue = String(ms)
                    }
                }
                .onChange(of: action) { _, newValue in
                    if case .delay(let ms) = newValue {
                        msValue = String(ms)
                    }
                }
            Text("ms")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    private func save() {
        onPreSave()
        let ms = UInt32(msValue) ?? 0
        action = .delay(ms: ms)
        onSave()
    }
}

struct InlineKeyRecorder: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    
    @State private var isRecording = false
    @State private var monitor: Any?
    
    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            HStack(spacing: 8) {
                if isRecording {
                    Image(systemName: "record.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 13))
                    Text("Press key/shortcut... (Esc to cancel)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                } else {
                    switch action {
                    case .pressShortcut(let trig):
                        ShortcutBadgeView(trigger: trig, isDimmedMini: false)
                    case .pressKey(let k):
                        ShortcutBadgeView(trigger: Trigger(keyCode: k, requireCmd: false, requireShift: false, requireOption: false, requireControl: false), isDimmedMini: false)
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isRecording ? Color.red.opacity(0.12) : Color(white: 0.22))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isRecording ? Color.red : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let f = event.modifierFlags
            let kc = event.keyCode
            let isCmd = f.contains(.command), isShift = f.contains(.shift), isOpt = f.contains(.option), isCtrl = f.contains(.control)
            
            // Esc alone = cancel
            if kc == 53 && !isCmd && !isShift && !isOpt && !isCtrl {
                DispatchQueue.main.async { self.stopRecording() }
                return nil
            }
            
            let newAction: MacroAction
            if isCmd || isShift || isOpt || isCtrl {
                let trigger = Trigger(keyCode: kc, requireCmd: isCmd, requireShift: isShift, requireOption: isOpt, requireControl: isCtrl)
                newAction = .pressShortcut(trigger: trigger)
            } else {
                newAction = .pressKey(keyCode: kc)
            }
            
            DispatchQueue.main.async {
                self.onPreSave()
                self.action = newAction
                self.stopRecording()
                self.onSave()
            }
            return nil
        }
    }
    
    func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

struct InlineDoAgainPicker: View {
    @Binding var action: MacroAction
    var actionItems: [MacroActionItem]
    var currentIndex: Int
    var onPreSave: () -> Void
    var onSave: () -> Void
    
    var body: some View {
        if case .doAgain(let currentTarget) = action {
            Menu {
                Button(action: {
                    onPreSave()
                    action = .doAgain(target: .origin)
                    onSave()
                }) {
                    HStack {
                        Text("Origin (Start Position)")
                        if currentTarget == .origin {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(0..<actionItems.count, id: \.self) { idx in
                    let otherItem = actionItems[idx]
                    if idx != currentIndex, otherItem.action.hasCoordinates {
                        Button(action: {
                            onPreSave()
                            action = .doAgain(target: .action(otherItem.id))
                            onSave()
                        }) {
                            HStack {
                                Text("Action \(idx + 1): \(otherItem.action.title) (\(otherItem.action.parameterString))")
                                if case .action(let tid) = currentTarget, tid == otherItem.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(targetLabel(for: currentTarget))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.cyan)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.cyan)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.cyan.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
    
    private func targetLabel(for target: DoAgainTarget) -> String {
        switch target {
        case .origin:
            return "Origin"
        case .step(let idx):
            return "Action \(idx)"
        case .action(let tid):
            if let idx = actionItems.firstIndex(where: { $0.id == tid }) {
                return "Action \(idx + 1)"
            }
            return "Action"
        }
    }
}

struct ActionCardView: View {
    let index: Int
    @Binding var item: MacroActionItem
    var onDelete: () -> Void
    var onPreSave: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: 13))
                    .frame(width: 14)

                // Squircle Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.action.color)
                        .frame(width: 32, height: 32)
                    Image(systemName: item.action.iconName)
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .semibold))
                }

                // Title & Parameters
                HStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 2) {
                        Text(item.action.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        Text("\(index + 1)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 0.5)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                            .offset(y: -4) // superscript style
                    }
                    
                    Spacer()
                    
                    // Render appropriate parameter editor/display
                    switch item.action {
                    case .typeText, .pasteText:
                        InlineTextEditView(action: $item.action, onPreSave: onPreSave, onSave: onSave)
                    case .delay:
                        InlineDelayEditView(action: $item.action, onPreSave: onPreSave, onSave: onSave)
                    case .pressKey, .pressShortcut:
                        InlineKeyRecorder(action: $item.action, onPreSave: onPreSave, onSave: onSave)
                    case .doAgain:
                        if let selected = MacroStore.shared.selectedMacro {
                            InlineDoAgainPicker(action: $item.action, actionItems: selected.actionItems, currentIndex: index, onPreSave: onPreSave, onSave: onSave)
                        } else {
                            Text(item.action.parameterString)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                        }
                    default:
                        Text(item.action.parameterString)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 8)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    switch item.action {
                    case .click(_, let button):
                        CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .click(button: button)) { newPoint in
                            onPreSave()
                            item.action = .click(point: newPoint, button: button)
                            onSave()
                        }
                    case .drag:
                        CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .drag) { start, end in
                            onPreSave()
                            item.action = .drag(start: start, end: end)
                            onSave()
                        }
                    default:
                        break
                    }
                }

                Spacer()

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.secondary.opacity(0.5))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(white: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// ==========================================
// MARK: - Draggable Action List (macOS drag-reorder)
// ==========================================
struct DraggableActionList: View {
    @Binding var actionItems: [MacroActionItem]
    var onSave: () -> Void
    var onInsertTemplate: (String, Int) -> Void

    @State private var draggingID: UUID?
    @State private var draggingTemplate: String? = nil
    @State private var placeholderIndex: Int? = nil
    @State private var isListTargeted = false

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach($actionItems, id: \.id) { $item in
                if let index = actionItems.firstIndex(where: { $0.id == item.id }) {
                    Group {
                        if index == placeholderIndex, let templateName = draggingTemplate {
                            PlaceholderSlotView(title: templateName)
                        }
                        
                        ActionCardView(
                            index: index,
                            item: $item,
                            onDelete: {
                                if let selected = MacroStore.shared.selectedMacro {
                                    MacroStore.shared.registerUndoState(for: selected)
                                }
                                actionItems.removeAll { $0.id == item.id }
                                onSave()
                            },
                            onPreSave: {
                                if let selected = MacroStore.shared.selectedMacro {
                                    MacroStore.shared.registerUndoState(for: selected)
                                }
                            },
                            onSave: onSave
                        )
                        .onDrag {
                            draggingID = item.id
                            if let selected = MacroStore.shared.selectedMacro {
                                MacroStore.shared.registerUndoState(for: selected)
                            }
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: ActionDropDelegate(
                            item: item,
                            index: index,
                            items: $actionItems,
                            draggingID: $draggingID,
                            draggingTemplate: $draggingTemplate,
                            placeholderIndex: $placeholderIndex,
                            onSave: onSave,
                            onInsertTemplate: onInsertTemplate
                        ))
                        .opacity(draggingID == item.id ? 0.3 : 1.0)
                    }
                }
            }
            
            if placeholderIndex == actionItems.count, let templateName = draggingTemplate {
                PlaceholderSlotView(title: templateName)
            }
        }
        .onDrop(of: [.text], isTargeted: $isListTargeted) { providers in
            if draggingID != nil {
                draggingID = nil
                onSave()
                return true
            }
            if let provider = providers.first {
                _ = provider.loadObject(ofClass: NSString.self) { (str, error) in
                    if let s = str as? String, s.hasPrefix("action_template:") {
                        let typeName = s.replacingOccurrences(of: "action_template:", with: "")
                        DispatchQueue.main.async {
                            let targetIndex = placeholderIndex ?? actionItems.count
                            onInsertTemplate(typeName, targetIndex)
                            draggingTemplate = nil
                            placeholderIndex = nil
                        }
                    }
                }
                return true
            }
            draggingTemplate = nil
            placeholderIndex = nil
            return false
        }
        .onChange(of: isListTargeted) { _, targeted in
            if !targeted {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    draggingTemplate = nil
                    placeholderIndex = nil
                }
            }
        }
    }
}

struct PlaceholderSlotView: View {
    let title: String
    
    var body: some View {
        HStack {
            Image(systemName: "plus.circle")
                .foregroundColor(.accentColor)
                .font(.system(size: 14))
            
            Text("Insert \(title) Here")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.accentColor)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

struct ActionDropDelegate: DropDelegate {
    let item: MacroActionItem
    let index: Int
    @Binding var items: [MacroActionItem]
    @Binding var draggingID: UUID?
    @Binding var draggingTemplate: String?
    @Binding var placeholderIndex: Int?
    var onSave: () -> Void
    var onInsertTemplate: (String, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if draggingID != nil {
            draggingID = nil
            onSave()
            return true
        }
        
        if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { (str, error) in
                if let s = str as? String, s.hasPrefix("action_template:") {
                    let typeName = s.replacingOccurrences(of: "action_template:", with: "")
                    DispatchQueue.main.async {
                        let targetIndex = placeholderIndex ?? index
                        onInsertTemplate(typeName, targetIndex)
                        draggingTemplate = nil
                        placeholderIndex = nil
                    }
                }
            }
            return true
        }
        
        draggingTemplate = nil
        placeholderIndex = nil
        return false
    }

    func dropEntered(info: DropInfo) {
        if draggingID == nil {
            if let provider = info.itemProviders(for: [.text]).first {
                _ = provider.loadObject(ofClass: NSString.self) { (str, error) in
                    if let s = str as? String, s.hasPrefix("action_template:") {
                        let typeName = s.replacingOccurrences(of: "action_template:", with: "")
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                draggingTemplate = typeName
                                placeholderIndex = index
                            }
                        }
                    }
                }
            }
        } else if let dragID = draggingID {
            guard let fromIdx = items.firstIndex(where: { $0.id == dragID }),
                  fromIdx != index else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                items.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: index > fromIdx ? index + 1 : index)
            }
        }
    }
}

// ==========================================
// MARK: - Macro Inspector (Right Column - System Settings Canvas)
// ==========================================
struct MacroInspectorView: View {
    @ObservedObject var macro: MacroItem
    @ObservedObject var store = MacroStore.shared
    @ObservedObject var permissions = PermissionManager.shared

    @State private var isDirty = false
    @State private var tempName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Top Header Bar (Macro Title)
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    TextField("Macro Name", text: $tempName)
                        .font(.system(size: 15, weight: .bold))
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(minWidth: 80, maxWidth: 180)
                        .onSubmit {
                            store.renameMacro(macro, newBaseName: tempName)
                        }
                }
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                if !permissions.isAccessibilityGranted {
                    Button {
                        permissions.openAccessibilitySettings()
                    } label: {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 26, height: 22)
                            .background(Color.yellow.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Accessibility permission required to simulate keystrokes and mouse clicks")
                }

                if isDirty {
                    Button("Save") {
                        store.saveMacro(macro)
                        isDirty = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .fixedSize()
                }

                Button {
                    store.runMacro(macro)
                } label: {
                    Label("Test Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // Main Detail ScrollView
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Card 1: Trigger HotKey (Simplified, no redundant text)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Trigger")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)

                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(red: 0.45, green: 0.2, blue: 0.8))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "keyboard")
                                    .foregroundColor(.white)
                                    .font(.system(size: 15, weight: .semibold))
                            }

                            Text("Key Press")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            Spacer()

                            HotKeyRecorder(trigger: $macro.trigger) {
                                store.saveMacro(macro)
                                isDirty = false
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color(white: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }

                    // Downward connector arrow
                    HStack {
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(white: 0.32))
                        Spacer()
                    }
                    .padding(.vertical, 2)

                    // Section: Actions (No counter, clean design)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Actions")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.leading, 2)
                            Spacer()
                        }
                        .padding(.top, 4)

                        // Draggable Action Cards
                        DraggableActionList(actionItems: $macro.actionItems, onSave: {
                            store.saveMacro(macro)
                        }, onInsertTemplate: { typeName, targetIndex in
                            store.registerUndoState(for: macro)
                            let newAction: MacroAction
                            switch typeName {
                            case "Left Click":
                                newAction = .click(point: .zero, button: .left)
                            case "Right Click":
                                newAction = .click(point: .zero, button: .right)
                            case "Drag":
                                newAction = .drag(start: .zero, end: .zero)
                            case "Delay":
                                newAction = .delay(ms: 300)
                            case "Text":
                                newAction = .typeText(text: "Hello ShortKing")
                            case "Key":
                                newAction = .pressKey(keyCode: 36)
                            case "Origin", "Do Again":
                                newAction = .doAgain(target: .origin)
                            default:
                                newAction = .delay(ms: 300)
                            }
                            
                            let newItem = MacroActionItem(action: newAction)
                            if targetIndex >= macro.actionItems.count {
                                macro.actionItems.append(newItem)
                            } else {
                                macro.actionItems.insert(newItem, at: targetIndex)
                            }
                            store.saveMacro(macro)
                            
                            // Immediately trigger capture overlay for click/drag actions
                            switch newAction {
                            case .click(_, let button):
                                CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .click(button: button)) { newPoint in
                                    if let idx = macro.actionItems.firstIndex(where: { $0.id == newItem.id }) {
                                        store.registerUndoState(for: macro)
                                        macro.actionItems[idx].action = .click(point: newPoint, button: button)
                                        store.saveMacro(macro)
                                    }
                                }
                            case .drag:
                                CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .drag) { start, end in
                                    if let idx = macro.actionItems.firstIndex(where: { $0.id == newItem.id }) {
                                        store.registerUndoState(for: macro)
                                        macro.actionItems[idx].action = .drag(start: start, end: end)
                                        store.saveMacro(macro)
                                    }
                                }
                            default:
                                break
                            }
                        })

                        // Minimalist + separator
                        HStack {
                            Spacer()
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(white: 0.35))
                            Spacer()
                        }
                        .padding(.vertical, 2)

                        // Add Action Section (5 Quick Action Buttons with Instant Coordinate Overlay)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add Action")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.leading, 2)
                                .padding(.top, 6)

                            HStack(spacing: 8) {
                                // 1. Left Click (Instant Screen Coordinate Capture)
                                quickActionButton(
                                    title: "Left Click",
                                    icon: "cursorarrow.click",
                                    color: Color(red: 0.08, green: 0.45, blue: 0.82)
                                ) {
                                    CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .click(button: .left)) { pt in
                                        store.registerUndoState(for: macro)
                                        macro.actionItems.append(MacroActionItem(action: .click(point: pt, button: .left)))
                                        store.saveMacro(macro)
                                    }
                                }

                                // 2. Right Click (Instant Screen Coordinate Capture)
                                quickActionButton(
                                    title: "Right Click",
                                    icon: "cursorarrow.click",
                                    color: Color(red: 0.04, green: 0.52, blue: 0.54)
                                ) {
                                    CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .click(button: .right)) { pt in
                                        store.registerUndoState(for: macro)
                                        macro.actionItems.append(MacroActionItem(action: .click(point: pt, button: .right)))
                                        store.saveMacro(macro)
                                    }
                                }

                                // 3. Drag (Two-step Start -> End Coordinate Capture with Trail)
                                quickActionButton(
                                    title: "Drag",
                                    icon: "hand.draw",
                                    color: Color(red: 0.52, green: 0.22, blue: 0.75)
                                ) {
                                    CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .drag) { start, end in
                                        store.registerUndoState(for: macro)
                                        macro.actionItems.append(MacroActionItem(action: .drag(start: start, end: end)))
                                        store.saveMacro(macro)
                                    }
                                }

                                // 4. Delay
                                quickActionButton(
                                    title: "Delay",
                                    icon: "timer",
                                    color: Color(red: 0.88, green: 0.42, blue: 0.04)
                                ) {
                                    store.registerUndoState(for: macro)
                                    macro.actionItems.append(MacroActionItem(action: .delay(ms: 300)))
                                    store.saveMacro(macro)
                                }

                                // 5. Text
                                quickActionButton(
                                    title: "Text",
                                    icon: "text.cursor",
                                    color: Color(red: 0.12, green: 0.58, blue: 0.24)
                                ) {
                                    store.registerUndoState(for: macro)
                                    macro.actionItems.append(MacroActionItem(action: .typeText(text: "Hello ShortKing")))
                                    store.saveMacro(macro)
                                }

                                // 6. Key
                                quickActionButton(
                                    title: "Key",
                                    icon: "keyboard",
                                    color: Color(red: 0.32, green: 0.28, blue: 0.72)
                                ) {
                                    store.registerUndoState(for: macro)
                                    macro.actionItems.append(MacroActionItem(action: .pressKey(keyCode: 36)))
                                    store.saveMacro(macro)
                                }

                                // 7. Do Again (Restore original cursor position or target another action)
                                quickActionButton(
                                    title: "Do Again",
                                    icon: "arrow.counterclockwise",
                                    color: Color(red: 0.12, green: 0.58, blue: 0.65)
                                ) {
                                    store.registerUndoState(for: macro)
                                    macro.actionItems.append(MacroActionItem(action: .doAgain(target: .origin)))
                                    store.saveMacro(macro)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(22)
            }
        }
        .background(Color(white: 0.14))
        .onAppear {
            tempName = macro.fileName.replacingOccurrences(of: ".shortking", with: "")
        }
        .onChange(of: macro.id) { _, _ in
            tempName = macro.fileName.replacingOccurrences(of: ".shortking", with: "")
        }
        .onChange(of: macro.fileName) { _, newFileName in
            tempName = newFileName.replacingOccurrences(of: ".shortking", with: "")
        }
    }

    @ViewBuilder
    private func quickActionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color)
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .foregroundColor(.white)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
            .background(Color(white: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDrag {
            return NSItemProvider(object: "action_template:\(title)" as NSString)
        }
    }
}

// ==========================================
// MARK: - Permission Banner View
// ==========================================
struct PermissionBannerView: View {
    @ObservedObject var permissions = PermissionManager.shared

    var body: some View {
        if !permissions.isAccessibilityGranted {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Izin macOS Diperlukan (Accessibility Permission)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    Text("ShortKing membutuhkan izin Aksesibilitas agar dapat mensimulasikan klik mouse, drag, dan shortcut keyboard.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Minta Ulang Izin") {
                    permissions.requestAccessibilityPrompt()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Buka System Settings") {
                    permissions.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.12))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.yellow.opacity(0.3)), alignment: .bottom)
        }
    }
}

// ==========================================
// MARK: - Main 3-Column Editor View
// ==========================================
// ==========================================
// ==========================================
// MARK: - macOS System Settings 100% Authentic Replica
// ==========================================

enum SettingsCategory: String, CaseIterable, Identifiable {
    case network = "Network"
    case wifi = "Wi-Fi"
    case bluetooth = "Bluetooth"
    case battery = "Battery"
    case general = "General"
    case accessibility = "Accessibility"
    case appearance = "Appearance"
    case siri = "Apple Intelligence & Siri"
    case desktop = "Desktop & Dock"
    case displays = "Displays"
    case menubar = "Menu Bar"
    case spotlight = "Spotlight"
    case emergency = "Emergency Stop"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .network:       return "globe"
        case .wifi:          return "wifi"
        case .bluetooth:     return "dot.radiowaves.left.and.right"
        case .battery:       return "battery.100.bolt"
        case .general:       return "gearshape.fill"
        case .accessibility: return "figure.arms.open"
        case .appearance:    return "circle.lefthalf.filled"
        case .siri:          return "sparkles"
        case .desktop:       return "macwindow.dock.rectangle"
        case .displays:      return "sun.max.fill"
        case .menubar:       return "switch.2"
        case .spotlight:     return "magnifyingglass"
        case .emergency:     return "xmark.octagon.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .network:       return Color(red: 0.05, green: 0.5, blue: 0.95)
        case .wifi:          return Color.blue
        case .bluetooth:     return Color(red: 0.1, green: 0.65, blue: 0.95)
        case .battery:       return Color.green
        case .general:       return Color.gray
        case .accessibility: return Color(red: 0.1, green: 0.55, blue: 0.95)
        case .appearance:    return Color(white: 0.3)
        case .siri:          return Color(red: 0.95, green: 0.45, blue: 0.5)
        case .desktop:       return Color.gray
        case .displays:      return Color.blue
        case .menubar:       return Color.gray
        case .spotlight:     return Color.blue
        case .emergency:     return Color.red
        }
    }
}

// Drill-down Sub-Pages
enum SettingsSubpage: String, Identifiable {
    case wifiSubpage
    case firewallSubpage
    case thunderboltSubpage
    case macroStorageSubpage
    case accessibilitySubpage
    case emergencySubpage

    var id: String { rawValue }
}

struct SettingsView: View {
    @ObservedObject var store = MacroStore.shared
    @ObservedObject var permissions = PermissionManager.shared

    @State private var selectedCategory: SettingsCategory = .network
    @State private var searchText = ""
    @State private var navigationStack: [SettingsSubpage] = []

    @AppStorage("soundOnEmergency") private var soundOnEmergency: Bool = true
    @AppStorage("defaultTextMode") private var defaultTextMode: Int = 0
    @AppStorage("firewallEnabled") private var firewallEnabled: Bool = false
    @AppStorage("wifiEnabled") private var wifiEnabled: Bool = true

    var canGoBack: Bool { !navigationStack.isEmpty }

    var body: some View {
        HSplitView {
            // ═══════════════════════════════════════════════════
            // LEFT SIDEBAR (Exact macOS System Settings Layout)
            // ═══════════════════════════════════════════════════
            VStack(alignment: .leading, spacing: 0) {
                // Search Capsule Pill
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color(white: 0.20))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Categories ScrollView
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        // Connectivity Group
                        sidebarRow(category: .wifi)
                        sidebarRow(category: .bluetooth)
                        sidebarRow(category: .network)
                        sidebarRow(category: .battery)

                        Divider()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)

                        // System Group
                        sidebarRow(category: .general)
                        sidebarRow(category: .accessibility)
                        sidebarRow(category: .appearance)
                        sidebarRow(category: .siri)
                        sidebarRow(category: .desktop)
                        sidebarRow(category: .displays)
                        sidebarRow(category: .menubar)
                        sidebarRow(category: .spotlight)
                        sidebarRow(category: .emergency)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: 220)
            .background(Color(white: 0.12))

            // ═══════════════════════════════════════════════════
            // RIGHT DETAIL CANVAS (Cards, Navigation, Drilldown)
            // ═══════════════════════════════════════════════════
            VStack(spacing: 0) {
                // Header Bar (< > Navigation + Page Title)
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        Button {
                            if !navigationStack.isEmpty {
                                navigationStack.removeLast()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 24)
                                .foregroundColor(canGoBack ? .white : .secondary.opacity(0.3))
                        }
                        .disabled(!canGoBack)
                        .buttonStyle(.plain)

                        Divider().frame(height: 14)

                        Button { } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 24)
                                .foregroundColor(.secondary.opacity(0.3))
                        }
                        .disabled(true)
                        .buttonStyle(.plain)
                    }
                    .background(Color(white: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text(currentDetailTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 14)

                Divider()

                // Content View (Overview Cards or Sub-pages)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let subpage = navigationStack.last {
                            renderSubpage(subpage)
                        } else {
                            renderCategoryOverview()
                        }
                    }
                    .padding(22)
                }

                // Footer (••• ⌄ and ?)
                HStack {
                    Spacer()
                    Button { } label: {
                        HStack(spacing: 4) {
                            Text("•••")
                            Image(systemName: "chevron.down").font(.system(size: 8))
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color(white: 0.22))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        let learnURL = URL(fileURLWithPath: "/Users/tonytoelle/Documents/PROJECTS/RedMunky - ShortKing/LEARN")
                        NSWorkspace.shared.open(learnURL)
                    } label: {
                        Image(systemName: "questionmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Color(white: 0.22))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
            .frame(minWidth: 440)
            .background(Color(white: 0.14))
        }
        .frame(width: 680, height: 480)
    }

    private var currentDetailTitle: String {
        if let sub = navigationStack.last {
            switch sub {
            case .wifiSubpage:         return "Wi-Fi"
            case .firewallSubpage:     return "Firewall"
            case .thunderboltSubpage:  return "Thunderbolt Bridge"
            case .macroStorageSubpage: return "Macro Watch Directory"
            case .accessibilitySubpage: return "Accessibility Permissions"
            case .emergencySubpage:    return "Emergency Stop"
            }
        }
        return selectedCategory.rawValue
    }

    // Sidebar Row with macOS Highlight
    @ViewBuilder
    private func sidebarRow(category: SettingsCategory) -> some View {
        Button {
            selectedCategory = category
            navigationStack.removeAll()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(category.iconColor)
                        .frame(width: 24, height: 24)
                    Image(systemName: category.iconName)
                        .foregroundColor(.white)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(category.rawValue)
                    .font(.system(size: 13, weight: selectedCategory == category ? .medium : .regular))
                    .foregroundColor(selectedCategory == category ? .white : Color(white: 0.88))

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                selectedCategory == category
                    ? Color(red: 0.05, green: 0.45, blue: 0.95) // Vibrant Apple blue selection
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // Overview Cards for the Selected Category
    @ViewBuilder
    private func renderCategoryOverview() -> some View {
        switch selectedCategory {
        case .network, .wifi:
            // 100% Match to the uploaded screenshot!
            macOSCard(
                icon: "wifi",
                color: Color.blue,
                title: "Wi-Fi",
                statusDotColor: .green,
                statusText: "Connected"
            ) {
                navigationStack.append(.wifiSubpage)
            }

            macOSCard(
                icon: "arrow.left.arrow.right",
                color: Color.orange,
                title: "Firewall",
                statusDotColor: Color(white: 0.5),
                statusText: firewallEnabled ? "Active" : "Inactive"
            ) {
                navigationStack.append(.firewallSubpage)
            }

            Text("Other Services")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 10)
                .padding(.leading, 4)

            macOSCard(
                icon: "bolt.fill",
                color: Color.gray,
                title: "Thunderbolt Bridge",
                statusDotColor: Color(red: 1.0, green: 0.35, blue: 0.35),
                statusText: "Not connected"
            ) {
                navigationStack.append(.thunderboltSubpage)
            }

            // ShortKing Integration Card
            macOSCard(
                icon: "folder.fill",
                color: Color(red: 0.05, green: 0.5, blue: 0.95),
                title: "ShortKing Macro Watcher",
                statusDotColor: .green,
                statusText: "Active: \(store.watchDirectoryURL.lastPathComponent)"
            ) {
                navigationStack.append(.macroStorageSubpage)
            }

        case .accessibility:
            macOSCard(
                icon: "figure.arms.open",
                color: Color.blue,
                title: "Accessibility (Aksesibilitas)",
                statusDotColor: permissions.isAccessibilityGranted ? .green : .red,
                statusText: permissions.isAccessibilityGranted ? "Granted" : "Permission Required"
            ) {
                navigationStack.append(.accessibilitySubpage)
            }

        case .emergency:
            macOSCard(
                icon: "xmark.octagon.fill",
                color: Color.red,
                title: "Emergency Panic Switch",
                statusDotColor: .red,
                statusText: "⌘ + ⌃ + ⇧ + X"
            ) {
                navigationStack.append(.emergencySubpage)
            }

        default:
            macOSCard(
                icon: selectedCategory.iconName,
                color: selectedCategory.iconColor,
                title: selectedCategory.rawValue,
                statusDotColor: .green,
                statusText: "Operational"
            ) {
                navigationStack.append(.macroStorageSubpage)
            }
        }
    }

    // Reusable Rounded Rectangle Card matching macOS
    @ViewBuilder
    private func macOSCard(
        icon: String,
        color: Color,
        title: String,
        statusDotColor: Color?,
        statusText: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color)
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    if let text = statusText {
                        HStack(spacing: 5) {
                            if let dot = statusDotColor {
                                Circle()
                                    .fill(dot)
                                    .frame(width: 6, height: 6)
                            }
                            Text(text)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(white: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // Sub-pages (Drill-down views)
    @ViewBuilder
    private func renderSubpage(_ subpage: SettingsSubpage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            switch subpage {
            case .wifiSubpage:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wi-Fi Settings")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    VStack(spacing: 0) {
                        HStack {
                            Text("Wi-Fi Network")
                                .foregroundColor(.white)
                            Spacer()
                            Toggle("", isOn: $wifiEnabled)
                                .toggleStyle(.switch)
                        }
                        .padding(12)

                        Divider()

                        HStack {
                            Text("Connected SSID")
                                .foregroundColor(.white)
                            Spacer()
                            Text("Home-5G (Connected)")
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                    }
                    .background(Color(white: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

            case .firewallSubpage:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Firewall Configuration")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Firewall")
                                .foregroundColor(.white)
                            Text("Blocks unauthorized incoming network connections")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $firewallEnabled)
                            .toggleStyle(.switch)
                    }
                    .padding(14)
                    .background(Color(white: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

            case .macroStorageSubpage:
                VStack(alignment: .leading, spacing: 10) {
                    Text("ShortKing Macro Documents Directory")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.watchDirectoryURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.12))
                            .cornerRadius(6)

                        HStack {
                            Button("Choose Folder…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                panel.title = "Pilih Folder Makro ShortKing"
                                if panel.runModal() == .OK, let url = panel.url {
                                    store.setWatchDirectory(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Reveal in Finder") {
                                NSWorkspace.shared.open(store.watchDirectoryURL)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(Color(white: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

            case .accessibilitySubpage:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Accessibility Privileges")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Status:")
                                .foregroundColor(.white)
                            Spacer()
                            Text(permissions.isAccessibilityGranted ? "Granted ✅" : "Missing ❌")
                                .foregroundColor(permissions.isAccessibilityGranted ? .green : .red)
                        }

                        if !permissions.isAccessibilityGranted {
                            Button("Request Permission Prompt") {
                                permissions.requestAccessibilityPrompt()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button("Open macOS Privacy & Security Settings") {
                            permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(Color(white: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

            case .emergencySubpage:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Panic Emergency Stop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Shortcut:")
                                .foregroundColor(.white)
                            Spacer()
                            Text("⌘ + ⌃ + ⇧ + X")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                        }

                        HStack {
                            Text("Sound alert on trigger")
                                .foregroundColor(.white)
                            Spacer()
                            Toggle("", isOn: $soundOnEmergency)
                                .toggleStyle(.switch)
                        }
                    }
                    .padding(14)
                    .background(Color(white: 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

            case .thunderboltSubpage:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Thunderbolt Bridge")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text("No active Thunderbolt hardware bridges connected.")
                        .foregroundColor(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

// ==========================================
// MARK: - Folder Inspector View (Simple, Clean Layout)
// ==========================================
struct FolderInspectorView: View {
    let folderURL: URL
    let initialConfig: FolderConfig
    let itemCount: Int
    @ObservedObject var store = MacroStore.shared

    @State private var folderName: String = ""
    @State private var config: FolderConfig = FolderConfig()
    @State private var isShowingRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var isAppearanceExpanded: Bool = true

    let availableColors: [(name: String, label: String, color: Color)] = [
        ("blue", "Blue", Color(red: 0.25, green: 0.65, blue: 0.95)),
        ("purple", "Purple", Color(red: 0.68, green: 0.45, blue: 0.95)),
        ("orange", "Orange", Color(red: 0.98, green: 0.58, blue: 0.20)),
        ("green", "Green", Color(red: 0.30, green: 0.80, blue: 0.45)),
        ("pink", "Pink", Color(red: 0.98, green: 0.45, blue: 0.65)),
        ("indigo", "Indigo", Color(red: 0.42, green: 0.38, blue: 0.88)),
        ("red", "Red", Color(red: 0.95, green: 0.30, blue: 0.30)),
        ("yellow", "Yellow", Color(red: 0.98, green: 0.80, blue: 0.20)),
        ("teal", "Teal", Color(red: 0.20, green: 0.75, blue: 0.80)),
        ("gray", "Gray", Color(white: 0.60))
    ]

    let availableIcons: [String] = [
        "folder.fill", "folder.badge.gearshape", "star.fill", "bookmark.fill", "tag.fill",
        "film.fill", "video.fill", "waveform", "music.note", "camera.fill", "photo.fill",
        "chevron.left.forwardslash.chevron.right", "terminal.fill", "cpu.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "paintpalette.fill", "paintbrush.fill", "wand.and.stars", "pencil.and.ruler.fill", "crop",
        "briefcase.fill", "doc.text.fill", "chart.bar.fill", "envelope.fill", "calendar",
        "gamecontroller.fill", "bolt.fill", "keyboard.fill", "slider.horizontal.3", "flame.fill"
    ]

    var runningApps: [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            $0.bundleIdentifier != nil &&
            $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
            $0.localizedName != nil
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ═══════════════════════════════════════════════════
                // CENTERED HEADER
                // ═══════════════════════════════════════════════════
                VStack(spacing: 10) {
                    // Big Squircle Icon
                    Button {
                        withAnimation { isAppearanceExpanded.toggle() }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(config.color.opacity(0.18))
                                .frame(width: 88, height: 88)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(config.color.opacity(0.35), lineWidth: 1.5)
                                )
                            Image(systemName: config.iconName)
                                .font(.system(size: 38, weight: .medium))
                                .foregroundColor(config.color)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Click to change appearance")

                    // Folder Name
                    Text(folderName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    // Macro Count
                    Text("\(itemCount) Macros")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.70))

                    // Rename / Edit link
                    Button {
                        renameText = folderName
                        isShowingRenameAlert = true
                    } label: {
                        Text("Edit Name")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(white: 0.50))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)

                // ═══════════════════════════════════════════════════
                // TARGET APPLICATIONS CARD
                // ═══════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "macwindow.on.rectangle")
                            .foregroundColor(Color(red: 0.30, green: 0.65, blue: 0.95))
                            .font(.system(size: 14, weight: .semibold))
                        Text("Target Applications")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: $config.isRestrictedToApps)
                            .toggleStyle(.switch)
                            .onChange(of: config.isRestrictedToApps) {
                                saveConfig()
                            }
                    }

                    Text("When enabled, shortcuts inside this folder will only run when one of the specified applications is active and focused.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(white: 0.55))
                        .fixedSize(horizontal: false, vertical: true)

                    if config.isRestrictedToApps {
                        // Applications List
                        if !config.targetApps.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(config.targetApps) { target in
                                    HStack(spacing: 12) {
                                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleId) {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                                .resizable()
                                                .frame(width: 22, height: 22)
                                        } else {
                                            Image(systemName: "app.fill")
                                                .foregroundColor(.accentColor)
                                                .frame(width: 22, height: 22)
                                        }

                                        Text(target.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)

                                        Spacer()

                                        Button {
                                            config.targetApps.removeAll { $0.bundleId == target.bundleId }
                                            saveConfig()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(Color(white: 0.45))
                                                .font(.system(size: 15))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove application")
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color(white: 0.20))
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                            }
                        }

                        // Minimalist "+ Add" Button
                        Menu {
                            Section("Running Applications") {
                                ForEach(runningApps, id: \.processIdentifier) { app in
                                    if let bId = app.bundleIdentifier, let name = app.localizedName {
                                        Button {
                                            if !config.targetApps.contains(where: { $0.bundleId == bId }) {
                                                config.targetApps.append(TargetApp(name: name, bundleId: bId))
                                                saveConfig()
                                            }
                                        } label: {
                                            if let icon = app.icon {
                                                Image(nsImage: icon)
                                            }
                                            Text(name)
                                        }
                                    }
                                }
                            }

                            Divider()

                            Button {
                                pickAppFromDisk()
                            } label: {
                                Label("Browse /Applications…", systemImage: "folder")
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 13))
                                Text("Add")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(Color(white: 0.80))
                        }
                        .menuStyle(.borderlessButton)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(Color(white: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // ═══════════════════════════════════════════════════
                // FOLDER APPEARANCE CARD
                // ═══════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAppearanceExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "paintpalette.fill")
                                .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.65))
                                .font(.system(size: 14, weight: .semibold))
                            Text("Folder Appearance")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: isAppearanceExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(white: 0.50))
                        }
                    }
                    .buttonStyle(.plain)

                    if isAppearanceExpanded {
                        // Color Palette
                        VStack(alignment: .leading, spacing: 8) {
                            Text("COLOR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(white: 0.5))

                            HStack(spacing: 10) {
                                ForEach(availableColors, id: \.name) { item in
                                    Button {
                                        config.colorName = item.name
                                        saveConfig()
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(item.color)
                                                .frame(width: 26, height: 26)
                                            if config.colorName.lowercased() == item.name.lowercased() {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 4)

                        Divider().background(Color(white: 0.25))

                        // Icon Grid
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ICON")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(white: 0.5))

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                                ForEach(availableIcons, id: \.self) { icon in
                                    let isSelected = config.iconName == icon
                                    Button {
                                        config.iconName = icon
                                        saveConfig()
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(isSelected ? config.color.opacity(0.3) : Color(white: 0.22))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .stroke(isSelected ? config.color : Color.clear, lineWidth: 1.5)
                                                )
                                                .frame(height: 38)
                                            Image(systemName: icon)
                                                .font(.system(size: 16))
                                                .foregroundColor(isSelected ? config.color : Color(white: 0.85))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(white: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(24)
        }
        .background(Color(white: 0.14))
        .onAppear {
            folderName = folderURL.lastPathComponent
            config = initialConfig
        }
        .onChange(of: folderURL) { _, newURL in
            folderName = newURL.lastPathComponent
            config = store.loadFolderConfig(at: newURL)
        }
        .alert("Rename Folder", isPresented: $isShowingRenameAlert) {
            TextField("Folder Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if !renameText.isEmpty && renameText != folderName {
                    store.renameFolder(at: folderURL, newName: renameText)
                    folderName = renameText
                }
            }
        }
    }

    private func saveConfig() {
        store.saveFolderConfig(config, for: folderURL)
    }

    private func pickAppFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        if panel.runModal() == .OK, let url = panel.url {
            let bundle = Bundle(url: url)
            let bundleId = bundle?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
            let name = bundle?.infoDictionary?["CFBundleName"] as? String ??
                       bundle?.infoDictionary?["CFBundleDisplayName"] as? String ??
                       url.deletingPathExtension().lastPathComponent
            
            if !config.targetApps.contains(where: { $0.bundleId == bundleId }) {
                config.targetApps.append(TargetApp(name: name, bundleId: bundleId))
                saveConfig()
            }
        }
    }
}

// ==========================================
// MARK: - Sidebar Tree Node View (Obsidian / Finder Style)
// ==========================================
struct FolderPromptState: Identifiable {
    let id = UUID()
    let isNewFolder: Bool
    let targetURL: URL?
    var initialName: String
}

struct SidebarNodeView: View {
    let node: FileSystemNode
    let depth: Int
    @Binding var expandedFolders: Set<String>
    @Binding var selectedPaths: Set<String>
    @ObservedObject var store = MacroStore.shared
    var onSelect: (String, NSEvent.ModifierFlags) -> Void
    var onPromptFolder: (Bool, URL?, String) -> Void

    @State private var isDropTarget = false

    var body: some View {
        switch node {
        case .folder(let name, let url, let config, let children):
            let isExpanded = expandedFolders.contains(url.path)
            let isSelected = selectedPaths.contains(url.path) || store.selectedFolderPath == url.path
            
            VStack(alignment: .leading, spacing: 2) {
                // Folder Row
                HStack(spacing: 0) {
                    // Chevron button (only toggles fold)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isExpanded {
                                expandedFolders.remove(url.path)
                            } else {
                                expandedFolders.insert(url.path)
                            }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(white: 0.55))
                            .frame(width: 16, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Folder title & icon (click to select and open folder settings)
                    Button {
                        let flags = NSEvent.modifierFlags
                        if flags.contains(.command) || flags.contains(.shift) {
                            onSelect(url.path, flags)
                        } else {
                            store.selectedFolderPath = url.path
                            store.selectedFilePath = nil
                            onSelect(url.path, flags)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: config.iconName)
                                .foregroundColor(config.color)
                                .font(.system(size: 13))

                            Text(name)
                                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                                .foregroundColor(isSelected ? .white : Color(white: 0.92))
                                .lineLimit(1)

                            Spacer()

                            Text("\(children.count)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(white: 0.45))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, CGFloat(depth * 14 + 4))
                .padding(.trailing, 8)
                .padding(.vertical, 4)
                .background(
                    isDropTarget
                        ? Color.accentColor.opacity(0.3)
                        : (isSelected ? Color(red: 0.05, green: 0.45, blue: 0.95).opacity(0.7) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onDrag {
                    let pathsToDrag = selectedPaths.contains(url.path) ? Array(selectedPaths) : [url.path]
                    return NSItemProvider(object: pathsToDrag.joined(separator: "\n") as NSString)
                }
                .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isDropTarget) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                            guard let str = string as? String else { return }
                            let paths = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                            DispatchQueue.main.async {
                                store.moveItems(paths: paths, toFolder: url)
                            }
                        }
                    }
                    return true
                }
                .contextMenu {
                    Button {
                        store.selectedFolderPath = url.path
                        store.selectedFilePath = nil
                    } label: {
                        Label("Folder Settings…", systemImage: "gearshape")
                    }

                    Divider()

                    Button {
                        store.createNewMacro(inFolder: url)
                    } label: {
                        Label("New Macro in Folder", systemImage: "plus.circle")
                    }

                    Button {
                        onPromptFolder(true, url, "")
                    } label: {
                        Label("New Subfolder…", systemImage: "folder.badge.plus")
                    }

                    Divider()

                    Button {
                        onPromptFolder(false, url, name)
                    } label: {
                        Label("Rename Folder…", systemImage: "pencil")
                    }

                    Button {
                        store.revealFolderInFinder(url)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Divider()

                    Button(role: .destructive) {
                        store.deleteFolder(at: url)
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                }

                // Children (Indented)
                if isExpanded {
                    ForEach(children) { child in
                        SidebarNodeView(
                            node: child,
                            depth: depth + 1,
                            expandedFolders: $expandedFolders,
                            selectedPaths: $selectedPaths,
                            onSelect: onSelect,
                            onPromptFolder: onPromptFolder
                        )
                    }
                }
            }

        case .macro(let macro):
            let isSelected = selectedPaths.contains(macro.fileURL.path) || (store.selectedFilePath == macro.fileURL.path && selectedPaths.isEmpty)

            Button {
                let flags = NSEvent.modifierFlags
                if flags.contains(.command) || flags.contains(.shift) {
                    onSelect(macro.fileURL.path, flags)
                } else {
                    store.selectedFilePath = macro.fileURL.path
                    store.selectedFolderPath = nil
                    onSelect(macro.fileURL.path, flags)
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(squircleColor(for: macro.fileName.hashValue))
                            .frame(width: 18, height: 18)
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 9, weight: .bold))
                    }

                    Text(macro.fileName.replacingOccurrences(of: ".shortking", with: ""))
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : Color(white: 0.90))
                        .lineLimit(1)

                    Spacer()

                    ShortcutBadgeView(trigger: macro.trigger, isDimmedMini: true)
                }
                .padding(.leading, CGFloat(depth * 14 + 20))
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    isSelected
                        ? Color(red: 0.05, green: 0.45, blue: 0.95)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .onDrag {
                let pathsToDrag = selectedPaths.contains(macro.fileURL.path) ? Array(selectedPaths) : [macro.fileURL.path]
                return NSItemProvider(object: pathsToDrag.joined(separator: "\n") as NSString)
            }
            .contextMenu {
                Button {
                    store.runMacro(macro)
                } label: {
                    Label("Run Macro", systemImage: "play.fill")
                }

                Divider()

                Button {
                    store.duplicateMacro(macro)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }

                Button {
                    store.revealInFinder(macro)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Divider()

                Button(role: .destructive) {
                    if !selectedPaths.isEmpty {
                        store.deleteItems(paths: Array(selectedPaths))
                        selectedPaths.removeAll()
                    } else {
                        store.deleteMacro(macro)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func squircleColor(for hash: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.05, green: 0.5, blue: 0.95), // Blue
            Color.purple,
            Color.orange,
            Color.green,
            Color(red: 0.95, green: 0.45, blue: 0.5), // Pink
            Color.indigo,
            Color.teal
        ]
        let idx = abs(hash) % colors.count
        return colors[idx]
    }
}

// ==========================================
// MARK: - Main Editor View (Obsidian / Finder Style)
// ==========================================
struct MainEditorView: View {
    @ObservedObject var store = MacroStore.shared
    @State private var searchText = ""
    @State private var expandedFolders: Set<String> = []
    @State private var selectedPaths: Set<String> = []
    @State private var lastClickedPath: String? = nil
    @State private var isRootDropTarget = false
    
    // Folder modal/alert states
    @State private var folderPrompt: FolderPromptState?
    @State private var folderInputText = ""
    @State private var showingFolderAlert = false

    var displayNodes: [FileSystemNode] {
        if searchText.isEmpty {
            return store.treeNodes
        } else {
            return filterTree(nodes: store.treeNodes, query: searchText)
        }
    }

    func filterTree(nodes: [FileSystemNode], query: String) -> [FileSystemNode] {
        var result: [FileSystemNode] = []
        for node in nodes {
            switch node {
            case .folder(let name, let url, let config, let children):
                let matching = filterTree(nodes: children, query: query)
                if !matching.isEmpty || name.localizedCaseInsensitiveContains(query) {
                    result.append(.folder(name: name, url: url, config: config, children: matching))
                }
            case .macro(let item):
                if item.fileName.localizedCaseInsensitiveContains(query) || item.trigger.displayString.localizedCaseInsensitiveContains(query) {
                    result.append(.macro(item: item))
                }
            }
        }
        return result
    }

    func getVisiblePaths(from nodes: [FileSystemNode]) -> [String] {
        var paths: [String] = []
        for node in nodes {
            switch node {
            case .folder(_, let url, _, let children):
                paths.append(url.path)
                if expandedFolders.contains(url.path) {
                    paths.append(contentsOf: getVisiblePaths(from: children))
                }
            case .macro(let item):
                paths.append(item.fileURL.path)
            }
        }
        return paths
    }

    func findFolderInfo(path: String, in nodes: [FileSystemNode]) -> (name: String, url: URL, config: FolderConfig, count: Int)? {
        for node in nodes {
            switch node {
            case .folder(let name, let url, let config, let children):
                if url.path == path {
                    return (name, url, config, children.count)
                }
                if let found = findFolderInfo(path: path, in: children) {
                    return found
                }
            case .macro:
                break
            }
        }
        return nil
    }

    func handleSelect(path: String, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedPaths.contains(path) {
                selectedPaths.remove(path)
            } else {
                selectedPaths.insert(path)
            }
            lastClickedPath = path
        } else if modifiers.contains(.shift), let last = lastClickedPath {
            let allPaths = getVisiblePaths(from: displayNodes)
            if let i1 = allPaths.firstIndex(of: last), let i2 = allPaths.firstIndex(of: path) {
                let range = min(i1, i2)...max(i1, i2)
                for p in allPaths[range] {
                    selectedPaths.insert(p)
                }
            } else {
                selectedPaths.insert(path)
            }
        } else {
            selectedPaths = [path]
            lastClickedPath = path
        }
        
        if let macro = store.macros.first(where: { selectedPaths.contains($0.fileURL.path) }) {
            store.selectedFilePath = macro.fileURL.path
            store.selectedFolderPath = nil
        }
    }

    var body: some View {
        HSplitView {
            // ═══════════════════════════════════════════════════
            // LEFT SIDEBAR (Obsidian / Finder Style Explorer)
            // ═══════════════════════════════════════════════════
            VStack(alignment: .leading, spacing: 0) {
                // Search Capsule Pill
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    TextField("Search macros", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color(white: 0.20))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Hierarchical Folder Tree
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if displayNodes.isEmpty {
                            VStack(spacing: 8) {
                                Text(searchText.isEmpty ? "No macros or folders yet" : "No matching macros")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                        } else {
                            ForEach(displayNodes) { node in
                                SidebarNodeView(
                                    node: node,
                                    depth: 0,
                                    expandedFolders: $expandedFolders,
                                    selectedPaths: $selectedPaths,
                                    onSelect: handleSelect,
                                    onPromptFolder: { isNew, url, name in
                                        folderPrompt = FolderPromptState(isNewFolder: isNew, targetURL: url, initialName: name)
                                        folderInputText = name
                                        showingFolderAlert = true
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isRootDropTarget) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                            guard let str = string as? String else { return }
                            let paths = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                            DispatchQueue.main.async {
                                store.moveItems(paths: paths, toFolder: store.watchDirectoryURL)
                            }
                        }
                    }
                    return true
                }

                Divider()

                // Bottom Toolbar (+ Macro, + Folder, Delete, Count)
                HStack(spacing: 12) {
                    Button {
                        store.createNewMacro()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("New Macro")

                    Button {
                        folderPrompt = FolderPromptState(isNewFolder: true, targetURL: nil, initialName: "")
                        folderInputText = ""
                        showingFolderAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("New Folder")

                    if !selectedPaths.isEmpty || store.selectedMacro != nil {
                        Button {
                            if !selectedPaths.isEmpty {
                                store.deleteItems(paths: Array(selectedPaths))
                                selectedPaths.removeAll()
                            } else if let m = store.selectedMacro {
                                store.deleteMacro(m)
                            }
                        } label: {
                            Image(systemName: "trash").font(.system(size: 13))
                        }
                        .buttonStyle(.borderless)
                        .help("Delete Selected Items")
                        .foregroundColor(.red)
                    }

                    Spacer()
                    Text("\(store.macros.count) macros")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 240, idealWidth: 290, maxWidth: 450)
            .background(Color(white: 0.12))
            .alert(folderPrompt?.isNewFolder == true ? "New Folder" : "Rename Folder", isPresented: $showingFolderAlert) {
                TextField("Folder Name", text: $folderInputText)
                Button("Cancel", role: .cancel) { folderPrompt = nil }
                Button(folderPrompt?.isNewFolder == true ? "Create" : "Save") {
                    if let prompt = folderPrompt {
                        if prompt.isNewFolder {
                            store.createFolder(name: folderInputText, parentURL: prompt.targetURL)
                        } else if let target = prompt.targetURL {
                            store.renameFolder(at: target, newName: folderInputText)
                        }
                    }
                    folderPrompt = nil
                }
            }
            .onAppear {
                for node in store.treeNodes {
                    if case .folder(_, let url, _, _) = node {
                        expandedFolders.insert(url.path)
                    }
                }
            }

            // ═══════════════════════════════════════════════════
            // RIGHT DETAIL CANVAS (Macro Inspector or Folder Inspector)
            // ═══════════════════════════════════════════════════
            if let macro = store.selectedMacro {
                MacroInspectorView(macro: macro)
                    .id(macro.id)
            } else if let folderPath = store.selectedFolderPath,
                      let folderInfo = findFolderInfo(path: folderPath, in: store.treeNodes) {
                FolderInspectorView(
                    folderURL: folderInfo.url,
                    initialConfig: folderInfo.config,
                    itemCount: folderInfo.count
                )
                .id(folderPath)
            } else {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color(white: 0.18))
                            .frame(width: 72, height: 72)
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.accentColor)
                    }
                    Text("No Selection")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Choose a macro or folder from the sidebar.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Create New Macro") {
                        store.createNewMacro()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.14))
            }
        }
        .frame(minWidth: 780, minHeight: 520)
    }
}

class EditorWindow: NSWindow {
    override var undoManager: UndoManager? {
        return MacroStore.shared.undoManager
    }
}

// ==========================================
// MARK: - App Delegate with Complete Standard Menu Bar & Settings Window
// ==========================================
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate?

    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var window: NSWindow?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        CarbonHotKeyManager.shared.installHandlerIfNeeded()
        PermissionManager.shared.checkStatus()
        setupMainMenu()
        setupMenuBar()
        showEditorWindow()
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else { return }
        let url = URL(fileURLWithPath: first)
        
        let watchDir = MacroStore.shared.watchDirectoryURL
        let destURL = watchDir.appendingPathComponent(url.lastPathComponent)
        
        if url.path != destURL.path {
            if !FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.copyItem(at: url, to: destURL)
            }
        }
        
        MacroStore.shared.loadMacros()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let found = MacroStore.shared.macros.first(where: { $0.fileName == url.lastPathComponent }) {
                MacroStore.shared.selectedMacroID = found.id
                self.showEditorWindow()
            }
        }
    }

    // MARK: - Standard macOS Main Menu Bar (Top Screen)
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. Application Menu (ShortKing)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "ShortKing")
        appMenu.addItem(withTitle: "About ShortKing", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        NSApp.servicesMenu = servicesMenu
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())

        appMenu.addItem(withTitle: "Hide ShortKing", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit ShortKing", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Macro", action: #selector(newMacro), keyEquivalent: "n").target = self
        let fileSettingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        fileSettingsItem.target = self
        fileMenu.addItem(fileSettingsItem)
        let openFolderItem = NSMenuItem(title: "Open Macros Folder…", action: #selector(openFolder), keyEquivalent: "o")
        openFolderItem.keyEquivalentModifierMask = [.command, .shift]
        openFolderItem.target = self
        fileMenu.addItem(openFolderItem)
        fileMenu.addItem(withTitle: "Reload Macros", action: #selector(reload), keyEquivalent: "r").target = self
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. Edit Menu (Standard macOS Clipboard & Text editing)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 4. Macro Engine Menu
        let macroMenuItem = NSMenuItem()
        let macroMenu = NSMenu(title: "Macro")
        let runItem = NSMenuItem(title: "Run Selected Macro", action: #selector(runCurrentMacro), keyEquivalent: "\r")
        runItem.target = self
        macroMenu.addItem(runItem)
        macroMenu.addItem(withTitle: "Create New Macro", action: #selector(newMacro), keyEquivalent: "n").target = self
        macroMenu.addItem(NSMenuItem.separator())
        let emergencyItem = NSMenuItem(title: "🛑 Emergency Stop Engine", action: #selector(emergencyKill), keyEquivalent: "x")
        emergencyItem.keyEquivalentModifierMask = [.command, .control, .shift]
        emergencyItem.target = self
        macroMenu.addItem(emergencyItem)
        macroMenuItem.submenu = macroMenu
        mainMenu.addItem(macroMenuItem)

        // 5. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Macro Editor", action: #selector(showEditorWindow), keyEquivalent: "1").target = self
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // 6. Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "ShortKing Documentation", action: #selector(openLearnFolder), keyEquivalent: "?").target = self
        helpMenu.addItem(withTitle: "About ShortKing", action: #selector(showAbout), keyEquivalent: "").target = self
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Bar Menu (System Tray Icon)
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "👑 SK"
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        buildStatusMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == statusMenu {
            buildStatusMenu()
        }
    }

    func buildStatusMenu() {
        statusMenu.removeAllItems()

        let editorItem = NSMenuItem(title: "Open Macro Editor…", action: #selector(showEditorWindow), keyEquivalent: "e")
        editorItem.target = self
        statusMenu.addItem(editorItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Macro list submenu
        let macros = MacroStore.shared.macros
        if !macros.isEmpty {
            let macrosHeader = NSMenuItem(title: "Active Macros (\(macros.count)):", action: nil, keyEquivalent: "")
            macrosHeader.isEnabled = false
            statusMenu.addItem(macrosHeader)

            for macro in macros {
                let name = macro.fileName.replacingOccurrences(of: ".shortking", with: "")
                let title = "  ▶ \(name)  [\(macro.trigger.displayString)]"
                let item = NSMenuItem(title: title, action: #selector(runMacroFromMenu(_:)), keyEquivalent: "")
                item.representedObject = macro
                item.target = self
                statusMenu.addItem(item)
            }
            statusMenu.addItem(NSMenuItem.separator())
        }

        let reloadItem = NSMenuItem(title: "Reload Macros", action: #selector(reload), keyEquivalent: "r")
        reloadItem.target = self
        statusMenu.addItem(reloadItem)

        let folderItem = NSMenuItem(title: "Open Macros Folder", action: #selector(openFolder), keyEquivalent: "")
        folderItem.target = self
        statusMenu.addItem(folderItem)

        let learnItem = NSMenuItem(title: "Open Docs & Guides", action: #selector(openLearnFolder), keyEquivalent: "")
        learnItem.target = self
        statusMenu.addItem(learnItem)

        statusMenu.addItem(NSMenuItem.separator())

        let emItem = NSMenuItem(title: "🛑 Emergency Stop (⌘⌃⇧X)", action: #selector(emergencyKill), keyEquivalent: "")
        emItem.target = self
        statusMenu.addItem(emItem)

        statusMenu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About ShortKing", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        statusMenu.addItem(aboutItem)

        statusMenu.addItem(withTitle: "Quit ShortKing", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: - Actions
    @objc func showEditorWindow() {
        if window == nil {
            let win = EditorWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            win.center()
            win.title = "👑 ShortKing — Macro Editor"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.contentViewController = NSHostingController(rootView: MainEditorView())
            win.isReleasedWhenClosed = false
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettingsWindow() {
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            win.center()
            win.title = "ShortKing Settings"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.contentViewController = NSHostingController(rootView: SettingsView())
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func newMacro() {
        MacroStore.shared.createNewMacro()
        showEditorWindow()
    }

    @objc func runCurrentMacro() {
        if let m = MacroStore.shared.selectedMacro {
            MacroStore.shared.runMacro(m)
        }
    }

    @objc func runMacroFromMenu(_ sender: NSMenuItem) {
        if let macro = sender.representedObject as? MacroItem {
            MacroStore.shared.runMacro(macro)
        }
    }

    @objc func emergencyKill() {
        CarbonHotKeyManager.shared.dispatch(hotKeyID: 9999)
    }

    @objc func openLearnFolder() {
        let learnURL = URL(fileURLWithPath: "/Users/tonytoelle/Documents/PROJECTS/RedMunky - ShortKing/LEARN")
        NSWorkspace.shared.open(learnURL)
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "👑 ShortKing"
        alert.informativeText = "Compact & High-Performance macOS Macro Automation Engine\nPowered by Carbon HotKey & Quartz Event Simulation.\n\nEmergency Stop: ⌘⌃⇧X"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func reload() { MacroStore.shared.loadMacros() }
    @objc func openFolder() { NSWorkspace.shared.open(MacroStore.shared.watchDirectoryURL) }
}

// ==========================================
// MARK: - Entry Point
// ==========================================
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
