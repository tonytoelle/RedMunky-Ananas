import Cocoa
import Foundation
import SwiftUI
import Combine

class DropShelfWindow: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    
    init(contentView: NSView, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.hidesOnDeactivate = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovable = true
        self.isMovableByWindowBackground = false
        self.minSize = NSSize(width: 200, height: 264)
        self.maxSize = NSSize(width: 800, height: 800)
        self.contentView = contentView
        self.invalidateShadow()
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if !self.isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
        }
    }
}

class DropShelfManager: ObservableObject {
    static let shared = DropShelfManager()
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "enableDropShelf")
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
                closeShelf()
            }
        }
    }
    
    @Published var shelfWindow: DropShelfWindow? = nil
    @Published var heldItems: [String] = [] {
        didSet {
            updateDockTile()
        }
    }
    
    // Virtual folder hierarchy mapping
    @Published var virtualFolderNames: [String: String] = [:]       // "virtual://UUID" -> "My Folder"
    @Published var virtualFolderChildren: [String: [String]] = [:]   // "virtual://UUID" -> [item paths or sub-folder IDs]
    
    func isVirtualFolder(_ path: String) -> Bool {
        return path.hasPrefix("virtual://")
    }
    
    func displayName(for path: String) -> String {
        if isVirtualFolder(path) {
            return virtualFolderNames[path] ?? "New Folder"
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    
    func createVirtualFolder(name: String = "New Folder", inside parentId: String? = nil) -> String {
        objectWillChange.send()
        let uniqueId = "virtual://\(UUID().uuidString)"
        
        // Find non-conflicting name
        let existingChildren = parentId != nil ? (virtualFolderChildren[parentId!] ?? []) : heldItems
        var folderName = name
        var counter = 1
        let existingNames = existingChildren.map { displayName(for: $0) }
        while existingNames.contains(folderName) {
            folderName = "\(name) \(counter)"
            counter += 1
        }
        
        virtualFolderNames[uniqueId] = folderName
        virtualFolderChildren[uniqueId] = []
        
        if let parent = parentId {
            var children = virtualFolderChildren[parent] ?? []
            children.append(uniqueId)
            virtualFolderChildren[parent] = children
        } else {
            heldItems.append(uniqueId)
        }
        return uniqueId
    }
    
    func moveItems(_ items: [String], into targetFolderId: String, currentFolderId: String?) {
        guard isVirtualFolder(targetFolderId) else { return }
        objectWillChange.send()
        var targetChildren = virtualFolderChildren[targetFolderId] ?? []
        
        for item in items {
            guard item != targetFolderId else { continue }
            if !targetChildren.contains(item) {
                targetChildren.append(item)
            }
            
            // Remove from current level
            if let current = currentFolderId {
                virtualFolderChildren[current]?.removeAll { $0 == item }
            } else {
                heldItems.removeAll { $0 == item }
            }
        }
        virtualFolderChildren[targetFolderId] = targetChildren
    }
    
    func removeItems(_ paths: [String], currentFolderId: String?) {
        objectWillChange.send()
        for path in paths {
            if let current = currentFolderId {
                virtualFolderChildren[current]?.removeAll { $0 == path }
            } else {
                heldItems.removeAll { $0 == path }
            }
            if isVirtualFolder(path) {
                virtualFolderNames.removeValue(forKey: path)
                virtualFolderChildren.removeValue(forKey: path)
            }
        }
    }
    
    func allContainedRealFilePaths(in path: String) -> [String] {
        if isVirtualFolder(path) {
            var result: [String] = []
            let children = virtualFolderChildren[path] ?? []
            for child in children {
                result.append(contentsOf: allContainedRealFilePaths(in: child))
            }
            return result
        } else {
            return [path]
        }
    }
    
    func stageVirtualFolderForDrag(virtualFolderId: String) -> (stagingURL: URL, originalFiles: [String]) {
        let folderName = displayName(for: virtualFolderId)
        let sessionUUID = UUID().uuidString
        let baseStagingDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("RedMunkyAnanasTransit_\(sessionUUID)", isDirectory: true)
        let folderURL = baseStagingDir.appendingPathComponent(folderName, isDirectory: true)
        
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        var originalFiles: [String] = []
        
        func populate(folderId: String, targetDir: URL) {
            let children = virtualFolderChildren[folderId] ?? []
            for child in children {
                if isVirtualFolder(child) {
                    let subName = displayName(for: child)
                    let subDir = targetDir.appendingPathComponent(subName, isDirectory: true)
                    try? FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
                    populate(folderId: child, targetDir: subDir)
                } else {
                    originalFiles.append(child)
                    let srcURL = URL(fileURLWithPath: child)
                    var destURL = targetDir.appendingPathComponent(srcURL.lastPathComponent)
                    
                    var counter = 1
                    let base = srcURL.deletingPathExtension().lastPathComponent
                    let ext = srcURL.pathExtension
                    while FileManager.default.fileExists(atPath: destURL.path) {
                        let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                        destURL = targetDir.appendingPathComponent(name)
                        counter += 1
                    }
                    
                    // Try hardlink first (instant zero-copy), fallback to copyItem
                    if (try? FileManager.default.linkItem(at: srcURL, to: destURL)) == nil {
                        try? FileManager.default.copyItem(at: srcURL, to: destURL)
                    }
                }
            }
        }
        
        populate(folderId: virtualFolderId, targetDir: folderURL)
        return (folderURL, originalFiles)
    }
    
    func updateDockTile() {
        DispatchQueue.main.async {
            if self.heldItems.isEmpty {
                NSApp.dockTile.badgeLabel = nil
            } else {
                NSApp.dockTile.badgeLabel = "\(self.heldItems.count)"
            }
            NSApp.dockTile.display()
        }
    }
    
    private var globalDragMonitor: Any? = nil
    private var localDragMonitor: Any? = nil
    private var mouseUpMonitor: Any? = nil
    
    private var lastMousePoint: CGPoint = .zero
    private var lastDirection: Int = 0 // -1 = left, 1 = right, 0 = stationary
    private var directionChanges: [Date] = []
    
    init() {
        let saved = UserDefaults.standard.object(forKey: "enableDropShelf") as? Bool ?? true
        self.isEnabled = saved
    }
    
    func startMonitoring() {
        guard isEnabled else { return }
        stopMonitoring()
        
        // Monitor global drags (drags starting from other apps like Finder)
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDrag(event: event)
        }
        
        // Monitor local drags (drags within ShortKing)
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDrag(event: event)
            return event
        }
        
        // Monitor mouse up globally to reset wiggling gesture tracking
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.resetWiggleState()
            return event
        }
    }
    
    func stopMonitoring() {
        if let monitor = globalDragMonitor { NSEvent.removeMonitor(monitor); globalDragMonitor = nil }
        if let monitor = localDragMonitor { NSEvent.removeMonitor(monitor); localDragMonitor = nil }
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor); mouseUpMonitor = nil }
    }
    
    private func handleDrag(event: NSEvent) {
        let currentPoint = NSEvent.mouseLocation
        defer { lastMousePoint = currentPoint }
        
        guard lastMousePoint != .zero else { return }
        
        let dx = currentPoint.x - lastMousePoint.x
        // Filter out extremely tiny movements to avoid noise
        guard abs(dx) > 4 else { return }
        
        let direction = dx > 0 ? 1 : -1
        
        if lastDirection != 0 && direction != lastDirection {
            // Direction of movement changed!
            let now = Date()
            directionChanges.append(now)
            
            // Keep only changes within the last 0.6 seconds
            directionChanges = directionChanges.filter { now.timeIntervalSince($0) < 0.6 }
            
            if directionChanges.count >= 4 {
                // Wiggle detected! Show the shelf window near the cursor as an empty drop zone
                showShelf(near: currentPoint)
                directionChanges.removeAll()
            }
        }
        
        lastDirection = direction
    }
    
    private func resetWiggleState() {
        directionChanges.removeAll()
        lastDirection = 0
        lastMousePoint = .zero
    }
    
    func showShelf(near point: CGPoint) {
        guard shelfWindow == nil else { return }
        
        // Shelf starts empty waiting for drop
        self.heldItems = []
        
        let initialSize = NSSize(width: 200, height: 264)
        let origin = CGPoint(x: point.x - initialSize.width/2 + 25, y: point.y - initialSize.height/2 + 25)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let hostView = NSHostingView(rootView: DropShelfView(manager: self))
            let win = DropShelfWindow(contentView: hostView, size: initialSize)
            win.setFrameOrigin(origin)
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            self.shelfWindow = win
        }
    }
    
    func expandWindow(width: CGFloat, height: CGFloat) {
        guard let window = shelfWindow else { return }
        var frame = window.frame
        let deltaH = height - frame.height
        frame.size.width = width
        frame.size.height = height
        frame.origin.y -= deltaH // keep top-left pinned
        window.animator().setFrame(frame, display: true)
    }
    
    func closeShelf() {
        DispatchQueue.main.async { [weak self] in
            self?.shelfWindow?.orderOut(nil)
            self?.shelfWindow = nil
            self?.heldItems.removeAll()
            self?.virtualFolderNames.removeAll()
            self?.virtualFolderChildren.removeAll()
        }
    }
}
