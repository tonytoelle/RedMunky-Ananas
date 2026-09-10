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

    func searchScore(_ query: String) -> Int? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 0 }
        
        var bestScore = Int.max
        
        // 1. Check trigger score
        for trig in triggers {
            if let score = trig.searchScore(query: q) {
                bestScore = min(bestScore, score)
            }
        }
        
        // 2. Check file name score
        let cleanFileName = fileName.replacingOccurrences(of: ".shortking", with: "").lowercased()
        if cleanFileName == q {
            bestScore = min(bestScore, 0)
        } else if cleanFileName.hasPrefix(q) {
            bestScore = min(bestScore, 1)
        } else if cleanFileName.contains(q) {
            bestScore = min(bestScore, 5)
        } else {
            let fm = fuzzyMatch(q, in: cleanFileName)
            if fm.matches {
                bestScore = min(bestScore, 40 + fm.score)
            }
        }
        
        // 3. Check action items score
        for item in actionItems {
            let desc = item.action.title.lowercased()
            if desc == q {
                bestScore = min(bestScore, 10)
            } else if desc.contains(q) {
                bestScore = min(bestScore, 20)
            }
        }
        
        return bestScore < Int.max ? bestScore : nil
    }

    func matchesSearchQuery(_ query: String) -> Bool {
        return searchScore(query) != nil
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
