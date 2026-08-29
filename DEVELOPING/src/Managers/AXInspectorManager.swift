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
struct TargetAppInfo: Identifiable, Hashable {
    let id: pid_t
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let executableURL: URL?
    
    init(pid: pid_t, name: String, bundleIdentifier: String?, icon: NSImage?, executableURL: URL?) {
        self.id = pid
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
        self.executableURL = executableURL
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
    
    static func == (lhs: TargetAppInfo, rhs: TargetAppInfo) -> Bool {
        return lhs.pid == rhs.pid
    }
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
    @Published var isAccessibilityGranted: Bool = true
    
    @Published var currentMousePosition: CGPoint = .zero
    @Published var targetApp: TargetAppInfo?
    @Published var runningApps: [TargetAppInfo] = []
    @Published var selectedAppPID: pid_t? = nil
    
    @Published var currentElement: AXElementNode?
    @Published var hierarchy: [AXElementNode] = []
    @Published var children: [AXElementNode] = []
    @Published var attributes: [(key: String, value: String)] = []
    @Published var actions: [String] = []
    
    @Published var statusMessage: String = "Ready to inspect"
    @Published var lastActionStatus: String? = nil
    
    private var trackingTimer: Timer?
    private var overlayWindow: AXHighlightOverlayWindow?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    
    private init() {
        setupOverlay()
        checkAccessibility()
        refreshRunningApps()
    }
    
    private func setupOverlay() {
        overlayWindow = AXHighlightOverlayWindow()
    }
    
    func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            self.isAccessibilityGranted = trusted
        }
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func refreshRunningApps() {
        let currentPID = NSRunningApplication.current.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != currentPID }
            .map { app in
                TargetAppInfo(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? "PID \(app.processIdentifier)",
                    bundleIdentifier: app.bundleIdentifier,
                    icon: app.icon,
                    executableURL: app.executableURL
                )
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        
        DispatchQueue.main.async {
            self.runningApps = apps
        }
    }
    
