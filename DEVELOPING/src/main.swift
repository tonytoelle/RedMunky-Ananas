import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    static var shared: AppDelegate?

    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var window: NSWindow?
    var settingsWindow: NSWindow?
    var inspectorWindow: NSWindow?
    
    private var lastModificationDate: Date? = nil
    private var binaryWatchTimer: Timer? = nil
    private var deleteKeyMonitor: Any? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.applicationIconImage = generateAppIcon()
        CarbonHotKeyManager.shared.installHandlerIfNeeded()
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
        DropShelfManager.shared.stopMonitoring()
    }
    
    private func installDeleteKeyMonitor() {
        deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Handle Cmd+Z (Undo) and Cmd+Shift+Z (Redo)
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "z" {
                if let responder = NSApp.keyWindow?.firstResponder {
                    if let tv = responder as? NSTextView, tv.isEditable {
                        return event // Allow standard text field undo
                    }
                    if let tf = responder as? NSTextField, tf.isEditable {
                        return event
                    }
                }
                
                if event.modifierFlags.contains(.shift) {
                    if MacroStore.shared.undoManager.canRedo {
                        MacroStore.shared.undoManager.redo()
                        return nil
                    }
                } else {
                    if MacroStore.shared.undoManager.canUndo {
                        MacroStore.shared.undoManager.undo()
                        return nil
                    }
                }
            }
            
            // keyCode 51 = Backspace / Delete, 117 = Forward Delete
            if event.keyCode == 51 || event.keyCode == 117 {
                // Check if user is currently actively typing in an editable text field/editor
                if let responder = NSApp.keyWindow?.firstResponder {
                    if let tv = responder as? NSTextView, tv.isEditable {
                        return event
                    }
                    if let tf = responder as? NSTextField, tf.isEditable {
                        return event
                    }
                }
                
                // If action(s) are selected in ShortKing, delete them immediately
                if !MacroStore.shared.selectedActionIDs.isEmpty {
                    MacroStore.shared.deleteSelectedActions()
                    return nil
                }
            }
            
            // Handle Cmd+C (Copy)
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "c" {
                if let responder = NSApp.keyWindow?.firstResponder {
                    if let tv = responder as? NSTextView, tv.isEditable { return event }
                    if let tf = responder as? NSTextField, tf.isEditable { return event }
                }
                
                // 1. Copy selected action items if there are any
                if !MacroStore.shared.selectedActionIDs.isEmpty, let selectedMacro = MacroStore.shared.selectedMacro {
                    let itemsToCopy = selectedMacro.actionItems.filter { MacroStore.shared.selectedActionIDs.contains($0.id) }
                    if !itemsToCopy.isEmpty {
                        MacroStore.shared.copiedActions = itemsToCopy
                        MacroStore.shared.copiedMacroURL = nil
                        return nil // consumed
                    }
                }
                
                // 2. Otherwise copy the selected macro in the sidebar
                if let selectedPath = MacroStore.shared.selectedFilePath {
                    MacroStore.shared.copiedMacroURL = URL(fileURLWithPath: selectedPath)
                    MacroStore.shared.copiedActions = []
                    return nil // consumed
                }
            }
            
            // Handle Cmd+V (Paste)
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v" {
                if let responder = NSApp.keyWindow?.firstResponder {
                    if let tv = responder as? NSTextView, tv.isEditable { return event }
                    if let tf = responder as? NSTextField, tf.isEditable { return event }
                }
                
                // 1. Paste copied action items if there are any
                if !MacroStore.shared.copiedActions.isEmpty, let selectedMacro = MacroStore.shared.selectedMacro {
                    MacroStore.shared.registerUndoState(for: selectedMacro)
                    let clonedPasted = MacroStore.shared.copiedActions.map { MacroActionItem(action: $0.action, repeatCount: $0.repeatCount) }
                    
                    if let lastSelectedID = MacroStore.shared.lastSelectedActionID,
                       let idx = selectedMacro.actionItems.firstIndex(where: { $0.id == lastSelectedID }) {
                        selectedMacro.actionItems.insert(contentsOf: clonedPasted, at: idx + 1)
                    } else {
                        selectedMacro.actionItems.append(contentsOf: clonedPasted)
                    }
                    MacroStore.shared.saveMacro(selectedMacro)
                    return nil // consumed
                }
                
                // 2. Otherwise paste the copied macro
                if MacroStore.shared.copiedMacroURL != nil {
                    let destDir: URL
                    if let folderPath = MacroStore.shared.selectedFolderPath {
                        destDir = URL(fileURLWithPath: folderPath)
                    } else if let filePath = MacroStore.shared.selectedFilePath {
                        destDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
                    } else {
                        destDir = MacroStore.shared.watchDirectoryURL
                    }
                    MacroStore.shared.pasteCopiedMacro(toFolder: destDir)
                    return nil // consumed
                }
            }
            
            return event
        }
    }
    
    @objc func undoAction(_ sender: Any?) {
        if let responder = NSApp.keyWindow?.firstResponder,
           let tv = responder as? NSTextView, tv.isEditable,
           let u = tv.undoManager, u.canUndo {
            u.undo()
            return
        }
        if MacroStore.shared.undoManager.canUndo {
            MacroStore.shared.undoManager.undo()
        }
    }

    @objc func redoAction(_ sender: Any?) {
        if let responder = NSApp.keyWindow?.firstResponder,
           let tv = responder as? NSTextView, tv.isEditable,
           let u = tv.undoManager, u.canRedo {
            u.redo()
            return
        }
        if MacroStore.shared.undoManager.canRedo {
            MacroStore.shared.undoManager.redo()
        }
    }
    
    @objc func deleteSelectedActionFromMenu(_ sender: Any?) {
        if !MacroStore.shared.selectedActionIDs.isEmpty {
            MacroStore.shared.deleteSelectedActions()
        }
    }

    @objc func relaunchApp() {
        if let selected = MacroStore.shared.selectedMacro {
            MacroStore.shared.saveMacro(selected)
        }
        
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
    
    func startBinaryWatcher() {
        let appURL = Bundle.main.bundleURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: appURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            lastModificationDate = modDate
        }
        
        binaryWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let url = Bundle.main.bundleURL
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modDate = attrs[.modificationDate] as? Date {
                if let last = self.lastModificationDate, modDate > last {
                    self.binaryWatchTimer?.invalidate()
                    self.relaunchApp()
                }
            }
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else { return }
        let url = URL(fileURLWithPath: first)
        
        let watchDir = MacroStore.shared.watchDirectoryURL
        let isInsideWatchDir = url.standardizedFileURL.path.hasPrefix(watchDir.standardizedFileURL.path)
        
        var targetURL = url
        if !isInsideWatchDir {
            let destURL = watchDir.appendingPathComponent(url.lastPathComponent)
            if url.path != destURL.path {
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.copyItem(at: url, to: destURL)
                }
            }
            targetURL = destURL
        }
        
        MacroStore.shared.loadMacros()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let found = MacroStore.shared.macros.first(where: { $0.fileURL.standardizedFileURL.path == targetURL.standardizedFileURL.path }) {
                MacroStore.shared.selectedFilePath = found.fileURL.path
                MacroStore.shared.selectedFolderPath = nil
                self.showEditorWindow()
            }
        }
    }

    // MARK: - Standard macOS Main Menu Bar (Top Screen)
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. Application Menu (ShortKing)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "ShortKing")
        
        let aboutItem = NSMenuItem(title: "About ShortKing", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.setSymbol("info.circle")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.setSymbol("gearshape")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem.separator())

        let relaunchItem = NSMenuItem(title: "Relaunch ShortKing", action: #selector(relaunchApp), keyEquivalent: "r")
        relaunchItem.keyEquivalentModifierMask = [.command, .shift]
        relaunchItem.setSymbol("arrow.clockwise")
        relaunchItem.target = self
        appMenu.addItem(relaunchItem)

        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        NSApp.servicesMenu = servicesMenu
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: "Hide ShortKing", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.setSymbol("eye.slash")
        appMenu.addItem(hideItem)
        
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.setSymbol("square.dashed")
        appMenu.addItem(hideOthersItem)
        
        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.setSymbol("eye")
        appMenu.addItem(showAllItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit ShortKing", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.setSymbol("power")
        appMenu.addItem(quitItem)
        
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Macro", action: #selector(newMacro), keyEquivalent: "n").target = self
        let openFolderItem = NSMenuItem(title: "Open Macros Folder…", action: #selector(openFolder), keyEquivalent: "o")
        openFolderItem.keyEquivalentModifierMask = [.command, .shift]
        openFolderItem.target = self
        fileMenu.addItem(openFolderItem)
        fileMenu.addItem(withTitle: "Reload Macros", action: #selector(reload), keyEquivalent: "r").target = self
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. Edit Menu (Standard macOS Clipboard & Text editing)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undoItem = NSMenuItem(title: "Undo", action: #selector(undoAction(_:)), keyEquivalent: "z")
        undoItem.target = self
        editMenu.addItem(undoItem)
        let redoItem = NSMenuItem(title: "Redo", action: #selector(redoAction(_:)), keyEquivalent: "Z")
        redoItem.target = self
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let deleteMenuItem = NSMenuItem(title: "Delete", action: #selector(deleteSelectedActionFromMenu(_:)), keyEquivalent: "\u{08}")
        deleteMenuItem.target = self
        editMenu.addItem(deleteMenuItem)
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 4. Macro Engine Menu
        let macroMenuItem = NSMenuItem()
        let macroMenu = NSMenu(title: "Macro")
        let runItem = NSMenuItem(title: "Run Selected Macro", action: #selector(runCurrentMacro), keyEquivalent: "\r")
        runItem.target = self
        macroMenu.addItem(runItem)
        macroMenu.addItem(withTitle: "Create New Macro", action: #selector(newMacro), keyEquivalent: "n").target = self
        macroMenu.addItem(NSMenuItem.separator())
        let emergencyItem = NSMenuItem(title: "🛑 Emergency Stop Engine", action: #selector(emergencyKill), keyEquivalent: "x")
        emergencyItem.keyEquivalentModifierMask = [.command, .control, .shift]
        emergencyItem.target = self
        macroMenu.addItem(emergencyItem)
        macroMenuItem.submenu = macroMenu
        mainMenu.addItem(macroMenuItem)

        // 5. Tools Menu
        let toolsMenuItem = NSMenuItem()
        let toolsMenu = NSMenu(title: "Tools")
        let inspectorItem = NSMenuItem(title: "UI Element Inspector…", action: #selector(showInspectorWindow), keyEquivalent: "i")
        inspectorItem.keyEquivalentModifierMask = [.command, .option]
        inspectorItem.target = self
        toolsMenu.addItem(inspectorItem)
        toolsMenuItem.submenu = toolsMenu
        mainMenu.addItem(toolsMenuItem)

        // 6. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        NSApp.windowsMenu = windowMenu
        
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Macro Editor", action: #selector(showEditorWindow), keyEquivalent: "1").target = self
        
        let alwaysOnTopItem = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = UserDefaults.standard.bool(forKey: "alwaysOnTop") ? .on : .off
        windowMenu.addItem(alwaysOnTopItem)
        
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // 6. Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "ShortKing Documentation", action: #selector(openLearnFolder), keyEquivalent: "?").target = self
        helpMenu.addItem(withTitle: "About ShortKing", action: #selector(showAbout), keyEquivalent: "").target = self
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let crownImage = NSImage(systemSymbolName: "crown.fill", accessibilityDescription: nil) {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            if let configuredImage = crownImage.withSymbolConfiguration(symbolConfig) {
                configuredImage.isTemplate = true
                statusItem.button?.image = configuredImage
            }
        } else {
            statusItem.button?.title = "👑"
        }
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        buildStatusMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == statusMenu {
            buildStatusMenu()
        }
    }

    func buildStatusMenu() {
        statusMenu.removeAllItems()

        let editorItem = NSMenuItem(title: "Open Macro Editor…", action: #selector(showEditorWindow), keyEquivalent: "e")
        editorItem.target = self
        statusMenu.addItem(editorItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        // Tools Submenu
        let toolsItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        let toolsSubmenu = NSMenu(title: "Tools")
        
        let inspectorMenuItem = NSMenuItem(title: "🔍 UI Element Inspector…", action: #selector(showInspectorWindow), keyEquivalent: "i")
        inspectorMenuItem.keyEquivalentModifierMask = [.command, .option]
        inspectorMenuItem.target = self
        toolsSubmenu.addItem(inspectorMenuItem)
        
        toolsItem.submenu = toolsSubmenu
        statusMenu.addItem(toolsItem)

        let alwaysOnTopItem = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTopFromMenu(_:)), keyEquivalent: "")
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = UserDefaults.standard.bool(forKey: "alwaysOnTop") ? .on : .off
        statusMenu.addItem(alwaysOnTopItem)

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLoginFromMenu(_:)), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        statusMenu.addItem(launchAtLoginItem)

        statusMenu.addItem(NSMenuItem.separator())

        let reloadItem = NSMenuItem(title: "Reload Macros", action: #selector(reload), keyEquivalent: "r")
        reloadItem.target = self
        statusMenu.addItem(reloadItem)

        let folderItem = NSMenuItem(title: "Open Macros Folder", action: #selector(openFolder), keyEquivalent: "o")
        folderItem.target = self
        statusMenu.addItem(folderItem)

        let learnItem = NSMenuItem(title: "Open Docs & Guides", action: #selector(openLearnFolder), keyEquivalent: "")
        learnItem.target = self
        statusMenu.addItem(learnItem)

        statusMenu.addItem(NSMenuItem.separator())

        let emItem = NSMenuItem(title: "🛑 Emergency Stop (⌘⌃⇧X)", action: #selector(emergencyKill), keyEquivalent: "")
        emItem.target = self
        statusMenu.addItem(emItem)

        statusMenu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About ShortKing", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        statusMenu.addItem(aboutItem)

        statusMenu.addItem(withTitle: "Quit ShortKing", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func showEditorWindow() {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let defaultSize = NSSize(width: 980, height: 770)
            let minSize = NSSize(width: 980, height: 770)

            let win = EditorWindow(
                contentRect: NSRect(x: 0, y: 0, width: defaultSize.width, height: defaultSize.height),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            win.minSize = minSize

            if !win.setFrameAutosaveName("ShortKingMainWindow") {
                win.setContentSize(defaultSize)
                win.center()
            }
            if win.frame.size.width < 980 || win.frame.size.height < 770 {
                var currentFrame = win.frame
                currentFrame.size.width = max(currentFrame.size.width, 980)
                currentFrame.size.height = max(currentFrame.size.height, 770)
                win.setFrame(currentFrame, display: true)
            }
            win.title = "👑 ShortKing — Macro Editor"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.titlebarSeparatorStyle = .none
            win.isOpaque = false
            win.backgroundColor = .clear
            win.contentViewController = NSHostingController(rootView: MainEditorView().preferredColorScheme(.dark))
            win.isReleasedWhenClosed = false
            win.delegate = self
            window = win
            
            let alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
            win.level = alwaysOnTop ? .floating : .normal
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateAlwaysOnTop() {
        let alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        window?.level = alwaysOnTop ? .floating : .normal
    }

    @objc func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        let current = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        let newVal = !current
        UserDefaults.standard.set(newVal, forKey: "alwaysOnTop")
        sender.state = newVal ? .on : .off
        updateAlwaysOnTop()
    }

    @objc func toggleAlwaysOnTopFromMenu(_ sender: NSMenuItem) {
        let current = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        let newVal = !current
        UserDefaults.standard.set(newVal, forKey: "alwaysOnTop")
        sender.state = newVal ? .on : .off
        updateAlwaysOnTop()
        
        if let winMenu = NSApp.mainMenu?.item(withTitle: "Window")?.submenu {
            if let item = winMenu.items.first(where: { $0.action == #selector(toggleAlwaysOnTop) }) {
                item.state = newVal ? .on : .off
            }
        }
    }

    @objc func toggleLaunchAtLoginFromMenu(_ sender: NSMenuItem) {
        let current = LaunchAtLoginManager.shared.isEnabled
        let newVal = !current
        LaunchAtLoginManager.shared.setEnabled(newVal)
        sender.state = newVal ? .on : .off
    }

    func updateDockVisibility(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    func updateMenuBarVisibility(_ show: Bool) {
        statusItem?.isVisible = show
    }

    @objc func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 740, height: 530),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            win.center()
            win.title = "ShortKing Settings"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.contentViewController = NSHostingController(rootView: SettingsView())
            win.isReleasedWhenClosed = false
            win.delegate = self
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showInspectorWindow() {
        NSApp.setActivationPolicy(.regular)
        if inspectorWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            win.center()
            win.title = "🔍 ShortKing — UI Element & Accessibility Inspector"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.level = .floating
            win.contentViewController = NSHostingController(rootView: UIInspectorView().preferredColorScheme(.dark))
            win.isReleasedWhenClosed = false
            win.delegate = self
            inspectorWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        inspectorWindow?.makeKeyAndOrderFront(nil)
        AXInspectorManager.shared.startInspecting()
    }

    // MARK: - NSWindowDelegate
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        
        if sender == inspectorWindow {
            AXInspectorManager.shared.stopInspecting()
        }
        
        let isEditorVisible = window?.isVisible == true && sender != window
        let isSettingsVisible = settingsWindow?.isVisible == true && sender != settingsWindow
        let isInspectorVisible = inspectorWindow?.isVisible == true && sender != inspectorWindow
        
        if !isEditorVisible && !isSettingsVisible && !isInspectorVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    @objc func newMacro() {
        MacroStore.shared.createNewMacro()
        showEditorWindow()
    }

    @objc func runCurrentMacro() {
        if let m = MacroStore.shared.selectedMacro {
            MacroStore.shared.runMacro(m)
        }
    }

    @objc func runMacroFromMenu(_ sender: NSMenuItem) {
        if let macro = sender.representedObject as? MacroItem {
            MacroStore.shared.runMacro(macro)
        }
    }

    @objc func emergencyKill() {
        CarbonHotKeyManager.shared.dispatch(hotKeyID: 9999)
    }

    @objc func openLearnFolder() {
        let learnURL = URL(fileURLWithPath: "/Users/tonytoelle/Documents/PROJECTS/RedMunky - ShortKing/LEARN")
        NSWorkspace.shared.open(learnURL)
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "👑 ShortKing"
        alert.informativeText = "Compact & High-Performance macOS Macro Automation Engine\nPowered by Carbon HotKey & Quartz Event Simulation.\n\nEmergency Stop: ⌘⌃⇧X"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func reload() { MacroStore.shared.loadMacros() }
    @objc func openFolder() { NSWorkspace.shared.open(MacroStore.shared.watchDirectoryURL) }
}

extension NSMenuItem {
    func setSymbol(_ symbolName: String) {
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            img.isTemplate = true
            self.image = img
        }
    }
}

// ==========================================
// MARK: - Entry Point
// ==========================================
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// ==========================================
// MARK: - Extensions
// ==========================================
