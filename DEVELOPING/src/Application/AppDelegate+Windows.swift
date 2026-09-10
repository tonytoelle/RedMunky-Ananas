import Cocoa
import SwiftUI

extension AppDelegate {
    @objc func showEditorWindow() {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let defaultSize = NSSize(width: 980, height: 770)
            let win = EditorWindow(
                contentRect: NSRect(origin: .zero, size: defaultSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.minSize = defaultSize

            if !win.setFrameAutosaveName("ShortKingMainWindow") {
                win.setContentSize(defaultSize)
                win.center()
            }
            if win.frame.size.width < defaultSize.width || win.frame.size.height < defaultSize.height {
                var frame = win.frame
                frame.size.width = max(frame.size.width, defaultSize.width)
                frame.size.height = max(frame.size.height, defaultSize.height)
                win.setFrame(frame, display: true)
            }

            configureWindow(win, title: "👑 ShortKing — Macro Editor")
            win.isOpaque = true
            win.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
            win.contentViewController = NSHostingController(rootView: MainEditorView().preferredColorScheme(.dark))
            window = win
        }

        show(window)
    }

    @objc func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 740, height: 530),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.center()
            configureWindow(win, title: "ShortKing Settings")
            win.contentViewController = NSHostingController(rootView: SettingsView())
            settingsWindow = win
        }

        show(settingsWindow)
    }

    @objc func showInspectorWindow() {
        ScreenAnnotationManager.shared.suspendHotKey()
        NSApp.setActivationPolicy(.regular)
        if inspectorWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.center()
            configureWindow(win, title: "🔍 ShortKing — UI Element & Accessibility Inspector")
            win.contentViewController = NSHostingController(rootView: UIInspectorView().preferredColorScheme(.dark))
            inspectorWindow = win
        }

        show(inspectorWindow)
        AXInspectorManager.shared.startInspecting()
    }

    private func configureWindow(_ window: NSWindow, title: String) {
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = preferredWindowLevel
    }

    private func show(_ window: NSWindow?) {
        window?.level = preferredWindowLevel
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private var preferredWindowLevel: NSWindow.Level {
        UserDefaults.standard.bool(forKey: "alwaysOnTop") ? .floating : .normal
    }

    func updateAlwaysOnTop() {
        let level = preferredWindowLevel
        window?.level = level
        settingsWindow?.level = level
        inspectorWindow?.level = level
    }

    @objc func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        setAlwaysOnTop(!UserDefaults.standard.bool(forKey: "alwaysOnTop"), sender: sender)
    }

    @objc func toggleAlwaysOnTopFromMenu(_ sender: NSMenuItem) {
        let newValue = !UserDefaults.standard.bool(forKey: "alwaysOnTop")
        setAlwaysOnTop(newValue, sender: sender)

        let windowMenu = NSApp.mainMenu?.item(withTitle: "Window")?.submenu
        windowMenu?.items.first(where: { $0.action == #selector(toggleAlwaysOnTop) })?.state = newValue ? .on : .off
    }

    private func setAlwaysOnTop(_ enabled: Bool, sender: NSMenuItem) {
        UserDefaults.standard.set(enabled, forKey: "alwaysOnTop")
        sender.state = enabled ? .on : .off
        updateAlwaysOnTop()
    }

    func updateDockVisibility(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    func updateMenuBarVisibility(_ show: Bool) {
        statusItem?.isVisible = show
    }

    func windowDidBecomeKey(_ notification: Notification) {
        (notification.object as? NSWindow)?.orderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)

        if sender == inspectorWindow {
            AXInspectorManager.shared.stopInspecting()
            ScreenAnnotationManager.shared.resumeHotKey()
        }

        let anotherWindowIsVisible = [window, settingsWindow, inspectorWindow].contains {
            $0 !== sender && $0?.isVisible == true
        }
        if !anotherWindowIsVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }
}
