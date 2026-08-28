import SwiftUI
import AppKit

// ============================================
// MARK: - App Entry Point
// ============================================
@main
struct AppleMusicUIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar) // Membiarkan titlebar menyatu native
    }
}
