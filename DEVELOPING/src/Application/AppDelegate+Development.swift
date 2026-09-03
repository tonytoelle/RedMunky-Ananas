import Cocoa

extension AppDelegate {
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
        if let attributes = try? FileManager.default.attributesOfItem(atPath: appURL.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            lastModificationDate = modificationDate
        }

        binaryWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let appURL = Bundle.main.bundleURL
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: appURL.path),
                  let modificationDate = attributes[.modificationDate] as? Date,
                  let previousDate = self.lastModificationDate,
                  modificationDate > previousDate else { return }

            self.binaryWatchTimer?.invalidate()
            self.relaunchApp()
        }
    }
}
