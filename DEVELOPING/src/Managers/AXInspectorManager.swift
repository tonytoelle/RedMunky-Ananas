import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon

// MARK: - AX Element Model Node
struct AXElementNode: Identifiable {
    let id = UUID()
    let element: AXUIElement
    let role: String
    let subrole: String?
    let title: String?
    let description: String?
    let value: String?
    let identifier: String?
    let frame: CGRect?
    let pid: pid_t
    
    var displayName: String {
        if let title = title, !title.isEmpty {
            return "\"\(title)\""
        }
        if let desc = description, !desc.isEmpty {
            return desc
        }
        if let id = identifier, !id.isEmpty {
            return "#\(id)"
        }
        if let sub = subrole, !sub.isEmpty {
            return "\(role) (\(sub))"
        }
        return role
    }
    
    var roleShort: String {
        role.replacingOccurrences(of: "AX", with: "")
    }
}

// MARK: - App Info Model
struct TargetAppInfo {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let executableURL: URL?
}

// MARK: - Highlighting Overlay Window
class AXHighlightOverlayWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.15, green: 0.85, blue: 0.45, alpha: 0.18).cgColor
        view.layer?.borderColor = NSColor(red: 0.15, green: 0.85, blue: 0.45, alpha: 0.85).cgColor
        view.layer?.borderWidth = 2.5
        view.layer?.cornerRadius = 4.0
        self.contentView = view
    }
    
    func updateFrame(for quartzRect: CGRect) {
        guard let primaryScreen = NSScreen.screens.first else {
            orderOut(nil)
            return
        }
        
        let primaryHeight = primaryScreen.frame.height
        // Convert Quartz display coordinates (top-left origin) to Cocoa screen coordinates (bottom-left origin)
        let cocoaY = primaryHeight - (quartzRect.origin.y + quartzRect.size.height)
        let cocoaRect = NSRect(x: quartzRect.origin.x, y: cocoaY, width: quartzRect.size.width, height: quartzRect.size.height)
        
        // Add minimal padding
        let paddedRect = cocoaRect.insetBy(dx: -2, dy: -2)
        self.setFrame(paddedRect, display: true)
        if !self.isVisible {
            self.orderFront(nil)
        }
    }
}

// MARK: - AX Inspector Manager
class AXInspectorManager: ObservableObject {
    static let shared = AXInspectorManager()
    
    @Published var isInspecting: Bool = false
    @Published var isLocked: Bool = false
    @Published var highlightOnScreen: Bool = true
    
    @Published var currentMousePosition: CGPoint = .zero
    @Published var targetApp: TargetAppInfo?
    @Published var currentElement: AXElementNode?
    @Published var hierarchy: [AXElementNode] = []
    @Published var children: [AXElementNode] = []
    @Published var attributes: [(key: String, value: String)] = []
    @Published var actions: [String] = []
    
    @Published var statusMessage: String = "Ready to inspect"
    @Published var lastActionStatus: String? = nil
    
    private var trackingTimer: Timer?
    private var overlayWindow: AXHighlightOverlayWindow?
    
    private init() {
        setupOverlay()
    }
    
    private func setupOverlay() {
        overlayWindow = AXHighlightOverlayWindow()
    }
    
