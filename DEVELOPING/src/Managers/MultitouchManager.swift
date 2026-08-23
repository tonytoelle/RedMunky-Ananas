import Foundation
import Cocoa
import Carbon

// Private MultitouchSupport structure definitions
struct MTPoint {
    var x: Float
    var y: Float
}

struct MTVector {
    var x: Float
    var y: Float
}

struct MTContact {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var size: Float
    var zero1: Int32
    var x: Float
    var y: Float
    var zero2: Int32
    var vx: Float
    var vy: Float
    var n1: Float
    var n2: Float
    var orientation: Float
    var surfaceArea: Float
    var pressure: Float
    var zero3: Int32
    var zero4: Int32
    var zero5: Int32
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallbackFunction = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

class MultitouchManager: ObservableObject {
    static let shared = MultitouchManager()
    
    private var devices: [MTDeviceRef] = []
    private var isListening = false
    
    // Tracking active touch state
    private static var activeTouches: [Int32: (startTime: Double, startX: Float, startY: Float)] = [:]
    private static var lastTapTime: Double = 0
    private static var maxFingerCountDuringGesture = 0
    
    // Load Private APIs
    private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias MTRegisterContactFrameCallbackFn = @convention(c) (MTDeviceRef?, MTContactCallbackFunction?) -> Void
    private typealias MTDeviceStartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
    private typealias MTDeviceStopFn = @convention(c) (MTDeviceRef?) -> Void
    
    private var MTDeviceCreateList: MTDeviceCreateListFn?
    private var MTRegisterContactFrameCallback: MTRegisterContactFrameCallbackFn?
    private var MTDeviceStart: MTDeviceStartFn?
    private var MTDeviceStop: MTDeviceStopFn?
    
    init() {
        loadMultitouchFramework()
    }
    
    private func loadMultitouchFramework() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            print("❌ MultitouchSupport.framework failed to load")
            return
        }
        
        if let sym = dlsym(handle, "MTDeviceCreateList") {
            MTDeviceCreateList = unsafeBitCast(sym, to: MTDeviceCreateListFn.self)
        }
        if let sym = dlsym(handle, "MTRegisterContactFrameCallback") {
            MTRegisterContactFrameCallback = unsafeBitCast(sym, to: MTRegisterContactFrameCallbackFn.self)
        }
        if let sym = dlsym(handle, "MTDeviceStart") {
            MTDeviceStart = unsafeBitCast(sym, to: MTDeviceStartFn.self)
        }
        if let sym = dlsym(handle, "MTDeviceStop") {
            MTDeviceStop = unsafeBitCast(sym, to: MTDeviceStopFn.self)
        }
        print("✅ MultitouchSupport APIs loaded successfully")
    }
    
    func startListening() {
        guard !isListening else { return }
        guard let MTDeviceCreateList = MTDeviceCreateList,
              let MTRegisterContactFrameCallback = MTRegisterContactFrameCallback,
              let MTDeviceStart = MTDeviceStart else { 
            print("❌ Multitouch APIs not fully loaded")
            return 
        }
        
        guard let unmanagedList = MTDeviceCreateList() else {
            print("❌ MTDeviceCreateList returned nil")
            return
        }
        
        let cfList = unmanagedList.takeRetainedValue()
        let count = CFArrayGetCount(cfList)
        print("🔍 Found \(count) potential multitouch devices")
        
        var deviceList: [MTDeviceRef] = []
        for i in 0..<count {
            if let ptr = CFArrayGetValueAtIndex(cfList, i) {
                deviceList.append(UnsafeMutableRawPointer(mutating: ptr))
            }
        }
        
        self.devices = deviceList
        
        for device in deviceList {
            MTRegisterContactFrameCallback(device, { (device, contactsRaw, numContacts, timestamp, frame) -> Int32 in
                MultitouchManager.handleTouchCallback(device: device, contactsRaw: contactsRaw, numContacts: numContacts, timestamp: timestamp, frame: frame)
                return 0
            })
            MTDeviceStart(device, 0)
        }
        isListening = true
        print("👆 Started tracking Multitouch Trackpad with \(deviceList.count) devices")
    }
    
    func stopListening() {
        guard isListening else { return }
        guard let MTDeviceStop = MTDeviceStop else { return }
        
        for device in devices {
            MTDeviceStop(device)
        }
        self.devices.removeAll()
        isListening = false
        print("👆 Stopped tracking Multitouch Trackpad")
    }
    
    // Core callback for touch frame processing
    private static func handleTouchCallback(device: MTDeviceRef?, contactsRaw: UnsafeMutableRawPointer?, numContacts: Int32, timestamp: Double, frame: Int32) {
        guard let contactsRaw = contactsRaw else { return }
        let contacts = contactsRaw.assumingMemoryBound(to: MTContact.self)
        
        let count = Int(numContacts)
        if count > 0 {
            maxFingerCountDuringGesture = max(maxFingerCountDuringGesture, count)
        }
        
        var currentIDs = Set<Int32>()
        
        for i in 0..<count {
            let contact = contacts[i]
            let id = contact.identifier
            currentIDs.insert(id)
            
            // State: 1 = Hover, 2 = Touch/Hold, 3 = Move, 4 = Release, 5 = Lift
            // If contact is newly placed on trackpad
            if activeTouches[id] == nil && (contact.state == 2 || contact.state == 3) {
                activeTouches[id] = (startTime: timestamp, startX: contact.x, startY: contact.y)
            }
        }
        
        // Check for finger releases (IDs that were active but are no longer in contact)
        for id in Array(activeTouches.keys) {
            if !currentIDs.contains(id) {
                if let touch = activeTouches[id] {
                    let duration = timestamp - touch.startTime
                    
                    // Filter out touches that were active for too long (must be a quick tap < 0.25 seconds)
                    if duration < 0.25 {
                        // Check if we just completed a gesture where max 3 fingers were touching
                        if maxFingerCountDuringGesture == 3 {
                            // Ensure it's not registered multiple times for each finger release
                            let timeSinceLastTap = timestamp - lastTapTime
                            if timeSinceLastTap > 0.3 {
                                lastTapTime = timestamp
                                triggerMiddleClick()
                            }
                        }
                    }
                }
                activeTouches.removeValue(forKey: id)
            }
        }
        
        // Reset gesture fingerprint when all fingers are off the trackpad
        if currentIDs.isEmpty {
            maxFingerCountDuringGesture = 0
        }
    }
    
    private static func triggerMiddleClick() {
        DispatchQueue.global(qos: .userInteractive).async {
            // Get current mouse location
            let cp = NSEvent.mouseLocation
            let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
            let clickPt = CGPoint(x: cp.x, y: screenHeight - cp.y)
            
            let source = CGEventSource(stateID: .hidSystemState)
            
            // Post Middle Click Down (Button: Center/2)
            let d = CGEvent(mouseEventSource: source, mouseType: .otherMouseDown, mouseCursorPosition: clickPt, mouseButton: .center)
            d?.post(tap: .cghidEventTap)
            
            usleep(15000) // 15ms click hold duration
            
            // Post Middle Click Up (Button: Center/2)
            let u = CGEvent(mouseEventSource: source, mouseType: .otherMouseUp, mouseCursorPosition: clickPt, mouseButton: .center)
            u?.post(tap: .cghidEventTap)
            
            print("🖱️ Multitouch Middle Click executed at \(clickPt)")
        }
    }
}
