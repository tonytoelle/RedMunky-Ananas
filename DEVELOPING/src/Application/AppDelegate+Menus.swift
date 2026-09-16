import Cocoa

extension AppDelegate {
    func setupMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(macroMenuItem())
        mainMenu.addItem(toolsMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private func applicationMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "RedMunky Ananas")

        menu.addTargetedItem(title: "About RedMunky Ananas", action: #selector(showAbout), target: self, symbol: "info.circle")
        menu.addItem(.separator())
        menu.addTargetedItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",", target: self, symbol: "gearshape")
        menu.addItem(.separator())

        let relaunch = menu.addTargetedItem(title: "Relaunch RedMunky Ananas", action: #selector(relaunchApp), keyEquivalent: "r", target: self, symbol: "arrow.clockwise")
        relaunch.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        NSApp.servicesMenu = servicesMenu
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())

        menu.addTargetedItem(title: "Hide RedMunky Ananas", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h", symbol: "eye.slash")
        let hideOthers = menu.addTargetedItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h", symbol: "square.dashed")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addTargetedItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), symbol: "eye")
        menu.addItem(.separator())
        menu.addTargetedItem(title: "Quit RedMunky Ananas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", symbol: "power")

        root.submenu = menu
        return root
    }

    private func fileMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "File")
        menu.addTargetedItem(title: "New Macro", action: #selector(newMacro), keyEquivalent: "n", target: self)
        let openFolder = menu.addTargetedItem(title: "Open Macros Folder…", action: #selector(openFolder), keyEquivalent: "o", target: self)
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        menu.addTargetedItem(title: "Reload Macros", action: #selector(reload), keyEquivalent: "r", target: self)
        menu.addItem(.separator())
        menu.addTargetedItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        root.submenu = menu
        return root
    }

    private func editMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        menu.addTargetedItem(title: "Undo", action: #selector(undoAction(_:)), keyEquivalent: "z", target: self)
        menu.addTargetedItem(title: "Redo", action: #selector(redoAction(_:)), keyEquivalent: "Z", target: self)
        menu.addItem(.separator())
        menu.addTargetedItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addTargetedItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addTargetedItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addTargetedItem(title: "Delete", action: #selector(deleteSelectedActionFromMenu(_:)), keyEquivalent: "\u{08}", target: self)
        menu.addTargetedItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        root.submenu = menu
        return root
    }

    private func macroMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Macro")
        menu.addTargetedItem(title: "Run Selected Macro", action: #selector(runCurrentMacro), keyEquivalent: "\r", target: self)

        let suspendTitle = MacroStore.shared.isSuspended ? "Resume All Macros" : "Suspend All Macros"
        let suspend = menu.addTargetedItem(title: suspendTitle, action: #selector(toggleSuspendAllMacros), keyEquivalent: "s", target: self)
        suspend.keyEquivalentModifierMask = [.command, .control]

        menu.addTargetedItem(title: "Create New Macro", action: #selector(newMacro), keyEquivalent: "n", target: self)
        menu.addItem(.separator())
        let emergency = menu.addTargetedItem(title: "🛑 Emergency Stop Engine", action: #selector(emergencyKill), keyEquivalent: "x", target: self)
        emergency.keyEquivalentModifierMask = [.command, .control, .shift]
        root.submenu = menu
        return root
    }

    private func toolsMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Tools")

        let inspector = menu.addTargetedItem(title: "UI Element Inspector…", action: #selector(showInspectorWindow), keyEquivalent: "i", target: self, symbol: "magnifyingglass")
        inspector.keyEquivalentModifierMask = [.command, .option]
        menu.addTargetedItem(title: "Screenshot with Note (F9)", action: #selector(startScreenshotAnnotation), target: self, symbol: "rectangle.dashed.and.paperclip")
        menu.addItem(.separator())

        let dropShelf = menu.addTargetedItem(title: "Drop Shelf (Wiggle Drag)", action: #selector(toggleDropShelf(_:)), target: self, symbol: "tray.and.arrow.down")
        dropShelf.state = DropShelfManager.shared.isEnabled ? .on : .off
        root.submenu = menu
        return root
    }

    private func windowMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Window")
        NSApp.windowsMenu = menu
        menu.addTargetedItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addTargetedItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        menu.addTargetedItem(title: "Macro Editor", action: #selector(showEditorWindow), keyEquivalent: "1", target: self)

        let alwaysOnTop = menu.addTargetedItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), target: self)
        alwaysOnTop.state = UserDefaults.standard.bool(forKey: "alwaysOnTop") ? .on : .off
        menu.addItem(.separator())
        menu.addTargetedItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)))
        root.submenu = menu
        return root
    }

    private func helpMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Help")
        menu.addTargetedItem(title: "RedMunky Ananas Documentation", action: #selector(openLearnFolder), keyEquivalent: "?", target: self)
        menu.addTargetedItem(title: "About RedMunky Ananas", action: #selector(showAbout), target: self)
        root.submenu = menu
        return root
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        buildStatusMenu()
    }

    func updateMenuBarIcon() {
        let isSuspended = MacroStore.shared.isSuspended
        let symbolName = isSuspended ? "pause.circle.fill" : "crown.fill"
        let description = isSuspended ? "RedMunky Ananas Suspended" : "RedMunky Ananas Active"

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        ) {
            image.isTemplate = true
            statusItem?.button?.image = image
            statusItem?.button?.title = ""
        } else {
            statusItem?.button?.image = nil
            statusItem?.button?.title = isSuspended ? "⏸️" : "👑"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == statusMenu {
            buildStatusMenu()
        }
    }

    func buildStatusMenu() {
        statusMenu.removeAllItems()
        let isSuspended = MacroStore.shared.isSuspended
        let suspendTitle = isSuspended ? "▶️ Resume All Macros" : "⏸️ Suspend All Macros"
        statusMenu.addTargetedItem(title: suspendTitle, action: #selector(toggleSuspendAllMacros), target: self)
        statusMenu.addItem(.separator())
        statusMenu.addTargetedItem(title: "Open Macro Editor…", action: #selector(showEditorWindow), keyEquivalent: "e", target: self)
        statusMenu.addTargetedItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",", target: self)

        let toolsItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        let tools = NSMenu(title: "Tools")
        let inspector = tools.addTargetedItem(title: "🔍 UI Element Inspector…", action: #selector(showInspectorWindow), keyEquivalent: "i", target: self)
        inspector.keyEquivalentModifierMask = [.command, .option]
        tools.addTargetedItem(title: "📸 Screenshot with Note (F9)", action: #selector(startScreenshotAnnotation), target: self)
        let dropShelf = tools.addTargetedItem(title: "📥 Drop Shelf (Wiggle to Hold)", action: #selector(toggleDropShelf(_:)), target: self)
        dropShelf.state = DropShelfManager.shared.isEnabled ? .on : .off
        toolsItem.submenu = tools
        statusMenu.addItem(toolsItem)

        let alwaysOnTop = statusMenu.addTargetedItem(title: "Always on Top", action: #selector(toggleAlwaysOnTopFromMenu(_:)), target: self)
        alwaysOnTop.state = UserDefaults.standard.bool(forKey: "alwaysOnTop") ? .on : .off
        let launchAtLogin = statusMenu.addTargetedItem(title: "Launch at Login", action: #selector(toggleLaunchAtLoginFromMenu(_:)), target: self)
        launchAtLogin.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off

        statusMenu.addItem(.separator())
        statusMenu.addTargetedItem(title: "Reload Macros", action: #selector(reload), keyEquivalent: "r", target: self)
        statusMenu.addTargetedItem(title: "Open Macros Folder", action: #selector(openFolder), keyEquivalent: "o", target: self)
        statusMenu.addTargetedItem(title: "Open Docs & Guides", action: #selector(openLearnFolder), target: self)
        statusMenu.addItem(.separator())
        statusMenu.addTargetedItem(title: "🛑 Emergency Stop (⌘⌃⇧X)", action: #selector(emergencyKill), target: self)
        statusMenu.addItem(.separator())
        statusMenu.addTargetedItem(title: "About RedMunky Ananas", action: #selector(showAbout), target: self)
        statusMenu.addTargetedItem(title: "Quit RedMunky Ananas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let itemCount = DropShelfManager.shared.heldItems.count
        let title = itemCount > 0 ? "DropShelf (\(itemCount) items)" : "DropShelf"
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addTargetedItem(title: "Open DropShelf", action: #selector(bringDropShelfToFront), target: self)

        if itemCount > 0 {
            menu.addTargetedItem(title: "Clear DropShelf Items", action: #selector(clearDropShelfItems), target: self)
        }

        menu.addItem(.separator())
        menu.addTargetedItem(title: "RedMunky Ananas Macro Editor", action: #selector(showEditorWindow), target: self)
        return menu
    }
}

extension NSMenu {
    @discardableResult
    func addTargetedItem(
        title: String,
        action: Selector?,
        keyEquivalent: String = "",
        target: AnyObject? = nil,
        symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if let symbol {
            item.setSymbol(symbol)
        }
        addItem(item)
        return item
    }
}

extension NSMenuItem {
    func setSymbol(_ symbolName: String) {
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            image.isTemplate = true
            self.image = image
        }
    }
}
