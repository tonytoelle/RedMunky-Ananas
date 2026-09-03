import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var window: NSWindow?
    var settingsWindow: NSWindow?
    var inspectorWindow: NSWindow?

    var lastModificationDate: Date?
    var binaryWatchTimer: Timer?
    var deleteKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.applicationIconImage = generateAppIcon()
        CarbonHotKeyManager.shared.installHandlerIfNeeded()
        ScreenAnnotationManager.shared.start()
        PermissionManager.shared.checkStatus()
        LaunchAtLoginManager.shared.enableAutoStart()

        if UserDefaults.standard.bool(forKey: "enableThreeFingerMiddleClick") {
            MultitouchManager.shared.startListening()
        }

        setupMainMenu()
        setupMenuBar()
        showEditorWindow()
        startBinaryWatcher()
        installDeleteKeyMonitor()
        DropShelfManager.shared.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let deleteKeyMonitor {
            NSEvent.removeMonitor(deleteKeyMonitor)
        }
        binaryWatchTimer?.invalidate()
        DropShelfManager.shared.stopMonitoring()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
