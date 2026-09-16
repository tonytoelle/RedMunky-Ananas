import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

class AnanasParser {
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
        var triggers: [Trigger] = []
        var isEnabled: Bool = true
        var groupStack: [[MacroActionItem]] = [[]]
        var groupNames: [String] = []
        var altGroupStack: [[MacroActionItem]] = [[]]
        var altGroupNames: [String] = []
        var isParsingAltActions = false
        
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            if line.uppercased().hasPrefix("ENABLED:") {
                let valStr = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces).lowercased()
                isEnabled = (valStr != "false" && valStr != "0" && valStr != "no" && valStr != "disabled")
            } else if line.uppercased().hasPrefix("TRIGGER_MODE:") {
                let modeStr = String(line.dropFirst(13)).trimmingCharacters(in: .whitespaces).lowercased()
                if modeStr == "key_switch" {
                    // Apply mode to the last trigger
                    if !triggers.isEmpty {
                        triggers[triggers.count - 1].mode = .keySwitch
                    }
                }
            } else if line.uppercased().hasPrefix("TRIGGER:") {
                // If we were parsing alt actions, finalize them for the previous trigger
                if isParsingAltActions, !triggers.isEmpty {
                    let altItems = altGroupStack.first ?? []
                    triggers[triggers.count - 1].alternateActionItems = altItems
                    altGroupStack = [[]]
                    altGroupNames = []
                    isParsingAltActions = false
                }
                if let t = parseTrigger(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)) {
                    triggers.append(t)
                }
            } else if line.uppercased().hasPrefix("ALT_ACTION:") {
                isParsingAltActions = true
                let actionStr = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                var cleanActionStr = actionStr
                var repeats = 1
                let parts = actionStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if let lastPart = parts.last, lastPart.hasPrefix("x"), lastPart.count > 1,
                   let val = Int(lastPart.dropFirst()) {
                    repeats = val
                    cleanActionStr = String(actionStr.prefix(actionStr.count - lastPart.count)).trimmingCharacters(in: .whitespaces)
                }
                
                if cleanActionStr.lowercased().hasPrefix("group") {
                    var gName = "Group"
                    let namePart = cleanActionStr.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if namePart.hasPrefix("\"") && namePart.hasSuffix("\"") && namePart.count >= 2 {
                        gName = String(namePart.dropFirst().dropLast())
                    } else if !namePart.isEmpty {
                        gName = namePart
                    }
                    altGroupStack.append([])
                    altGroupNames.append(gName)
                } else if cleanActionStr.lowercased() == "end_group" {
                    if altGroupStack.count > 1 {
                        let subActions = altGroupStack.popLast()!
                        let name = altGroupNames.popLast()!
                        let groupItem = MacroActionItem(action: .group(name: name, actions: subActions), repeatCount: repeats)
                        altGroupStack[altGroupStack.count - 1].append(groupItem)
                    }
                } else {
                    if let a = parseAction(cleanActionStr) {
                        altGroupStack[altGroupStack.count - 1].append(MacroActionItem(action: a, repeatCount: repeats))
                    }
                }
            } else if line.uppercased().hasPrefix("ACTION:") {
                let actionStr = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                var cleanActionStr = actionStr
                var repeats = 1
                let parts = actionStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if let lastPart = parts.last, lastPart.hasPrefix("x"), lastPart.count > 1,
                   let val = Int(lastPart.dropFirst()) {
                    repeats = val
                    cleanActionStr = String(actionStr.prefix(actionStr.count - lastPart.count)).trimmingCharacters(in: .whitespaces)
                }
                
                if cleanActionStr.lowercased().hasPrefix("group") {
                    var gName = "Group"
                    let namePart = cleanActionStr.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if namePart.hasPrefix("\"") && namePart.hasSuffix("\"") && namePart.count >= 2 {
                        gName = String(namePart.dropFirst().dropLast())
                    } else if !namePart.isEmpty {
                        gName = namePart
                    }
                    groupStack.append([])
                    groupNames.append(gName)
                } else if cleanActionStr.lowercased() == "end_group" {
                    if groupStack.count > 1 {
                        let subActions = groupStack.popLast()!
                        let name = groupNames.popLast()!
                        let groupItem = MacroActionItem(action: .group(name: name, actions: subActions), repeatCount: repeats)
                        groupStack[groupStack.count - 1].append(groupItem)
                    }
                } else {
                    if let a = parseAction(cleanActionStr) {
                        groupStack[groupStack.count - 1].append(MacroActionItem(action: a, repeatCount: repeats))
                    }
                }
            }
        }
        
        // Finalize any remaining alt actions for the last trigger
        if isParsingAltActions, !triggers.isEmpty {
            let altItems = altGroupStack.first ?? []
            triggers[triggers.count - 1].alternateActionItems = altItems
        }
        
        let items = groupStack.first ?? []
        
        func flattenActions(_ actionItems: [MacroActionItem]) -> [MacroActionItem] {
            var flat: [MacroActionItem] = []
            for item in actionItems {
                flat.append(item)
                if case .group(_, let sub) = item.action {
                    flat.append(contentsOf: flattenActions(sub))
                }
            }
            return flat
        }
        let flatItems = flattenActions(items)
        
        func resolveDoAgainTargets(in actionItems: inout [MacroActionItem], flat: [MacroActionItem]) {
            for i in 0..<actionItems.count {
                if case .doAgain(let target) = actionItems[i].action, case .step(let idx) = target {
                    let targetIdx = idx - 1
                    if targetIdx >= 0 && targetIdx < flat.count {
                        actionItems[i].action = .doAgain(target: .action(flat[targetIdx].id))
                    } else {
                        actionItems[i].action = .doAgain(target: .origin)
                    }
                } else if case .group(let name, var sub) = actionItems[i].action {
                    resolveDoAgainTargets(in: &sub, flat: flat)
                    actionItems[i].action = .group(name: name, actions: sub)
                }
            }
        }
        
        var resolvedItems = items
        resolveDoAgainTargets(in: &resolvedItems, flat: flatItems)
        
        guard !triggers.isEmpty else { return nil }
        return MacroItem(fileName: url.lastPathComponent, fileURL: url, triggers: triggers, actionItems: resolvedItems, isEnabled: isEnabled)
    }

    static func parseAction(_ s: String) -> MacroAction? {
        let parts = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let cmd = parts.first?.lowercased() else { return nil }
        switch cmd {
        case "window_transform":
            if parts.count >= 5 {
                let p1Parts = parts[1].split(separator: ",")
                let p2Parts = parts[2].split(separator: ",")
                let p3Parts = parts[3].split(separator: ",")
                let p4Parts = parts[4].split(separator: ",")
                if p1Parts.count >= 2, p2Parts.count >= 2, p3Parts.count >= 2, p4Parts.count >= 2,
                   let x1 = Double(p1Parts[0]), let y1 = Double(p1Parts[1]),
                   let x2 = Double(p2Parts[0]), let y2 = Double(p2Parts[1]),
                   let x3 = Double(p3Parts[0]), let y3 = Double(p3Parts[1]),
                   let x4 = Double(p4Parts[0]), let y4 = Double(p4Parts[1]) {
                    return .windowTransform(
                        p1: CGPoint(x: x1, y: y1),
                        p2: CGPoint(x: x2, y: y2),
                        p3: CGPoint(x: x3, y: y3),
                        p4: CGPoint(x: x4, y: y4)
                    )
                }
            }
        case "current_position", "current_pos":
            let isRight = parts.count >= 2 && parts[1].lowercased().contains("right")
            return .currentPosition(button: isRight ? .right : .left)
        case "click":
            if parts.count >= 2 && parts[1].lowercased() == "current" {
                return .currentPosition(button: .left)
            }
            if parts.count >= 3, let x = Double(parts[1]), let y = Double(parts[2]) {
                return .click(point: CGPoint(x: x, y: y), button: .left)
            }
        case "right_click":
            if parts.count >= 2 && parts[1].lowercased() == "current" {
                return .currentPosition(button: .right)
            }
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
        case "move", "move_cursor":
            if parts.count >= 3, let x = Double(parts[1]), let y = Double(parts[2]) {
                return .moveCursor(point: CGPoint(x: x, y: y))
            }
        case "path":
            var pts: [SequencePoint] = []
            for chunk in parts.dropFirst() {
                let segs = chunk.split(separator: ":")
                if segs.count >= 2 {
                    let coords = segs[0].split(separator: ",")
                    if coords.count >= 2, let x = Double(coords[0]), let y = Double(coords[1]) {
                        let typeWithRepeat = String(segs[1]).lowercased()
                        let subSegs = typeWithRepeat.split(separator: "*")
                        let typeStr = String(subSegs[0])
                        var repeatVal = 1
                        if subSegs.count >= 2, let r = Int(subSegs[1]) {
                            repeatVal = r
                        }
                        
                        let type: SequencePointType
                        switch typeStr {
                        case "click": type = .click
                        case "drag":  type = .drag
                        case "move":  type = .move
                        default:      type = .move
                        }
                        pts.append(SequencePoint(point: CGPoint(x: x, y: y), type: type, repeatCount: repeatVal))
                    }
                }
            }
            return .path(points: pts)
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
        case "origin":
            if parts.count >= 2 {
                let typeStr = parts[1].lowercased()
                if typeStr == "window" {
                    return .originAction(type: .window)
                }
            }
            return .originAction(type: .cursor)
        case "press_shortcut":
            if parts.count >= 2, let trig = parseTrigger(parts[1]) { return .pressShortcut(trigger: trig) }
        case "restore_cursor", "restore_origin", "move_to_origin", "do_again":
            if parts.count >= 2, let last = parts.last {
                if last.hasPrefix("step_") {
                    let numStr = last.replacingOccurrences(of: "step_", with: "")
                    if let idx = Int(numStr) {
                        return .doAgain(target: .step(idx))
                    }
                } else if last == "window_origin" {
                    return .doAgain(target: .originWindow)
                }
            }
            return .doAgain(target: .origin)
        case "open_file":
            var t = s.dropFirst(cmd.count).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 { t = String(t.dropFirst().dropLast()) }
            return .openFile(path: t)
        case "custom_action":
            var t = s.dropFirst(cmd.count).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 { t = String(t.dropFirst().dropLast()) }
            return .customAction(script: t)
        case "ax_press", "ax_click", "axpress", "axclick":
            var t = s.dropFirst(cmd.count).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 { t = String(t.dropFirst().dropLast()) }
            return .axPress(target: t)
        case "screenshot_annotation", "screenshot_with_note", "annotated_screenshot":
            return .screenshotAnnotation
        case "volume_up":
            return .volumeUp
        case "volume_down":
            return .volumeDown
        case "brightness_up":
            return .brightnessUp
        case "brightness_down":
            return .brightnessDown
        default: break
        }
        return nil
    }

    static func generateScript(triggers: [Trigger], actionItems: [MacroActionItem], isEnabled: Bool = true) -> String {
        var lines = ["# RedMunky Ananas Macro Script"]
        if !isEnabled {
            lines.append("ENABLED: false")
        }
        for t in triggers {
            lines.append("TRIGGER: \(t.scriptString)")
            if t.mode == .keySwitch {
                lines.append("TRIGGER_MODE: key_switch")
            }
        }
        lines.append("")
        lines.append("# Actions:")
        
        func appendActionItem(_ item: MacroActionItem, prefix: String = "ACTION") {
            var line = ""
            switch item.action {
            case .doAgain(let target):
                switch target {
                case .origin:
                    line = "\(prefix): do_again"
                case .originWindow:
                    line = "\(prefix): do_again window_origin"
                case .step(let idx):
                    line = "\(prefix): do_again step_\(idx)"
                case .action(let tid):
                    func findFlatIndex(id: UUID, currentItems: [MacroActionItem], indexTracker: inout Int) -> Int? {
                        for current in currentItems {
                            indexTracker += 1
                            if current.id == id { return indexTracker }
                            if case .group(_, let sub) = current.action {
                                if let found = findFlatIndex(id: id, currentItems: sub, indexTracker: &indexTracker) {
                                    return found
                                }
                            }
                        }
                        return nil
                    }
                    var tracker = 0
                    if let idx = findFlatIndex(id: tid, currentItems: actionItems, indexTracker: &tracker) {
                        line = "\(prefix): do_again step_\(idx)"
                    } else {
                        line = "\(prefix): do_again"
                    }
                }
            case .group(let name, let subActions):
                line = "\(prefix): group \"\(name)\""
                if item.repeatCount > 1 {
                    line += " x\(item.repeatCount)"
                }
                lines.append(line)
                for subItem in subActions {
                    appendActionItem(subItem, prefix: prefix)
                }
                lines.append("\(prefix): end_group")
                return
            default:
                line = item.action.scriptLine
                // Replace "ACTION:" prefix with the correct prefix for alt actions
                if prefix == "ALT_ACTION" && line.hasPrefix("ACTION:") {
                    line = "ALT_ACTION:" + line.dropFirst(7)
                }
            }
            
            if item.repeatCount > 1 {
                line += " x\(item.repeatCount)"
            }
            // Ensure correct prefix for non-scriptLine items
            if prefix == "ALT_ACTION" && line.hasPrefix("ACTION:") {
                line = "ALT_ACTION:" + line.dropFirst(7)
            }
            lines.append(line)
        }
        
        for item in actionItems {
            appendActionItem(item)
        }
        
        // Emit alternate actions for key switch triggers
        for t in triggers where t.mode == .keySwitch && !t.alternateActionItems.isEmpty {
            lines.append("")
            lines.append("# Alternate Actions:")
            for item in t.alternateActionItems {
                appendActionItem(item, prefix: "ALT_ACTION")
            }
        }
        
        return lines.joined(separator: "\n") + "\n"
    }

    static func generateScript(trigger: Trigger, actionItems: [MacroActionItem]) -> String {
        return generateScript(triggers: [trigger], actionItems: actionItems)
    }
    static func generateScript(trigger: Trigger, actions: [MacroAction]) -> String {
        let items = actions.map { MacroActionItem(action: $0) }
        return generateScript(triggers: [trigger], actionItems: items)
    }
    static func generateScript(triggers: [Trigger], actions: [MacroAction]) -> String {
        let items = actions.map { MacroActionItem(action: $0) }
        return generateScript(triggers: triggers, actionItems: items)
    }
}

// ==========================================
// MARK: - Input Simulator (Robust & Timing-Correct)
// ==========================================
