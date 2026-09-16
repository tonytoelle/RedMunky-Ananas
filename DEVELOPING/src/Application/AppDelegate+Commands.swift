import Cocoa

extension AppDelegate {
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let firstPath = filenames.first else { return }
        let sourceURL = URL(fileURLWithPath: firstPath)
        let watchDirectory = MacroStore.shared.watchDirectoryURL
        let isInsideWatchDirectory = sourceURL.standardizedFileURL.path.hasPrefix(
            watchDirectory.standardizedFileURL.path
        )

        var targetURL = sourceURL
        if !isInsideWatchDirectory {
            let destinationURL = watchDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if sourceURL.path != destinationURL.path,
               !FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
            targetURL = destinationURL
        }

        MacroStore.shared.loadMacros()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let macro = MacroStore.shared.macros.first(where: {
                $0.fileURL.standardizedFileURL.path == targetURL.standardizedFileURL.path
            }) else { return }

            MacroStore.shared.selectedFilePath = macro.fileURL.path
            MacroStore.shared.selectedFolderPath = nil
            self?.showEditorWindow()
        }
    }

    @objc func newMacro() {
        MacroStore.shared.createNewMacro()
        showEditorWindow()
    }

    @objc func runCurrentMacro() {
        guard let macro = MacroStore.shared.selectedMacro else { return }
        MacroStore.shared.runMacro(macro)
    }

    @objc func runMacroFromMenu(_ sender: NSMenuItem) {
        guard let macro = sender.representedObject as? MacroItem else { return }
        MacroStore.shared.runMacro(macro)
    }

    @objc func toggleSuspendAllMacros() {
        MacroStore.shared.isSuspended.toggle()
        updateMenuBarIcon()
        buildStatusMenu()
    }

    @objc func emergencyKill() {
        CarbonHotKeyManager.shared.dispatch(hotKeyID: 9999)
    }

    @objc func startScreenshotAnnotation() {
        ScreenAnnotationManager.shared.beginSelection()
    }

    @objc func toggleLaunchAtLoginFromMenu(_ sender: NSMenuItem) {
        let newValue = !LaunchAtLoginManager.shared.isEnabled
        LaunchAtLoginManager.shared.setEnabled(newValue)
        sender.state = newValue ? .on : .off
    }

    @objc func toggleDropShelf(_ sender: NSMenuItem) {
        DropShelfManager.shared.isEnabled.toggle()
        sender.state = DropShelfManager.shared.isEnabled ? .on : .off
    }

    @objc func bringDropShelfToFront() {
        if let window = DropShelfManager.shared.shelfWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            DropShelfManager.shared.showShelf(near: NSEvent.mouseLocation)
        }
    }

    @objc func clearDropShelfItems() {
        DropShelfManager.shared.heldItems.removeAll()
        DropShelfManager.shared.closeShelf()
    }

    @objc func openLearnFolder() {
        let projectDirectory = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        NSWorkspace.shared.open(projectDirectory.appendingPathComponent("LEARN", isDirectory: true))
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "👑 RedMunky Ananas"
        alert.informativeText = "Compact & High-Performance macOS Macro Automation Engine\nPowered by Carbon HotKey & Quartz Event Simulation.\n\nEmergency Stop: ⌘⌃⇧X"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func reload() {
        MacroStore.shared.loadMacros()
    }

    @objc func openFolder() {
        NSWorkspace.shared.open(MacroStore.shared.watchDirectoryURL)
    }
}
