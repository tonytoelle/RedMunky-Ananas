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
    var parentFolderConfig: FolderConfig?

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

