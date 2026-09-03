import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

class CarbonHotKeyManager {
    static let shared = CarbonHotKeyManager()

    private var registeredRefs: [UInt32: EventHotKeyRef] = [:]
    private var actionClosures: [UInt32: () -> Void] = [:]
    private var isHandlerInstalled = false
    private var currentID: UInt32 = 100
    private var emergencyRef: EventHotKeyRef?
    private let lock = NSLock()

    func installHandlerIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !isHandlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), carbonHotKeyCallback, 1, &eventType, nil, nil)
        isHandlerInstalled = true
        registerEmergencyKillSwitch()
    }

    func registerEmergencyKillSwitch() {
        let eID = EventHotKeyID(signature: OSType(0x4B494C4C), id: 9999)
        RegisterEventHotKey(7, UInt32(cmdKey | shiftKey | controlKey), eID, GetApplicationEventTarget(), 0, &emergencyRef)
        print("🛑 [Emergency] Cmd+Ctrl+Shift+X aktif")
    }

    func unregisterAll() {
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { self.unregisterAll() }
            return
        }
        lock.lock()
        let refs = Array(registeredRefs.values)
        registeredRefs.removeAll()
        actionClosures.removeAll()
        lock.unlock()
        
        refs.forEach { UnregisterEventHotKey($0) }
    }

    func register(trigger: Trigger, action: @escaping () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.register(trigger: trigger, action: action) }
            return
        }
        installHandlerIfNeeded()
        var mods: UInt32 = 0
        if trigger.requireCmd     { mods |= UInt32(cmdKey) }
        if trigger.requireShift   { mods |= UInt32(shiftKey) }
        if trigger.requireOption  { mods |= UInt32(optionKey) }
        if trigger.requireControl { mods |= UInt32(controlKey) }

        lock.lock()
        let id = currentID
        currentID += 1
        lock.unlock()

        let hkID = EventHotKeyID(signature: OSType(0x534B494E), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(trigger.keyCode), mods, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            lock.lock()
            registeredRefs[id] = ref
            actionClosures[id] = action
            lock.unlock()
            print("👑 HotKey registered: \(trigger.displayString) [ID:\(id)]")
        } else {
            print("⚠️ HotKey FAILED: \(trigger.displayString) OSStatus=\(status)")
        }
    }

    private var inspectorF10Ref: EventHotKeyRef?
    private var screenshotF9Ref: EventHotKeyRef?

    func registerInspectorF10(action: @escaping () -> Void) {
        unregisterInspectorF10()
        installHandlerIfNeeded()
        let hkID = EventHotKeyID(signature: OSType(0x494E5350), id: 8888)
        let status = RegisterEventHotKey(109, 0, hkID, GetApplicationEventTarget(), 0, &inspectorF10Ref)
        if status == noErr {
            lock.lock()
            actionClosures[8888] = action
            lock.unlock()
            print("🔍 Inspector F10 HotKey registered")
        }
    }

    func unregisterInspectorF10() {
        if let ref = inspectorF10Ref {
            UnregisterEventHotKey(ref)
            inspectorF10Ref = nil
            lock.lock()
            actionClosures.removeValue(forKey: 8888)
            lock.unlock()
        }
    }

    func registerScreenshotF9(action: @escaping () -> Void) {
        unregisterScreenshotF9()
        installHandlerIfNeeded()
        let hkID = EventHotKeyID(signature: OSType(0x5343524E), id: 8889)
        let status = RegisterEventHotKey(101, 0, hkID, GetApplicationEventTarget(), 0, &screenshotF9Ref)
        if status == noErr {
            lock.lock()
            actionClosures[8889] = action
            lock.unlock()
            print("📸 Screenshot F9 HotKey registered")
        }
    }

    func unregisterScreenshotF9() {
        if let ref = screenshotF9Ref {
            UnregisterEventHotKey(ref)
            screenshotF9Ref = nil
            lock.lock()
            actionClosures.removeValue(forKey: 8889)
            lock.unlock()
        }
    }

    func dispatch(hotKeyID: UInt32) {
        if hotKeyID == 9999 {
            print("🚨 EMERGENCY KILL")
            MacroRuntime.shared.emergencyStop()
            NSSound.beep()
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }
        if hotKeyID == 8888 {
            lock.lock()
            let closure = actionClosures[8888]
            lock.unlock()
            if let closure = closure {
                DispatchQueue.main.async { closure() }
            }
            return
        }
        if hotKeyID == 8889 {
            lock.lock()
            let closure = actionClosures[8889]
            lock.unlock()
            if let closure = closure {
                DispatchQueue.main.async { closure() }
            }
            return
        }
        lock.lock()
        let closure = actionClosures[hotKeyID]
        lock.unlock()
        if let closure = closure {
            DispatchQueue.global(qos: .userInitiated).async { closure() }
        }
    }
}

// ==========================================
// MARK: - Parser & Serializer
// ==========================================
