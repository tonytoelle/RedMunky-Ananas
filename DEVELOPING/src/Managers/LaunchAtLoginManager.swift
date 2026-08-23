import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool = false

    private var isUpdating: Bool = false
    private let launchAgentLabel = "com.redmunky.shortking"
    private var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/com.redmunky.shortking.plist")
    }

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        isUpdating = true
        var active = false
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                active = true
            }
        }
        if !active {
            active = FileManager.default.fileExists(atPath: launchAgentURL.path)
        }
        let result = active
        DispatchQueue.main.async {
            self.isEnabled = result
            self.isUpdating = false
        }
    }

    func setEnabled(_ enable: Bool) {
        // 1. Try SMAppService (macOS 13+)
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("SMAppService: \(error.localizedDescription)")
            }
        }

        // 2. Dual fallback: User LaunchAgent plist in ~/Library/LaunchAgents
        let appBundlePath = Bundle.main.bundlePath
        if enable {
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(launchAgentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/usr/bin/open</string>
                    <string>-a</string>
                    <string>\(appBundlePath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>ProcessType</key>
                <string>Interactive</string>
            </dict>
            </plist>
            """
            do {
                let dir = launchAgentURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try plistContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to write LaunchAgent: \(error)")
            }
        } else {
            try? FileManager.default.removeItem(at: launchAgentURL)
        }

        refreshStatus()
    }

    func enableAutoStart() {
        setEnabled(true)
    }
}

// ==========================================
// MARK: - Shortcut Badge View
// ==========================================
