import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

// ==========================================
// MARK: - KeyCode Mapping Helper
// ==========================================
struct KeyMap {
    static let keyNames: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "<": 43, "/": 44, "n": 45, "m": 46, ".": 47, ">": 47,
        "tab": 48, "space": 49, "`": 50, "delete": 51, "enter": 36, "return": 36, "esc": 53,
        "escape": 53, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "brightness_down": 145, "brightness_up": 144
    ]
    static func keyCode(for key: String) -> CGKeyCode? { keyNames[key.lowercased()] }
    static func name(for keyCode: CGKeyCode) -> String {
        keyNames.first(where: { $0.value == keyCode })?.key.uppercased() ?? "Key(\(keyCode))"
    }
}

// ==========================================
// MARK: - Models (with stable IDs for drag-drop)
// ==========================================
enum TriggerMode: String, Codable, CaseIterable, Hashable {
    case keyPress = "key_press"
    case keySwitch = "key_switch"
    
    var displayName: String {
        switch self {
        case .keyPress: return "Key Press"
        case .keySwitch: return "Key Switch"
        }
    }
    
    var iconName: String {
        switch self {
        case .keyPress: return "keyboard"
        case .keySwitch: return "arrow.triangle.swap"
        }
    }
    
    var color: Color {
        switch self {
        case .keyPress: return Color(red: 0.45, green: 0.2, blue: 0.8)
        case .keySwitch: return Color(red: 0.1, green: 0.65, blue: 0.7)
        }
    }
}

struct Trigger: Hashable, Equatable, Codable, Identifiable {
    var id = UUID()
    var keyCode: CGKeyCode
    var requireCmd: Bool
    var requireShift: Bool
    var requireOption: Bool
    var requireControl: Bool
    var mode: TriggerMode = .keyPress
    var alternateActionItems: [MacroActionItem] = []

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

    // Custom Codable for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, keyCode, requireCmd, requireShift, requireOption, requireControl, mode
    }

    init(keyCode: CGKeyCode, requireCmd: Bool, requireShift: Bool, requireOption: Bool, requireControl: Bool, mode: TriggerMode = .keyPress, alternateActionItems: [MacroActionItem] = []) {
        self.keyCode = keyCode
        self.requireCmd = requireCmd
        self.requireShift = requireShift
        self.requireOption = requireOption
        self.requireControl = requireControl
        self.mode = mode
        self.alternateActionItems = alternateActionItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        keyCode = try c.decode(CGKeyCode.self, forKey: .keyCode)
        requireCmd = try c.decode(Bool.self, forKey: .requireCmd)
        requireShift = try c.decode(Bool.self, forKey: .requireShift)
        requireOption = try c.decode(Bool.self, forKey: .requireOption)
        requireControl = try c.decode(Bool.self, forKey: .requireControl)
        mode = try c.decodeIfPresent(TriggerMode.self, forKey: .mode) ?? .keyPress
        alternateActionItems = []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(requireCmd, forKey: .requireCmd)
        try c.encode(requireShift, forKey: .requireShift)
        try c.encode(requireOption, forKey: .requireOption)
        try c.encode(requireControl, forKey: .requireControl)
        try c.encode(mode, forKey: .mode)
    }

    // Manual Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(keyCode)
        hasher.combine(requireCmd)
        hasher.combine(requireShift)
        hasher.combine(requireOption)
        hasher.combine(requireControl)
        hasher.combine(mode)
    }

    func matchesSearchQuery(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return false }
        
        let keyName = KeyMap.name(for: keyCode).lowercased()
        
        // 1. Direct match on key name alone (e.g. searching "f8" matches F8, ⇧F8, ⌥F8, ⌃F8, ⌘F8, etc.)
        // or searching "a" matches A, ⇧A, ⌃A, ⌘A, etc.
        if keyName == q {
            return true
        }
        
        // 2. Direct match on displayString or scriptString
        let dStr = displayString.lowercased()
        let sStr = scriptString.lowercased()
        if dStr.contains(q) || sStr.contains(q) {
            return true
        }
        
        // 3. Multi-word/token matching (e.g. "shift f8", "shift+f8", "ctrl a", "alt a", "opt f8", "cmd f8")
        let cleanQ = q.replacingOccurrences(of: "+", with: " ")
                      .replacingOccurrences(of: "-", with: " ")
                      .replacingOccurrences(of: "_", with: " ")
        let tokens = cleanQ.split(separator: " ").map { String($0) }
        
        if tokens.contains(keyName) {
            var allModifiersMatch = true
            for token in tokens where token != keyName {
                switch token {
                case "cmd", "command", "⌘":
                    if !requireCmd { allModifiersMatch = false }
                case "shift", "⇧":
                    if !requireShift { allModifiersMatch = false }
                case "opt", "option", "alt", "⌥":
                    if !requireOption { allModifiersMatch = false }
                case "ctrl", "control", "⌃":
                    if !requireControl { allModifiersMatch = false }
                default:
                    allModifiersMatch = false
                }
            }
            if allModifiersMatch {
                return true
            }
        }
        
        // 4. Fuzzy match fallback
        if fuzzyMatch(q, in: sStr).matches || fuzzyMatch(q, in: dStr).matches {
            return true
        }
        
        return false
    }

    // Manual Equatable
    static func == (lhs: Trigger, rhs: Trigger) -> Bool {
        return lhs.id == rhs.id &&
               lhs.keyCode == rhs.keyCode &&
               lhs.requireCmd == rhs.requireCmd &&
               lhs.requireShift == rhs.requireShift &&
               lhs.requireOption == rhs.requireOption &&
               lhs.requireControl == rhs.requireControl &&
               lhs.mode == rhs.mode
    }
}

