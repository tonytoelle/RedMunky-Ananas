import Cocoa
import Foundation
import SwiftUI
import Combine

class DropShelfWindow: NSPanel {
    init(contentView: NSView, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
    @Published var heldItems: [String] = [] // Holds file paths
    
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
        }
    }
}
