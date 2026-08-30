import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var isAccessibilityGranted: Bool = false
    @Published var isInputMonitoringGranted: Bool = false
    @Published var isScreenRecordingGranted: Bool = false

    private var timer: Timer?

    init() {
        checkStatus()
        startPolling()
    }

    func checkStatus() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let axGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        let inputGranted: Bool
        if #available(macOS 10.15, *) {
            inputGranted = CGPreflightListenEventAccess()
        } else {
            inputGranted = true
        }

        let screenGranted: Bool
        if #available(macOS 10.15, *) {
            screenGranted = CGPreflightScreenCaptureAccess()
        } else {
            screenGranted = true
        }

        DispatchQueue.main.async {
            self.isAccessibilityGranted = axGranted
            self.isInputMonitoringGranted = inputGranted
            self.isScreenRecordingGranted = screenGranted
        }
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }

    func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        checkStatus()
    }

    func requestInputMonitoringPrompt() {
        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }
        checkStatus()
    }

    func requestScreenRecordingPrompt() {
        if #available(macOS 10.15, *) {
            _ = CGRequestScreenCaptureAccess()
        }
        checkStatus()
    }

    func requestAllPermissions() {
        requestAccessibilityPrompt()
        requestInputMonitoringPrompt()
        requestScreenRecordingPrompt()
        // Buka setting jika belum diberikan
        if !isAccessibilityGranted {
            openAccessibilitySettings()
        }
    }

    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenRecordingSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func grantOrOpenAccessibility() {
        if !isAccessibilityGranted {
            requestAccessibilityPrompt()
        }
        openAccessibilitySettings()
    }

    func grantOrOpenInputMonitoring() {
        if !isInputMonitoringGranted {
            requestInputMonitoringPrompt()
        }
        openInputMonitoringSettings()
    }

    func grantOrOpenScreenRecording() {
        if !isScreenRecordingGranted {
            requestScreenRecordingPrompt()
        }
        openScreenRecordingSettings()
    }
}

// ==========================================
// MARK: - Launch at Login Manager
// ==========================================