// CRITICAL FIX: MacroAction now has a STABLE UUID stored as a constant
// This is essential for SwiftUI List drag-drop to work correctly
struct MacroActionItem: Identifiable, Equatable {
    let id: UUID   // stable — created once, never regenerated
    var action: MacroAction
    var repeatCount: Int = 1

    init(action: MacroAction, repeatCount: Int = 1) {
        self.id = UUID()
        self.action = action
        self.repeatCount = repeatCount
    }

    init(id: UUID, action: MacroAction, repeatCount: Int = 1) {
        self.id = id
        self.action = action
        self.repeatCount = repeatCount
    }
}

enum DoAgainTarget: Equatable {
    case origin
    case originWindow
    case step(Int)
    case action(UUID)
    
    var isOrigin: Bool {
        if case .origin = self { return true }
        if case .originWindow = self { return true }
        return false
    }
}

// ==========================================
// MARK: - Multi-Point Cursor Sequence & Path Models
// ==========================================
enum SequencePointType: String, CaseIterable, Identifiable, Codable {
    case click = "Click"
    case drag = "Drag"
    case move = "Move"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .click: return "cursorarrow.click"
        case .drag: return "hand.draw"
        case .move: return "cursorarrow.motionlines"
        }
    }
    
    var color: Color {
        switch self {
        case .click: return Color(red: 0.08, green: 0.55, blue: 1.0)
        case .drag: return Color.purple
        case .move: return Color(red: 0.28, green: 0.72, blue: 0.52)
        }
    }
}

struct SequencePoint: Identifiable, Equatable, Codable {
    let id: UUID
    var point: CGPoint
    var type: SequencePointType
    var repeatCount: Int = 1
    
    init(id: UUID = UUID(), point: CGPoint, type: SequencePointType, repeatCount: Int = 1) {
        self.id = id
        self.point = point
        self.type = type
        self.repeatCount = repeatCount
    }
}

enum OriginType: String, Codable, CaseIterable {
    case cursor
    case window
    
    var title: String {
        switch self {
        case .cursor: return "Cursor Position"
        case .window: return "Window Size & Position"
        }
    }
}