    func startInspecting() {
        guard !isInspecting else { return }
        checkAccessibility()
        isInspecting = true
        isLocked = false
        refreshRunningApps()
        installKeyMonitors()
        statusMessage = "Tracking mouse cursor… (Press F10 to freeze inspection)"
        
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
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
        removeKeyMonitors()
        overlayWindow?.orderOut(nil)
        statusMessage = "Inspection paused"
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
            statusMessage = "🔒 Frozen on element. (Press F10 to unfreeze)"
        } else {
            statusMessage = "Tracking mouse cursor… (Press F10 to freeze)"
        }
    }
    
    // MARK: - Low-Level Global CGEventTap & Monitors for F10 (System-Wide Kernel Override)
    private var inspectorEventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private func installKeyMonitors() {
        removeKeyMonitors()
        
        // 1. Carbon OS-Level Global HotKey Override for F10 (Keycode 109)
        CarbonHotKeyManager.shared.registerInspectorF10 { [weak self] in
            self?.toggleLock()
        }
        
        // 2. Local monitor when ShortKing / Inspector is focused
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isInspecting else { return event }
            if event.keyCode == 109 { // F10
                self.toggleLock()
                return nil // consume event so it doesn't trigger UI controls
            }
            return event
        }
        
        // 3. Low-Level CGEventTap to intercept F10 at kernel/driver level across any application
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << 14) // keyDown + NX_SYSDEFINED
        inspectorEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = AXInspectorManager.shared.inspectorEventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                
                if type == .keyDown {
                    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                    if keycode == 109 { // F10
                        DispatchQueue.main.async {
                            AXInspectorManager.shared.toggleLock()
                        }
                        return nil // Swallow F10 globally so no other app receives it!
                    }
                } else if type.rawValue == 14 { // NX_SYSDEFINED (Media / hardware key)
                    if let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
                        let data1 = nsEvent.data1
                        let keyType = (data1 & 0xFFFF0000) >> 16
                        let keyState = (data1 & 0xFF00) >> 8
                        let isKeyDown = (keyState == 0xa)
                        if isKeyDown && keyType == 7 { // NX_KEYTYPE_MUTE (F10 on Mac Keyboard)
                            DispatchQueue.main.async {
                                AXInspectorManager.shared.toggleLock()
                            }
                            return nil // Swallow
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        
        if let tap = inspectorEventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    private func removeKeyMonitors() {
        CarbonHotKeyManager.shared.unregisterInspectorF10()
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = inspectorEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            inspectorEventTap = nil
        }
        
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
        if let m = globalKeyMonitor {
            NSEvent.removeMonitor(m)
            globalKeyMonitor = nil
        }
    }
    
    func inspectAtCurrentCursor() {
        let mouseLoc = NSEvent.mouseLocation
        let primaryScreenH = NSScreen.screens.first?.frame.height ?? 1080
        let quartzPoint = CGPoint(x: mouseLoc.x, y: primaryScreenH - mouseLoc.y)
        
        DispatchQueue.main.async {
            self.currentMousePosition = quartzPoint
        }
        
        inspectElement(at: quartzPoint)
    }
    
    func inspectFrontmostApp() {
        let currentPID = NSRunningApplication.current.processIdentifier
        guard let frontApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.isActive && $0.processIdentifier != currentPID
        }) ?? NSWorkspace.shared.frontmostApplication else {
            return
        }
        
        inspectApp(pid: frontApp.processIdentifier)
    }
    
    func inspectApp(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowRef: CFTypeRef?
        var targetElement: AXUIElement = appElement
        
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
           let win = focusedWindowRef {
            targetElement = (win as! AXUIElement)
            
            var focusedElemRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(targetElement, kAXFocusedUIElementAttribute as CFString, &focusedElemRef) == .success,
               let elem = focusedElemRef {
                targetElement = (elem as! AXUIElement)
            }
        }
        
        parseElement(targetElement)
    }
    
    func inspectElement(at quartzPoint: CGPoint) {
        var foundElement: AXUIElement? = nil
        
        // 1. Primary Method: SystemWide Copy Element At Position
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let sysResult = AXUIElementCopyElementAtPosition(systemWide, Float(quartzPoint.x), Float(quartzPoint.y), &elementRef)
        if sysResult == .success, let el = elementRef {
            foundElement = el
        }
        
        // 2. Secondary Method: Window owner PID query if SystemWide missed or returned empty
        if foundElement == nil {
            if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                for win in windowList {
                    guard let boundsDict = win[kCGWindowBounds as String] as? [String: Any],
                          let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                          let pid = win[kCGWindowOwnerPID as String] as? pid_t,
                          pid > 0 else { continue }
                    
                    if bounds.contains(quartzPoint) {
                        let appElem = AXUIElementCreateApplication(pid)
                        var appElRef: AXUIElement?
                        if AXUIElementCopyElementAtPosition(appElem, Float(quartzPoint.x), Float(quartzPoint.y), &appElRef) == .success,
                           let el = appElRef {
                            foundElement = el
                            break
                        }
                    }
                }
            }
        }
        
        // 3. Fallback: Frontmost Application
        if foundElement == nil, let frontApp = NSWorkspace.shared.frontmostApplication {
            let appElem = AXUIElementCreateApplication(frontApp.processIdentifier)
            var appElRef: AXUIElement?
            if AXUIElementCopyElementAtPosition(appElem, Float(quartzPoint.x), Float(quartzPoint.y), &appElRef) == .success,
               let el = appElRef {
                foundElement = el
            }
        }
        
        guard let element = foundElement else {
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
    
    // MARK: - Code & Natural Language Snippet Generators
    func generateNaturalLanguagePrompt() -> String {
        guard let node = currentElement else {
            return "No UI element selected. Hover cursor over any element and press Spacebar to freeze."
        }
        
        let appName = targetApp?.name ?? "Target Application"
        let bundleID = targetApp?.bundleIdentifier ?? "N/A"
        let pid = targetApp?.pid ?? 0
        
        var hierarchyPath: [String] = []
        for item in hierarchy {
            if let t = item.title, !t.isEmpty {
                hierarchyPath.append("\(item.roleShort) \"\(t)\"")
            } else if let sub = item.subrole, !sub.isEmpty {
                hierarchyPath.append("\(item.roleShort) (\(sub.replacingOccurrences(of: "AX", with: "")))")
            } else {
                hierarchyPath.append(item.roleShort)
            }
        }
        let pathString = hierarchyPath.isEmpty ? node.displayName : hierarchyPath.joined(separator: " > ")
        
        var coordCenter = "X: \(Int(currentMousePosition.x)), Y: \(Int(currentMousePosition.y))"
        var boundsText = "Unavailable"
        
        if let f = node.frame {
            coordCenter = "X: \(Int(f.midX)), Y: \(Int(f.midY))"
            boundsText = "x: \(Int(f.origin.x)), y: \(Int(f.origin.y)), w: \(Int(f.width)), h: \(Int(f.height))"
        }
        
        let actionsList = actions.isEmpty ? "Click" : actions.joined(separator: ", ")
        let titleStr = (node.title != nil && !node.title!.isEmpty) ? "\"\(node.title!)\"" : "None"
        let descStr = (node.description != nil && !node.description!.isEmpty) ? "\"\(node.description!)\"" : "None"
        let idStr = (node.identifier != nil && !node.identifier!.isEmpty) ? "\"\(node.identifier!)\"" : "None"
        
        return """
        Target UI Element for Automation / Keyboard Shortcut:
        - Application: \(appName) (Bundle: \(bundleID), PID: \(pid))
        - UI Element: \(node.role) \(node.displayName)
        - Title / Label: \(titleStr)
        - Description: \(descStr)
        - Accessibility Identifier: \(idStr)
        - Full Hierarchy: \(pathString)
        - Exact Screen Coordinates: Center (\(coordCenter)) | Bounds [\(boundsText)]
        - Available Actions: \(actionsList)

        Instructions:
        To automate or create a shortcut directing to this element, target application '\(appName)', follow the hierarchy path '\(pathString)', and trigger action '\(actions.first ?? "AXPress")' or click at screen coordinates (\(coordCenter)).
        """
    }
    
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
