import Cocoa
import Foundation
import SwiftUI
import Combine

class DropShelfWindow: NSPanel {
    init(contentView: NSView, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.contentView = contentView
    }
}

class DropShelfManager: ObservableObject {
    static let shared = DropShelfManager()
    
    @Published var shelfWindow: DropShelfWindow? = nil
    @Published var heldItems: [String] = [] // Holds file paths or macro paths
    
    private var globalDragMonitor: Any? = nil
    private var localDragMonitor: Any? = nil
    private var mouseUpMonitor: Any? = nil
    
    private var lastMousePoint: CGPoint = .zero
    private var lastDirection: Int = 0 // -1 = left, 1 = right, 0 = stationary
    private var directionChanges: [Date] = []
    
    func startMonitoring() {
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
        if let monitor = globalDragMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localDragMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor) }
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
                // Wiggle detected! Show the shelf window near the cursor
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
        
        let size = NSSize(width: 180, height: 180)
        // Position window offset slightly so it spawns next to cursor rather than directly under it
        let origin = CGPoint(x: point.x - size.width/2 + 25, y: point.y - size.height/2 + 25)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let hostView = NSHostingView(rootView: DropShelfView(manager: self))
            let win = DropShelfWindow(contentView: hostView, size: size)
            win.setFrameOrigin(origin)
            win.makeKeyAndOrderFront(nil)
            
            self.shelfWindow = win
        }
    }
    
    func closeShelf() {
        DispatchQueue.main.async { [weak self] in
            self?.shelfWindow?.orderOut(nil)
            self?.shelfWindow = nil
            self?.heldItems.removeAll()
        }
    }
}