enum MacroAction: Equatable {
    case click(point: CGPoint, button: CGMouseButton)
    case drag(start: CGPoint, end: CGPoint)
    case path(points: [SequencePoint])
    case delay(ms: UInt32)
    case typeText(text: String)
    case pasteText(text: String)
    case pressKey(keyCode: CGKeyCode)
    case pressShortcut(trigger: Trigger)
    case doAgain(target: DoAgainTarget)
    case moveCursor(point: CGPoint)
    case openFile(path: String)
    case customAction(script: String)
    case volumeUp
    case volumeDown
    case brightnessUp
    case brightnessDown
    indirect case group(name: String, actions: [MacroActionItem])
    case windowTransform(p1: CGPoint, p2: CGPoint, p3: CGPoint, p4: CGPoint)
    case originAction(type: OriginType)
    case currentPosition(button: CGMouseButton)
    case axPress(target: String)
    case screenshotAnnotation

    var iconName: String {
        switch self {
        case .click:        return "cursorarrow.click"
        case .currentPosition: return "cursorarrow.click.2"
        case .drag:         return "hand.draw"
        case .path:         return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .delay:        return "timer"
        case .typeText:     return "text.cursor"
        case .pasteText:    return "doc.on.clipboard"
        case .pressKey, .pressShortcut: return "keyboard"
        case .doAgain:      return "arrow.counterclockwise"
        case .moveCursor:   return "cursorarrow.motionlines"
        case .openFile:     return "arrow.up.forward.app"
        case .customAction: return "terminal"
        case .volumeUp:     return "speaker.wave.3.fill"
        case .volumeDown:   return "speaker.wave.1.fill"
        case .brightnessUp:   return "sun.max.fill"
        case .brightnessDown: return "sun.min.fill"
        case .group:        return "folder"
        case .windowTransform: return "macwindow"
        case .originAction:  return "scope"
        case .axPress:       return "hand.tap"
        case .screenshotAnnotation: return "rectangle.dashed.and.paperclip"
        }
    }
    var color: Color {
        switch self {
        case .click(_, let button): return button == .left ? Color(red: 0.08, green: 0.45, blue: 0.82) : Color(red: 0.04, green: 0.52, blue: 0.54)
        case .currentPosition(let button): return button == .left ? Color(red: 0.08, green: 0.45, blue: 0.82) : Color(red: 0.04, green: 0.52, blue: 0.54)
        case .drag:         return Color(red: 0.52, green: 0.22, blue: 0.75)
        case .path:         return Color(red: 0.65, green: 0.25, blue: 0.85)
        case .delay:        return Color(red: 0.88, green: 0.42, blue: 0.04)
        case .typeText:     return Color(red: 0.12, green: 0.58, blue: 0.24)
        case .pasteText:    return Color(red: 0.04, green: 0.52, blue: 0.54)
        case .pressKey, .pressShortcut: return Color(red: 0.32, green: 0.28, blue: 0.72)
        case .doAgain:      return Color(red: 0.12, green: 0.58, blue: 0.65)
        case .moveCursor:   return Color(red: 0.28, green: 0.52, blue: 0.92)
        case .openFile:     return Color(red: 0.1, green: 0.65, blue: 0.6)
        case .customAction: return Color.pink
        case .volumeUp, .volumeDown: return Color.blue
        case .brightnessUp, .brightnessDown: return Color.orange
        case .group:        return Color.orange
        case .windowTransform: return Color(red: 0.1, green: 0.58, blue: 0.8)
        case .originAction: return Color(red: 0.85, green: 0.15, blue: 0.45)
        case .axPress:      return Color.purple
        case .screenshotAnnotation: return Color(red: 0.18, green: 0.52, blue: 0.78)
        }
    }
    var title: String {
        switch self {
        case .click(_, let b):      return "\(b == .left ? "Left" : "Right") Click"
        case .currentPosition:      return "Current Position"
        case .drag:                 return "Drag"
        case .path:                 return "Path"
        case .delay:                return "Delay"
        case .typeText:             return "Type"
        case .pasteText:            return "Paste"
        case .pressKey, .pressShortcut: return "Key Press"
        case .doAgain:              return "Do Again"
        case .moveCursor:           return "Move Cursor"
        case .openFile:             return "Open File"
        case .customAction:         return "Custom Action"
        case .volumeUp:             return "Volume Up"
        case .volumeDown:           return "Volume Down"
        case .brightnessUp:         return "Brightness Up"
        case .brightnessDown:       return "Brightness Down"
        case .group:                return "Group"
        case .windowTransform:      return "Window Transform"
        case .originAction:         return "Origin"
        case .axPress:              return "AX Press"
        case .screenshotAnnotation: return "Screenshot with Note"
        }
    }
    var details: String {
        switch self {
        case .click(let p, let b):
            return "Click \(b == .left ? "Left Button" : "Right Button") at coordinates (\(Int(p.x)), \(Int(p.y)))"
        case .currentPosition(let b):
            return "Click \(b == .left ? "Left Button" : "Right Button") at current cursor position"
        case .drag(let s, let e):   return "Drag cursor from (\(Int(s.x)), \(Int(s.y))) to (\(Int(e.x)), \(Int(e.y)))"
        case .path(let pts):        return "\(pts.count) steps cursor sequence"
        case .delay(let ms):        return "Wait \(ms) milliseconds before next step"
        case .typeText(let t):      return "Type: \"\(t)\""
        case .pasteText(let t):     return "Paste: \"\(t)\""
        case .pressKey(let k):      return "Press key: \(KeyMap.name(for: k))"
        case .pressShortcut(let t): return "Hotkey combo: \(t.displayString)"
        case .doAgain(let target):
            switch target {
            case .origin:
                return "Move cursor back to position before macro started"
            case .originWindow:
                return "Restore active window size & position to state before macro started"
            case .step(let idx):
                return "Move cursor to coordinates of Action \(idx)"
            case .action:
                return "Move cursor to target action coordinates"
            }
        case .moveCursor(let p):
            return "Move cursor to coordinates (\(Int(p.x)), \(Int(p.y)))"
        case .openFile(let path):
            return "Open file or app at: \(path)"
        case .customAction(let script):
            return "Run command: \(script)"
        case .volumeUp:
            return "Increase system volume (Native)"
        case .volumeDown:
            return "Decrease system volume (Native)"
        case .brightnessUp:
            return "Increase screen brightness (Native)"
        case .brightnessDown:
            return "Decrease screen brightness (Native)"
        case .group(let name, let actions):
            return "Group: \"\(name)\" (\(actions.count) actions)"
        case .windowTransform(let p1, _, _, _):
            return "Window Transform coordinates starting at (\(Int(p1.x)), \(Int(p1.y)))"
        case .originAction(let type):
            return "Record current \(type == .cursor ? "cursor position" : "active window state") as origin"
        case .axPress(let target):
            return "Perform Accessibility Press on \"\(target)\""
        case .screenshotAnnotation:
            return "Capture a screen region and add a note"
        }
    }
    var parameterString: String {
        switch self {
        case .click(let point, _):
            return "\(Int(point.x)), \(Int(point.y))"
        case .currentPosition(let b):
            return "\(b == .left ? "Left" : "Right") Click"
        case .drag(let start, let end):
            return "(\(Int(start.x)), \(Int(start.y))) → (\(Int(end.x)), \(Int(end.y)))"
        case .path(let pts):
            return "\(pts.count) pts"
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
                return "Move Cursor to Origin"
            case .originWindow:
                return "Origin Window Transformation"
            case .step(let idx):
                return "Action \(idx)"
            case .action:
                return "Action"
            }
        case .moveCursor(let point):
            return "\(Int(point.x)), \(Int(point.y))"
        case .openFile(let path):
            return path.isEmpty ? "Choose file..." : URL(fileURLWithPath: path).lastPathComponent
        case .customAction(let script):
            return script
        case .volumeUp:
            return "+"
        case .volumeDown:
            return "-"
        case .brightnessUp:
            return "+"
        case .brightnessDown:
            return "-"
        case .group(_, let actions):
            return "\(actions.count) actions"
        case .windowTransform:
            return "4 corners"
        case .originAction(let type):
            return type.title
        case .axPress(let target):
            return "\"\(target)\""
        case .screenshotAnnotation:
            return "F9 tool"
        }
    }
    var scriptLine: String {
        switch self {
        case .click(let p, let b):
            return b == .left ? "ACTION: click \(Int(p.x)) \(Int(p.y))" : "ACTION: right_click \(Int(p.x)) \(Int(p.y))"
        case .currentPosition(let b):
            return "ACTION: current_position \(b == .left ? "left" : "right")"
        case .drag(let s, let e):   return "ACTION: drag \(Int(s.x)) \(Int(s.y)) to \(Int(e.x)) \(Int(e.y))"
        case .path(let pts):
            let pStr = pts.map { pt -> String in
                let base = "\(Int(pt.point.x)),\(Int(pt.point.y)):\(pt.type.rawValue.lowercased())"
                return pt.repeatCount > 1 ? "\(base)*\(pt.repeatCount)" : base
            }.joined(separator: " ")
            return "ACTION: path \(pStr)"
        case .delay(let ms):        return "ACTION: delay \(ms)"
        case .typeText(let t):      return "ACTION: type \"\(t)\""
        case .pasteText(let t):     return "ACTION: paste \"\(t)\""
        case .pressKey(let k):      return "ACTION: press \(KeyMap.name(for: k).lowercased())"
        case .pressShortcut(let t): return "ACTION: press_shortcut \(t.scriptString)"
        case .doAgain(let target):
            switch target {
            case .origin:
                return "ACTION: do_again"
            case .originWindow:
                return "ACTION: do_again window_origin"
            case .step(let idx):
                return "ACTION: do_again step_\(idx)"
            case .action:
                return "ACTION: do_again"
            }
        case .moveCursor(let p):
            return "ACTION: move \(Int(p.x)) \(Int(p.y))"
        case .openFile(let path):
            return "ACTION: open_file \"\(path)\""
        case .customAction(let script):
            return "ACTION: custom_action \"\(script)\""
        case .volumeUp:
            return "ACTION: volume_up"
        case .volumeDown:
            return "ACTION: volume_down"
        case .brightnessUp:
            return "ACTION: brightness_up"
        case .brightnessDown:
            return "ACTION: brightness_down"
        case .group(let name, _):
            return "ACTION: group \"\(name)\""
        case .windowTransform(let p1, let p2, let p3, let p4):
            return "ACTION: window_transform \(Int(p1.x)),\(Int(p1.y)) \(Int(p2.x)),\(Int(p2.y)) \(Int(p3.x)),\(Int(p3.y)) \(Int(p4.x)),\(Int(p4.y))"
        case .originAction(let type):
            return "ACTION: origin \(type.rawValue)"
        case .axPress(let target):
            return "ACTION: ax_press \"\(target)\""
        case .screenshotAnnotation:
            return "ACTION: screenshot_annotation"
        }
    }
    
    var hasCoordinates: Bool {
        switch self {
        case .click, .drag, .moveCursor, .path:
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
    var customAppIconBundleId: String? = nil
    var isEnabled: Bool = true
    
    init() {}
    
    init(iconName: String = "folder.fill", colorName: String = "blue", isRestrictedToApps: Bool = false, targetApps: [TargetApp] = [], customAppIconBundleId: String? = nil, isEnabled: Bool = true) {
        self.iconName = iconName
        self.colorName = colorName
        self.isRestrictedToApps = isRestrictedToApps
        self.targetApps = targetApps
        self.customAppIconBundleId = customAppIconBundleId
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case iconName, colorName, isRestrictedToApps, targetApps, customAppIconBundleId, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "folder.fill"
        self.colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? "blue"
        self.isRestrictedToApps = try container.decodeIfPresent(Bool.self, forKey: .isRestrictedToApps) ?? false
        self.targetApps = try container.decodeIfPresent([TargetApp].self, forKey: .targetApps) ?? []
        self.customAppIconBundleId = try container.decodeIfPresent(String.self, forKey: .customAppIconBundleId)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    
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
