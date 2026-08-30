import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case permissions = "Permissions & Security"
    case engine = "Macro Engine"
    case appearance = "Appearance & Editor"
    case about = "About ShortKing"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .permissions: return "lock.shield.fill"
        case .engine:      return "bolt.fill"
        case .appearance:  return "paintbrush.fill"
        case .about:       return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:     return Color(red: 0.15, green: 0.55, blue: 0.98)
        case .permissions: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .engine:      return Color(red: 1.00, green: 0.58, blue: 0.00)
        case .appearance:  return Color(red: 0.70, green: 0.35, blue: 0.95)
        case .about:       return Color(red: 0.30, green: 0.65, blue: 0.98)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store = MacroStore.shared
    @ObservedObject var permissions = PermissionManager.shared
    @ObservedObject var launchAtLogin = LaunchAtLoginManager.shared

    @State private var selectedCategory: SettingsCategory = .general
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    // General Settings
    @AppStorage("alwaysOnTop") private var alwaysOnTop: Bool = false
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    @AppStorage("showInDock") private var showInDock: Bool = true
    @AppStorage("enableThreeFingerMiddleClick") private var enableThreeFingerMiddleClick: Bool = false

    // Emergency & Feedback Settings
    @AppStorage("soundOnEmergency") private var soundOnEmergency: Bool = true
    @AppStorage("soundOnComplete") private var soundOnComplete: Bool = true
    @AppStorage("soundOnError") private var soundOnError: Bool = true
    @AppStorage("showOSDFeedback") private var showOSDFeedback: Bool = true

    // Engine Delays & Safety Limits
    @AppStorage("defaultStepDelay") private var defaultStepDelay: Double = 0.05
    @AppStorage("maxLoopIterations") private var maxLoopIterations: Int = 1000

    // Appearance & Editor
    @AppStorage("showActionIndices") private var showActionIndices: Bool = true
    @AppStorage("compactActionCards") private var compactActionCards: Bool = false
    @AppStorage("showTriggerBadgesInSidebar") private var showTriggerBadgesInSidebar: Bool = true

    var filteredCategories: [SettingsCategory] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return SettingsCategory.allCases
        }
        let query = searchText.lowercased()
        return SettingsCategory.allCases.filter { category in
            if category.rawValue.lowercased().contains(query) { return true }
            switch category {
            case .general:
                return "login startup boot dock menubar always on top folder watch directory document path trackpad middle click".contains(query)
            case .permissions:
                return "accessibility input monitoring permission privacy security panic emergency stop shortcut cmd control shift x screen recording".contains(query)
            case .engine:
                return "delay timing speed loop safety iterations sound feedback audio display brightness".contains(query)
            case .appearance:
                return "editor appearance theme index badge compact cards numbers layout".contains(query)
            case .about:
                return "about version documentation learn help reset defaults".contains(query)
            }
        }
    }

    private func categoryDescription(for category: SettingsCategory) -> String {
        switch category {
        case .general:
            return "Configure startup behavior, window controls, and macro storage."
        case .permissions:
            return "Manage macOS system accessibility, screen recording, and panic stops."
        case .engine:
            return "Tune execution timing, iteration ceilings, and sound effects."
        case .appearance:
            return "Customize card layout, step indicators, and sidebar aesthetics."
        case .about:
            return "Software version, project architecture, and developer resources."
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()

            HSplitView {
                // ═══════════════════════════════════════════════════
                // LEFT SIDEBAR (Matching MainEditorView Sidebar)
                // ═══════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    // Search Pill Field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(isSearchFocused ? Color.accentColor : Color(white: 0.55))
                            .font(.system(size: 13, weight: .medium))
                        TextField("Search settings…", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .focused($isSearchFocused)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color(white: 0.55))
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSearchFocused ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    // Category List
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(filteredCategories) { category in
                                SidebarCategoryRow(
                                    category: category,
                                    isSelected: selectedCategory == category,
                                    onSelect: { selectedCategory = category }
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 12)
                    }
                }
                .frame(width: 220)
                .background(Color.clear)

                // ═══════════════════════════════════════════════════
                // RIGHT DETAIL CANVAS (Matching MainEditorView Detail)
                // ═══════════════════════════════════════════════════
                VStack(spacing: 0) {
                    // Header Bar with Window Drag Support
                    HStack(spacing: 12) {
                        Image(systemName: selectedCategory.iconName)
                            .foregroundColor(selectedCategory.iconColor)
                            .font(.system(size: 18, weight: .bold))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedCategory.rawValue)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text(categoryDescription(for: selectedCategory))
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(white: 0.6))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 14)
                    .background(WindowDragView())
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.06)), alignment: .bottom)

                    // Scrollable Settings Cards
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            switch selectedCategory {
                            case .general:
                                renderGeneralSettings()
                            case .permissions:
                                renderPermissionsSettings()
                            case .engine:
                                renderEngineSettings()
                            case .appearance:
                                renderAppearanceSettings()
                            case .about:
                                renderAboutSettings()
                            }
                        }
                        .padding(24)
                    }
                }
                .frame(minWidth: 480)
                .background(Color.clear)
            }
        }
        .frame(minWidth: 720, idealWidth: 760, maxWidth: .infinity, minHeight: 500, idealHeight: 560, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    // ═══════════════════════════════════════════════════
    // 1. GENERAL SETTINGS PANE
    // ═══════════════════════════════════════════════════
    @ViewBuilder
    private func renderGeneralSettings() -> some View {
        // Startup & Window Behavior Card
        settingsCard(title: "Startup & Window Behavior", icon: "power", iconColor: .blue) {
            VStack(spacing: 0) {
                toggleRow(
                    title: "Launch at Login (Buka Otomatis saat Startup)",
                    subtitle: "Starts the ShortKing background macro engine automatically when your Mac turns on or you log in.",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )

                cardDivider()

                toggleRow(
                    title: "Always on Top (Jendela Selalu di Atas)",
                    subtitle: "Keeps the ShortKing Macro Editor floating on top of all other application windows.",
                    isOn: Binding(
                        get: { alwaysOnTop },
                        set: {
                            alwaysOnTop = $0
                            AppDelegate.shared?.updateAlwaysOnTop()
                        }
                    )
                )
            }
        }

        // Dock & Menu Bar Visibility Card
        settingsCard(title: "Dock & Menu Bar Visibility", icon: "menubar.dock.rectangle", iconColor: .teal) {
            VStack(spacing: 0) {
                toggleRow(
                    title: "Show in macOS Menu Bar (Status Bar Item)",
                    subtitle: "Displays the 👑 ShortKing status icon in the top macOS menu bar for rapid macro triggers.",
                    isOn: Binding(
                        get: { showInMenuBar },
                        set: {
                            showInMenuBar = $0
                            AppDelegate.shared?.updateMenuBarVisibility($0)
                        }
                    )
                )

                cardDivider()

                toggleRow(
                    title: "Show in macOS Dock",
                    subtitle: "Displays ShortKing in your macOS Dock. Turn off if you prefer running purely in the Menu Bar.",
                    isOn: Binding(
                        get: { showInDock },
                        set: {
                            showInDock = $0
                            AppDelegate.shared?.updateDockVisibility($0)
                        }
                    )
                )
            }
        }

        // Trackpad Middle Click Card
        settingsCard(title: "Trackpad Gestures", icon: "hand.tap.fill", iconColor: .orange) {
            toggleRow(
                title: "Enable 3-Finger Tap for Middle Click",
                subtitle: "Tapping the trackpad with 3 fingers will execute a middle click (Button 2) at the current cursor position.",
                isOn: Binding(
                    get: { enableThreeFingerMiddleClick },
                    set: { newValue in
                        enableThreeFingerMiddleClick = newValue
                        if newValue {
                            MultitouchManager.shared.startListening()
                        } else {
                            MultitouchManager.shared.stopListening()
                        }
                    }
                )
            )
        }

        // Macro Watch Directory Card
        settingsCard(title: "Macro Watch Directory (Penyimpanan Dokumen)", icon: "folder.fill", iconColor: Color(red: 0.15, green: 0.65, blue: 0.95)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ShortKing monitors this folder in real-time. Any `.shortking` JSON macro file added or edited here will automatically sync.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(white: 0.65))

                HStack(spacing: 8) {
                    Text(store.watchDirectoryURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                HStack(spacing: 10) {
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.title = "Pilih Folder Makro ShortKing"
                        if panel.runModal() == .OK, let url = panel.url {
                            store.setWatchDirectory(url)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.badge.plus")
                            Text("Choose Folder…")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        NSWorkspace.shared.open(store.watchDirectoryURL)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.forward.app")
                            Text("Reveal in Finder")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        store.loadMacros()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reload Macros")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════
    // 2. PERMISSIONS & SECURITY PANE
    // ═══════════════════════════════════════════════════
    @ViewBuilder
    private func renderPermissionsSettings() -> some View {
        // macOS Permissions Card
        settingsCard(title: "macOS System Permissions", icon: "hand.raised.fill", iconColor: .green) {
            VStack(spacing: 0) {
                // Accessibility Row
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility (Aksesibilitas)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Text("Required by macOS to simulate mouse clicks, keyboard shortcuts, drags, and macro events.")
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(white: 0.65))
                        }
                        Spacer()
                        statusBadge(isGranted: permissions.isAccessibilityGranted)
                    }

                    HStack(spacing: 8) {
                        if !permissions.isAccessibilityGranted {
                            Button("Request Permission Prompt") {
                                permissions.requestAccessibilityPrompt()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button("Open macOS Privacy Settings") {
                            permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 8)

                cardDivider()

                // Input Monitoring Row
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Input Monitoring (Pemantauan Input)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Text("Required to capture global hotkey triggers while other applications are in the foreground.")
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(white: 0.65))
                        }
                        Spacer()
                        statusBadge(isGranted: permissions.isInputMonitoringGranted)
                    }

                    HStack(spacing: 8) {
                        if !permissions.isInputMonitoringGranted {
                            Button("Request Permission Prompt") {
                                permissions.requestInputMonitoringPrompt()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button("Open Input Monitoring Settings") {
                            permissions.openInputMonitoringSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 8)

                cardDivider()

                // Screen Recording Row
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screen Recording (Perekaman Layar)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Text("Required to capture screen coordinates, pixel colors, and drag-and-drop targets during macro execution.")
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(white: 0.65))
                        }
                        Spacer()
                        statusBadge(isGranted: permissions.isScreenRecordingGranted)
                    }

                    HStack(spacing: 8) {
                        if !permissions.isScreenRecordingGranted {
                            Button("Request Permission Prompt") {
                                permissions.requestScreenRecordingPrompt()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button("Open Screen Recording Settings") {
                            permissions.openScreenRecordingSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 8)
            }
        }

        // Emergency Panic Card
        settingsCard(title: "Emergency Panic Engine (Saklar Darurat)", icon: "xmark.octagon.fill", iconColor: .red) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global Panic Shortcut:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Pressing this combination immediately aborts all running macro simulations, loops, and actions.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(white: 0.65))
                    }
                    Spacer()
                    Text("⌘ + ⌃ + ⇧ + X")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }

                cardDivider()

                toggleRow(
                    title: "Sound Alert on Panic Trigger",
                    subtitle: "Plays a high-priority macOS system warning alert sound when emergency stop is triggered.",
                    isOn: $soundOnEmergency
                )

                HStack {
                    Spacer()
                    Button {
                        CarbonHotKeyManager.shared.dispatch(hotKeyID: 9999)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.slash.fill")
                            Text("Test Emergency Stop Now")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
    }

    // ═══════════════════════════════════════════════════
    // 3. MACRO ENGINE & EXECUTION PANE
    // ═══════════════════════════════════════════════════
    @ViewBuilder
    private func renderEngineSettings() -> some View {
        // Timing & Delays Card
        settingsCard(title: "Execution Timing & Delays", icon: "gauge.with.needle.fill", iconColor: .orange) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Step Delay (Jeda Antar Aksi)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Default pause duration between sequential macro steps so target applications process events smoothly.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(white: 0.65))
                    }
                    Spacer()
                    Text(String(format: "%.2f s (%d ms)", defaultStepDelay, Int(defaultStepDelay * 1000)))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                HStack(spacing: 12) {
                    Slider(value: $defaultStepDelay, in: 0.01...0.30, step: 0.01)
                    Button("Reset (0.05s)") {
                        defaultStepDelay = 0.05
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                cardDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Max Loop Safety Limit (Batas Loop Aman)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Safety ceiling for 'Do Again' repeat loops to prevent infinite freezes.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(white: 0.65))
                    }
                    Spacer()
                    Picker("", selection: $maxLoopIterations) {
                        Text("100 cycles").tag(100)
                        Text("500 cycles").tag(500)
                        Text("1,000 cycles").tag(1000)
                        Text("5,000 cycles").tag(5000)
                    }
                    .frame(width: 130)
                }
            }
        }

        // Audio & Visual Feedback Card
        settingsCard(title: "Audio & Visual Feedback", icon: "speaker.wave.2.fill", iconColor: .yellow) {
            VStack(spacing: 0) {
                toggleRow(
                    title: "Sound on Macro Completion",
                    subtitle: "Plays a subtle audio tick sound when a triggered macro finishes all steps.",
                    isOn: $soundOnComplete
                )

                cardDivider()

                toggleRow(
                    title: "Sound on Action Error",
                    subtitle: "Plays an error beep if an action fails (e.g. image target not found or coordinate invalid).",
                    isOn: $soundOnError
                )

                cardDivider()

                toggleRow(
                    title: "Visual OSD Feedback",
                    subtitle: "Briefly flashes a subtle on-screen indicator when a global macro shortcut is pressed.",
                    isOn: $showOSDFeedback
                )
            }
        }

        // Hardware Controls Card
        settingsCard(title: "Hardware Display Controls", icon: "sun.max.fill", iconColor: .yellow) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS DisplayServices Hardware Engine")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Direct GPU display brightness control for Apple Silicon and Intel Mac screens.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(white: 0.65))
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("Operational")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════
    // 4. APPEARANCE & EDITOR PANE
    // ═══════════════════════════════════════════════════
    @ViewBuilder
    private func renderAppearanceSettings() -> some View {
        // Macro Editor Display Card
        settingsCard(title: "Macro Editor Display", icon: "list.number", iconColor: .purple) {
            VStack(spacing: 0) {
                toggleRow(
                    title: "Show Step Number Badges (Nomor Urut Aksi)",
                    subtitle: "Displays sequential step numbering (1, 2, 3...) on each action card in the builder.",
                    isOn: $showActionIndices
                )

                cardDivider()

                toggleRow(
                    title: "Compact Action Cards Layout",
                    subtitle: "Reduces vertical padding for viewing complex multi-action macros with minimal scrolling.",
                    isOn: $compactActionCards
                )

                cardDivider()

                toggleRow(
                    title: "Show Shortcut Badges in Sidebar",
                    subtitle: "Shows hotkey badges (e.g. ⇧+F1) directly next to macro names in the sidebar.",
                    isOn: $showTriggerBadgesInSidebar
                )
            }
        }

        // Persistence & Storage Card
        settingsCard(title: "Persistence & Formatting", icon: "doc.text.fill", iconColor: .indigo) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Macro File Format: .shortking (JSON)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Standardized JSON structure compatible with Git version control and text editors.")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(white: 0.65))
                    }
                    Spacer()
                    Text("Auto-Save Active ✅")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════
    // 5. ABOUT SHORTKING PANE
    // ═══════════════════════════════════════════════════
    @ViewBuilder
    private func renderAboutSettings() -> some View {
        // App Identity Card
        settingsCard(title: "Application Information", icon: "crown.fill", iconColor: .yellow) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.15, green: 0.55, blue: 0.95), Color(red: 0.45, green: 0.20, blue: 0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)
                    Text("👑")
                        .font(.system(size: 30))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ShortKing")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("Version 1.0 (macOS Native)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Compact & High-Performance macOS Macro Automation Engine powered by Carbon HotKeys & Quartz Event Simulation.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }

        // Quick Links & Actions Card
        settingsCard(title: "Documentation & Resources", icon: "book.fill", iconColor: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        let learnURL = URL(fileURLWithPath: "/Users/tonytoelle/Documents/PROJECTS/RedMunky - ShortKing/LEARN")
                        NSWorkspace.shared.open(learnURL)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "book.pages.fill")
                            Text("Open Documentation (LEARN)")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        NSWorkspace.shared.open(store.watchDirectoryURL)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.fill")
                            Text("Open Macros Folder")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        AppDelegate.shared?.relaunchApp()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                            Text("Relaunch App")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("Emergency Stop Hotkey: ⌘ + Control + Shift + X")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // ═══════════════════════════════════════════════════
    // REUSABLE UI BUILDER HELPERS
    // ═══════════════════════════════════════════════════

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Color(white: 0.9))
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(14)
            .background(Color(white: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundColor(.white)
                    .font(.system(size: 12.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(white: 0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func cardDivider() -> some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusBadge(isGranted: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isGranted ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(isGranted ? "Granted ✅" : "Permission Required ❌")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isGranted ? .green : .red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isGranted ? Color.green : Color.red).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// ═══════════════════════════════════════════════════
// SIDEBAR CATEGORY ROW (Clean, Frameless, matching MainEditorView)
// ═══════════════════════════════════════════════════
private struct SidebarCategoryRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: category.iconName)
                    .foregroundColor(isSelected ? .white : category.iconColor)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)

                Text(category.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : Color(white: 0.90))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color.accentColor
                    : (isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