    func startInspecting() {
        guard !isInspecting else { return }
        isInspecting = true
        isLocked = false
        statusMessage = "Tracking mouse cursor… (Press Space or click Lock to freeze)"
        
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isLocked {
                self.inspectAtCurrentCursor()
            }
        }
    }
    
    func stopInspecting() {
        isInspecting = false
        trackingTimer?.invalidate()
        trackingTimer = nil
        overlayWindow?.orderOut(nil)
        statusMessage = "Inspection stopped"
    }
    
    func toggleInspection() {
        if isInspecting {
            stopInspecting()
        } else {
            startInspecting()
        }
    }
    
    func toggleLock() {
        isLocked.toggle()
        if isLocked {
            statusMessage = "🔒 Frozen on element. You can now explore attributes or click actions."
        } else {
            statusMessage = "Tracking mouse cursor…"
        }
    }
    
    func inspectAtCurrentCursor() {
        let cursorLoc = CGEvent(source: nil)?.location ?? .zero
        DispatchQueue.main.async {
            self.currentMousePosition = cursorLoc
        }
        inspectElement(at: cursorLoc)
    }
    
    func inspectElement(at quartzPoint: CGPoint) {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(quartzPoint.x), Float(quartzPoint.y), &elementRef)
        guard result == .success, let element = elementRef else {
            DispatchQueue.main.async {
                if !self.isLocked {
                    self.overlayWindow?.orderOut(nil)
                }
            }
            return
        }
        
        parseElement(element)
    }
    
    func parseElement(_ element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        
        // App Info
        var appInfo: TargetAppInfo? = nil
        if pid > 0, let runningApp = NSRunningApplication(processIdentifier: pid) {
            appInfo = TargetAppInfo(
                pid: pid,
                name: runningApp.localizedName ?? "Process \(pid)",
                bundleIdentifier: runningApp.bundleIdentifier,
                icon: runningApp.icon,
                executableURL: runningApp.executableURL
            )
        }
        
        let node = makeNode(for: element, pid: pid)
        let chain = fetchHierarchy(for: element, pid: pid)
        let elementChildren = fetchChildren(for: element, pid: pid)
        let elementAttrs = fetchAllAttributes(for: element)
        let elementActions = fetchActions(for: element)
        
        DispatchQueue.main.async {
            self.targetApp = appInfo
            self.currentElement = node
            self.hierarchy = chain
            self.children = elementChildren
            self.attributes = elementAttrs
            self.actions = elementActions
            
            if self.highlightOnScreen, let frame = node.frame, frame.width > 0, frame.height > 0 {
                self.overlayWindow?.updateFrame(for: frame)
            } else {
                self.overlayWindow?.orderOut(nil)
            }
        }
    }
    
    func selectHierarchyNode(_ node: AXElementNode) {
        parseElement(node.element)
    }
    
    // MARK: - Action Execution
    func performAction(_ actionName: String) {
        guard let node = currentElement else { return }
        let result = AXUIElementPerformAction(node.element, actionName as CFString)
        if result == .success {
            lastActionStatus = "Action '\(actionName)' executed successfully!"
        } else {
            lastActionStatus = "Failed to perform '\(actionName)' (Error: \(result.rawValue))"
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.lastActionStatus = nil
        }
    }
    
    // MARK: - Element Helpers
    private func makeNode(for element: AXUIElement, pid: pid_t) -> AXElementNode {
        let role = getStringAttribute(kAXRoleAttribute, from: element) ?? "AXUnknown"
        let subrole = getStringAttribute(kAXSubroleAttribute, from: element)
        let title = getStringAttribute(kAXTitleAttribute, from: element)
        let description = getStringAttribute(kAXDescriptionAttribute, from: element)
        let value = getStringAttribute(kAXValueAttribute, from: element)
        let identifier = getStringAttribute(kAXIdentifierAttribute, from: element)
        let frame = getRectAttribute(from: element)
        
        return AXElementNode(
            element: element,
            role: role,
            subrole: subrole,
            title: title,
            description: description,
            value: value,
            identifier: identifier,
            frame: frame,
            pid: pid
        )
    }
    
    private func fetchHierarchy(for element: AXUIElement, pid: pid_t) -> [AXElementNode] {
        var list: [AXElementNode] = []
        var current: AXUIElement? = element
        var depth = 0
        
        while let el = current, depth < 15 {
            let node = makeNode(for: el, pid: pid)
            list.insert(node, at: 0)
            
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef {
                current = (parent as! AXUIElement)
            } else {
                current = nil
            }
            depth += 1
        }
        return list
    }
    
    private func fetchChildren(for element: AXUIElement, pid: pid_t) -> [AXElementNode] {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard result == .success, let list = childrenRef as? [AXUIElement] else {
            return []
        }
        return list.prefix(50).map { makeNode(for: $0, pid: pid) }
    }
    
    private func fetchActions(for element: AXUIElement) -> [String] {
        var actionsRef: CFArray?
        let result = AXUIElementCopyActionNames(element, &actionsRef)
        guard result == .success, let list = actionsRef as? [String] else {
            return []
        }
        return list
    }
    
    private func fetchAllAttributes(for element: AXUIElement) -> [(key: String, value: String)] {
        var namesRef: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &namesRef)
        guard result == .success, let names = namesRef as? [String] else {
            return []
        }
        
        var list: [(key: String, value: String)] = []
        for name in names.sorted() {
            var valRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, name as CFString, &valRef) == .success, let val = valRef {
                let formatted = formatAttributeValue(val)
                list.append((key: name, value: formatted))
            }
        }
        return list
    }
    
    private func formatAttributeValue(_ value: CFTypeRef) -> String {
        let typeID = CFGetTypeID(value)
        
        if typeID == CFStringGetTypeID() {
            return "\(value as! String)"
        } else if typeID == CFBooleanGetTypeID() {
            return (value as! CFBoolean) == kCFBooleanTrue ? "true" : "false"
        } else if typeID == CFNumberGetTypeID() {
            return "\(value)"
        } else if typeID == AXValueGetTypeID() {
            let axVal = value as! AXValue
            let axType = AXValueGetType(axVal)
            switch axType {
            case .cgPoint:
                var pt = CGPoint.zero
                AXValueGetValue(axVal, .cgPoint, &pt)
                return "CGPoint(x: \(Int(pt.x)), y: \(Int(pt.y)))"
            case .cgSize:
                var sz = CGSize.zero
                AXValueGetValue(axVal, .cgSize, &sz)
                return "CGSize(w: \(Int(sz.width)), h: \(Int(sz.height)))"
            case .cgRect:
                var rc = CGRect.zero
                AXValueGetValue(axVal, .cgRect, &rc)
                return "CGRect(x: \(Int(rc.origin.x)), y: \(Int(rc.origin.y)), w: \(Int(rc.size.width)), h: \(Int(rc.size.height)))"
            default:
                return "AXValue<\(axType)>"
            }
        } else if typeID == AXUIElementGetTypeID() {
            let el = value as! AXUIElement
            let role = getStringAttribute(kAXRoleAttribute, from: el) ?? "AXUIElement"
            let title = getStringAttribute(kAXTitleAttribute, from: el)
            if let t = title, !t.isEmpty {
                return "<\(role): \"\(t)\">"
            }
            return "<\(role)>"
        } else if typeID == CFArrayGetTypeID() {
            let arr = value as! NSArray
            return "[\(arr.count) items]"
        }
        return "\(value)"
    }
    
    private func getStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var valRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valRef) == .success,
              let val = valRef else {
            return nil
        }
        if CFGetTypeID(val) == CFStringGetTypeID() {
            return val as? String
        }
        return nil
    }
    
    private func getRectAttribute(from element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pVal = posRef, let sVal = sizeRef,
              CFGetTypeID(pVal) == AXValueGetTypeID(),
              CFGetTypeID(sVal) == AXValueGetTypeID() else {
            return nil
        }
        
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pVal as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sVal as! AXValue, .cgSize, &size)
        
        return CGRect(origin: origin, size: size)
    }
    
    // MARK: - Code & Snippet Generators
    func generateAppleScriptSnippet() -> String {
        guard let app = targetApp else { return "-- No application selected" }
        let appName = app.name
        
        if let node = currentElement {
            let role = node.role
            let title = node.title ?? ""
            
            if role == "AXMenuItem" {
                return """
                tell application "System Events"
                    tell process "\(appName)"
                        -- Click context menu or menu item
                        click menu item "\(title)" of menu 1
                    end tell
                end tell
                """
            } else if role == "AXButton" {
                return """
                tell application "System Events"
                    tell process "\(appName)"
                        click button "\(title)" of window 1
                    end tell
                end tell
                """
            }
        }
        
        return """
        tell application "System Events"
            tell process "\(appName)"
                -- Target UI Element
                get properties of (first UI element whose role is "\(currentElement?.role ?? "AXUIElement")")
            end tell
        end tell
        """
    }
    
    func generateSwiftSnippet() -> String {
        guard let app = targetApp, let node = currentElement else { return "// No element selected" }
        let title = node.title ?? ""
        let role = node.role
        
        return """
        // Swift Accessibility interaction for \(app.name) (PID: \(app.pid))
        let appRef = AXUIElementCreateApplication(\(app.pid))
        // Target: \(role) "\(title)"
        """
    }
}
