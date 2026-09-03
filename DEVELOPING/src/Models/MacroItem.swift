import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

class MacroItem: Identifiable, ObservableObject {
    let id: UUID
    @Published var fileName: String
    @Published var fileURL: URL
    @Published var triggers: [Trigger] = []
    @Published var actionItems: [MacroActionItem]  // items have stable IDs for drag-drop
    @Published var isEnabled: Bool = true
    @Published var parentFolderConfig: FolderConfig?

    var isEffectivelyEnabled: Bool {
        guard isEnabled else { return false }
        return parentFolderConfig?.isEnabled ?? true
    }

    var actions: [MacroAction] { actionItems.map(\.action) }

    var trigger: Trigger {
        get { triggers.first ?? Trigger(keyCode: 0, requireCmd: false, requireShift: false, requireOption: false, requireControl: false) }
        set {
            if triggers.isEmpty {
                triggers = [newValue]
            } else {
                triggers[0] = newValue
            }
        }
    }

    init(fileName: String, fileURL: URL, trigger: Trigger, actionItems: [MacroActionItem], isEnabled: Bool = true, parentFolderConfig: FolderConfig? = nil) {
        self.id = UUID()
        self.fileName = fileName
        self.fileURL = fileURL
        self.triggers = [trigger]
        self.actionItems = actionItems
        self.isEnabled = isEnabled
        self.parentFolderConfig = parentFolderConfig
    }

    init(fileName: String, fileURL: URL, triggers: [Trigger], actionItems: [MacroActionItem], isEnabled: Bool = true, parentFolderConfig: FolderConfig? = nil) {
        self.id = UUID()
        self.fileName = fileName
        self.fileURL = fileURL
        self.triggers = triggers
        self.actionItems = actionItems
        self.isEnabled = isEnabled
        self.parentFolderConfig = parentFolderConfig
    }

    func matchesSearchQuery(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        
        // 1. Check all triggers
        for trig in triggers {
            if trig.matchesSearchQuery(q) {
                return true
            }
        }
        
        // 2. Check file name
        let cleanFileName = fileName.replacingOccurrences(of: ".shortking", with: "")
        if cleanFileName.lowercased().contains(q) {
            return true
        }
        if fuzzyMatch(q, in: cleanFileName).matches {
            return true
        }
        
        return false
    }
}

// ==========================================
// MARK: - Carbon HotKey Manager
// ==========================================
func carbonHotKeyCallback(
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
