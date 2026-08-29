import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

struct MacroInspectorView: View {
    @ObservedObject var macro: MacroItem
    @ObservedObject var store = MacroStore.shared
    @ObservedObject var permissions = PermissionManager.shared
    let detailWidth: CGFloat

    @State private var isDirty = false
    @State private var tempName: String = ""
    @State private var keyMonitor: Any? = nil
    @State private var isTriggerCollapsed = false
    @State private var isActionsCollapsed = false
    @AppStorage("isActionDrawerOpen") private var isActionDrawerOpen = false
    @State private var isShowingTriggerPopover = false
    @State private var isEditingName = false
    @State private var activeActionTarget: ActionTarget = .primary
    
    enum ActionTarget { case primary, alternate }

    @FocusState private var isNameFocused: Bool
    
    @AppStorage("alwaysOnTop") private var alwaysOnTop: Bool = false
    
    @State private var scrollOffset: CGFloat = 0
    
    var scrollProgress: CGFloat {
        let offset = max(0, -scrollOffset)
        let threshold: CGFloat = 40.0
        return min(1.0, offset / threshold)
    }
    
    // Detect if any trigger is key switch
    var hasKeySwitchTrigger: Bool {
        macro.triggers.contains { $0.mode == .keySwitch }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                headerSection
                triggerSection
                actionsSection
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
            .padding(.top, 12)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            tempName = macro.fileName.replacingOccurrences(of: ".shortking", with: "")
            isEditingName = false
        }
        .onChange(of: macro.id) { _, _ in
            tempName = macro.fileName.replacingOccurrences(of: ".shortking", with: "")
            isEditingName = false
            store.selectedActionID = nil
        }
        .onChange(of: macro.fileName) { _, newFileName in
            tempName = newFileName.replacingOccurrences(of: ".shortking", with: "")
            isEditingName = false
        }
    }

    // MARK: - Header Section
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                if isEditingName {
                    TextField("Macro Name", text: $tempName)
                        .font(.system(size: 24, weight: .bold))
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(minWidth: 80, maxWidth: 320)
                        .focused($isNameFocused)
                        .onSubmit {
                            store.renameMacro(macro, newBaseName: tempName)
                            isNameFocused = false
                            isEditingName = false
                        }
                        .onChange(of: isNameFocused) { _, focused in
                            if !focused {
                                store.renameMacro(macro, newBaseName: tempName)
                                isEditingName = false
                            }
                        }
                        .onAppear {
                            isNameFocused = true
                        }
                } else {
                    Text(tempName.isEmpty ? "Untitled Macro" : tempName.capitalized)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            isEditingName = true
                        }
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer()

            if !permissions.isAccessibilityGranted {
                Button {
                    permissions.openAccessibilitySettings()
                } label: {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Accessibility permission required to simulate keystrokes and mouse clicks")
            }

            if isDirty {
                Button {
                    store.saveMacro(macro)
                    isDirty = false
                } label: {
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }

            Button {
                store.runMacro(macro)
            } label: {
                Label("Test Run", systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                alwaysOnTop.toggle()
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.updateAlwaysOnTop()
                }
            } label: {
                Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(alwaysOnTop ? .accentColor : .secondary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Always on Top")
        }
        .padding(.vertical, 4)
        .background(WindowDragView())
    }

    // MARK: - Trigger Section
    @ViewBuilder
    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trigger")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
                Spacer()
                Image(systemName: isTriggerCollapsed ? "chevron.right" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10, weight: .bold))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isTriggerCollapsed.toggle()
                }
            }

            if !isTriggerCollapsed {
                ForEach(macro.triggers) { trig in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(trig.mode.color)
                                .frame(width: 32, height: 32)
                            Image(systemName: trig.mode.iconName)
                                .foregroundColor(.white)
                                .font(.system(size: 15, weight: .semibold))
                        }

                        if detailWidth > 320 {
                            Text(trig.mode.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                        }

                        Spacer()

                        HotKeyRecorder(trigger: triggerBinding(for: trig)) {
                            store.saveMacro(macro)
                            isDirty = false
                        }

                        // Mode toggle button
                        Button {
                            store.registerUndoState(for: macro)
                            if let idx = macro.triggers.firstIndex(where: { $0.id == trig.id }) {
                                macro.triggers[idx].mode = macro.triggers[idx].mode == .keyPress ? .keySwitch : .keyPress
                                store.saveMacro(macro)
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(trig.mode == .keySwitch ? Color(red: 0.1, green: 0.65, blue: 0.7) : .secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(trig.mode == .keyPress ? "Switch to Key Switch mode" : "Switch to Key Press mode")

                        if macro.triggers.count > 1 {
                            Button {
                                store.registerUndoState(for: macro)
                                macro.triggers.removeAll(where: { $0.id == trig.id })
                                store.saveMacro(macro)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Centered + button for adding triggers
                HStack {
                    Spacer()
                    Button {
                        isShowingTriggerPopover.toggle()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isShowingTriggerPopover, arrowEdge: .bottom) {
                        VStack(spacing: 4) {
                            ForEach(TriggerMode.allCases, id: \.self) { mode in
                                Button {
                                    store.registerUndoState(for: macro)
                                    macro.triggers.append(Trigger(keyCode: 17, requireCmd: true, requireShift: true, requireOption: false, requireControl: false, mode: mode))
                                    store.saveMacro(macro)
                                    isShowingTriggerPopover = false
                                } label: {
                                    HStack(spacing: 8) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(mode.color)
                                                .frame(width: 22, height: 22)
                                            Image(systemName: mode.iconName)
                                                .foregroundColor(.white)
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        Text(mode.displayName)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .frame(width: 160)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(white: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var alternateActionItemsBinding: Binding<[MacroActionItem]> {
        Binding(
            get: {
                if let idx = self.macro.triggers.firstIndex(where: { $0.mode == .keySwitch }) {
                    return self.macro.triggers[idx].alternateActionItems
                }
                return []
            },
            set: { newValue in
                if let idx = self.macro.triggers.firstIndex(where: { $0.mode == .keySwitch }) {
                    self.macro.triggers[idx].alternateActionItems = newValue
                    self.store.saveMacro(self.macro)
                }
            }
        )
    }

    @ViewBuilder
    private var primaryActionsArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 12))
                Text("Primary Action")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            DraggableActionList(actionItems: $macro.actionItems, onSave: {
                store.saveMacro(macro)
            }, onInsertTemplate: { typeName, targetIndex in
                insertAction(typeName: typeName, targetIndex: targetIndex, isAlternate: false)
            }, detailWidth: detailWidth)
        }
        .padding(10)
        .background(Color.white.opacity(activeActionTarget == .primary ? 0.03 : 0.01))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(activeActionTarget == .primary ? 0.3 : 0.1), lineWidth: 1)
        )
        .onTapGesture {
            activeActionTarget = .primary
        }
    }

    @ViewBuilder
    private var alternateActionsArea: some View {
        if macro.triggers.contains(where: { $0.mode == .keySwitch }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundColor(Color(red: 0.1, green: 0.65, blue: 0.7))
                        .font(.system(size: 12))
                    Text("Alternate Action")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                DraggableActionList(actionItems: alternateActionItemsBinding, onSave: {
                    store.saveMacro(macro)
                }, onInsertTemplate: { typeName, targetIndex in
                    insertAction(typeName: typeName, targetIndex: targetIndex, isAlternate: true)
                }, detailWidth: detailWidth)
            }
            .padding(10)
            .background(Color.white.opacity(activeActionTarget == .alternate ? 0.03 : 0.01))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.1, green: 0.65, blue: 0.7).opacity(activeActionTarget == .alternate ? 0.3 : 0.1), lineWidth: 1)
            )
            .onTapGesture {
                activeActionTarget = .alternate
            }
        }
    }

    @ViewBuilder
    private var actionSelectionDrawer: some View {
        SpotlightSearchBar(placeholder: "Search actions...", items: SearchableActionDef.allActions, width: detailWidth) { actionDef in
            let isAlt = hasKeySwitchTrigger && activeActionTarget == .alternate
            let tIdx = isAlt ? (macro.triggers.first(where: { $0.mode == .keySwitch })?.alternateActionItems.count ?? 0) : macro.actionItems.count
            insertAction(typeName: actionDef.title, targetIndex: tIdx, isAlternate: isAlt)
        }
    }

    // MARK: - Actions Section
    @ViewBuilder
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Actions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: isActionsCollapsed ? "chevron.right" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10, weight: .bold))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isActionsCollapsed.toggle()
                }
            }

            if !isActionsCollapsed {
                if hasKeySwitchTrigger {
                    // Two sub-areas: Actions and Alternate Actions
                    VStack(alignment: .leading, spacing: 16) {
                        primaryActionsArea
                        alternateActionsArea
                    }
                } else {
                    // Single actions area
                    DraggableActionList(actionItems: $macro.actionItems, onSave: {
                        store.saveMacro(macro)
                    }, onInsertTemplate: { typeName, targetIndex in
                        insertAction(typeName: typeName, targetIndex: targetIndex, isAlternate: false)
                    }, detailWidth: detailWidth)
                }

                actionSelectionDrawer
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(white: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func insertAction(typeName: String, targetIndex: Int, isAlternate: Bool) {
        store.registerUndoState(for: macro)
        
        let newAction: MacroAction
        switch typeName {
        case "Path": newAction = .path(points: [])
        case "Left Click": newAction = .click(point: .zero, button: .left)
        case "Right Click": newAction = .click(point: .zero, button: .right)
        case "Drag": newAction = .drag(start: .zero, end: .zero)
        case "Move Cursor": newAction = .moveCursor(point: .zero)
        case "Delay": newAction = .delay(ms: 300)
        case "Text": newAction = .typeText(text: "Hello ShortKing")
        case "Key": newAction = .pressKey(keyCode: 36)
        case "Do Again": newAction = .doAgain(target: .origin)
        case "Group": newAction = .group(name: "New Group", actions: [])
        case "Custom": newAction = .customAction(script: "osascript -e 'set volume output volume (output volume of (get volume settings) + 6)'")
        case "Open File": newAction = .openFile(path: "")
        case "Vol Up": newAction = .volumeUp
        case "Vol Down": newAction = .volumeDown
        case "Brit Up": newAction = .brightnessUp
        case "Brit Down": newAction = .brightnessDown
        case "Window Transform": newAction = .windowTransform(p1: .zero, p2: .zero, p3: .zero, p4: .zero)
        case "Origin": newAction = .originAction(type: .cursor)
        default: newAction = .delay(ms: 300)
        }
        
        let newActionItem = MacroActionItem(action: newAction)
        
        if isAlternate {
            if let idx = macro.triggers.firstIndex(where: { $0.mode == .keySwitch }) {
                var altItems = macro.triggers[idx].alternateActionItems
                if targetIndex >= altItems.count {
                    altItems.append(newActionItem)
                } else {
                    altItems.insert(newActionItem, at: targetIndex)
                }
                macro.triggers[idx].alternateActionItems = altItems
                store.saveMacro(macro)
                
                triggerCaptureIfNeeded(for: newActionItem, index: targetIndex, isAlternate: true, switchTriggerIndex: idx)
            }
        } else {
            if targetIndex >= macro.actionItems.count {
                macro.actionItems.append(newActionItem)
            } else {
                macro.actionItems.insert(newActionItem, at: targetIndex)
            }
            store.saveMacro(macro)
            
            triggerCaptureIfNeeded(for: newActionItem, index: targetIndex, isAlternate: false, switchTriggerIndex: nil)
        }
    }

    private func triggerCaptureIfNeeded(for actionItem: MacroActionItem, index: Int, isAlternate: Bool, switchTriggerIndex: Int?) {
        switch actionItem.action {
        case .path:
            CaptureOverlayWindow.shared = CaptureOverlayWindow(
                initialPoints: [],
                defaultType: .move,
                onSequenceCaptured: { pts in
                    if pts.isEmpty {
                        removeActionItem(id: actionItem.id, isAlternate: isAlternate, switchTriggerIndex: switchTriggerIndex)
                    } else {
                        updateActionItem(id: actionItem.id, action: .path(points: pts), isAlternate: isAlternate, switchTriggerIndex: switchTriggerIndex)
                    }
                },
                onSequenceRealTime: { tempPts in
                    updateActionItem(id: actionItem.id, action: .path(points: tempPts), isAlternate: isAlternate, switchTriggerIndex: switchTriggerIndex)
                }
            )
        case .click(let pt, let button):
            CaptureOverlayWindow.shared = CaptureOverlayWindow(
                mode: .click(button: button, initialPoint: pt == .zero ? nil : pt),
                onClickCaptured: { capturedPt in
                    updateActionItem(id: actionItem.id, action: .click(point: capturedPt, button: button), isAlternate: isAlternate, switchTriggerIndex: switchTriggerIndex)
                },
                onClickRealTime: { _ in }
            )
        case .drag(let start, let end):
            CaptureOverlayWindow.shared = CaptureOverlayWindow(
                mode: .drag(initialStart: start == .zero ? nil : start, initialEnd: end == .zero ? nil : end),
                onDragCaptured: { capturedStart, capturedEnd in
                    updateActionItem(id: actionItem.id, action: .drag(start: capturedStart, end: capturedEnd), isAlternate: isAlternate, switchTriggerIndex: switchTriggerIndex)
                },
                onDragRealTime: { _, _ in }
            )
        case .moveCursor(let pt):
            CaptureOverlayWindow.shared = CaptureOverlayWindow(
                mode: .click(button: .left, initialPoint: pt == .zero ? nil : pt),
                onClickCaptured: { capturedPt in
                    updateActionItem(id: actionItem.id, action: .moveCursor(point: capturedPt), isAlternate: isAlternate, switchTriggerIndex: switchTriggerIndex)
                },
                onClickRealTime: { _ in }
            )
        case .windowTransform(let p1, _, let p3, _):
            let initialPoints: [SequencePoint] = (p1 == .zero && p3 == .zero) ? [] : [
                SequencePoint(point: p1, type: .click),
                SequencePoint(point: p3, type: .click)
            ]
            CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .windowTransform(initialPoints: initialPoints)) { np1, np2, np3, np4 in
                updateActionItem(id: actionItem.id, action: .windowTransform(p1: np1, p2: np2, p3: np3, p4: np4), isAlternate: isAlternate, switchTriggerIndex: switchTriggerIndex)
            }
        default:
            break
        }
    }
    
    private func removeActionItem(id: UUID, isAlternate: Bool, switchTriggerIndex: Int?) {
        if isAlternate, let idx = switchTriggerIndex {
            macro.triggers[idx].alternateActionItems.removeAll(where: { $0.id == id })
        } else {
            macro.actionItems.removeAll(where: { $0.id == id })
        }
        store.saveMacro(macro)
    }
    
    private func updateActionItem(id: UUID, action: MacroAction, isAlternate: Bool, switchTriggerIndex: Int?) {
        if isAlternate, let idx = switchTriggerIndex {
            if let aIdx = macro.triggers[idx].alternateActionItems.firstIndex(where: { $0.id == id }) {
                macro.triggers[idx].alternateActionItems[aIdx].action = action
                store.saveMacro(macro)
            }
        } else {
            if let aIdx = macro.actionItems.firstIndex(where: { $0.id == id }) {
                macro.actionItems[aIdx].action = action
                store.saveMacro(macro)
            }
        }
    }

    private func triggerBinding(for trig: Trigger) -> Binding<Trigger> {
        Binding(
            get: { macro.triggers.first(where: { $0.id == trig.id }) ?? trig },
            set: { newValue in
                if let index = macro.triggers.firstIndex(where: { $0.id == trig.id }) {
                    store.registerUndoState(for: macro)
                    macro.triggers[index] = newValue
                    store.saveMacro(macro)
                }
            }
        )
    }
}

// ==========================================
// MARK: - Permission Banner View
// ==========================================
struct PermissionBannerView: View {
    @ObservedObject var permissions = PermissionManager.shared

    var body: some View {
        if !permissions.isAccessibilityGranted {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Izin macOS Diperlukan (Accessibility Permission)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    Text("ShortKing membutuhkan izin Aksesibilitas agar dapat mensimulasikan klik mouse, drag, dan shortcut keyboard.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Minta Ulang Izin") {
                    permissions.requestAccessibilityPrompt()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Buka System Settings") {
                    permissions.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.12))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.yellow.opacity(0.3)), alignment: .bottom)
        }
    }
}

// ==========================================
// MARK: - ShortKing Native Settings
// ==========================================

struct FolderInspectorView: View {
    let folderURL: URL
    let initialConfig: FolderConfig
    let itemCount: Int
    @ObservedObject var store = MacroStore.shared

    @State private var folderName: String = ""
    @State private var config: FolderConfig = FolderConfig()
    @State private var isShowingRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var isAppearanceExpanded: Bool = false
    @State private var isEditingFolderName: Bool = false
    @FocusState private var isFolderNameFocused: Bool
    @State private var tempFolderName: String = ""

    let availableColors: [(name: String, label: String, color: Color)] = [
        ("blue", "Blue", Color(red: 0.25, green: 0.65, blue: 0.95)),
        ("purple", "Purple", Color(red: 0.68, green: 0.45, blue: 0.95)),
        ("orange", "Orange", Color(red: 0.98, green: 0.58, blue: 0.20)),
        ("green", "Green", Color(red: 0.30, green: 0.80, blue: 0.45)),
        ("pink", "Pink", Color(red: 0.98, green: 0.45, blue: 0.65)),
        ("indigo", "Indigo", Color(red: 0.42, green: 0.38, blue: 0.88)),
        ("red", "Red", Color(red: 0.95, green: 0.30, blue: 0.30)),
        ("yellow", "Yellow", Color(red: 0.98, green: 0.80, blue: 0.20)),
        ("teal", "Teal", Color(red: 0.20, green: 0.75, blue: 0.80)),
        ("gray", "Gray", Color(white: 0.60))
    ]

    let availableIcons: [String] = [
        "folder.fill", "folder.badge.gearshape", "star.fill", "bookmark.fill", "tag.fill",
        "film.fill", "video.fill", "waveform", "music.note", "camera.fill", "photo.fill",
        "chevron.left.forwardslash.chevron.right", "terminal.fill", "cpu.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "paintpalette.fill", "paintbrush.fill", "wand.and.stars", "pencil.and.ruler.fill", "crop",
        "briefcase.fill", "doc.text.fill", "chart.bar.fill", "envelope.fill", "calendar",
        "gamecontroller.fill", "bolt.fill", "keyboard.fill", "slider.horizontal.3", "flame.fill"
    ]

    @AppStorage("alwaysOnTop") private var alwaysOnTop: Bool = false
    
    @State private var scrollOffset: CGFloat = 0
    
    var scrollProgress: CGFloat {
        let offset = max(0, -scrollOffset)
        let threshold: CGFloat = 40.0
        return min(1.0, offset / threshold)
    }

    var runningApps: [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            $0.bundleIdentifier != nil &&
            $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
            $0.localizedName != nil
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Top Action Bar
                HStack {
                    Spacer()
                    Button {
                        alwaysOnTop.toggle()
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.updateAlwaysOnTop()
                        }
                    } label: {
                        Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(alwaysOnTop ? .accentColor : .secondary)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Always on Top")
                }
                .background(WindowDragView())

                // ═══════════════════════════════════════════════════
                // CENTERED HEADER
                // ═══════════════════════════════════════════════════
                VStack(spacing: 10) {
                    // Big Squircle Icon
                    Button {
                        withAnimation { isAppearanceExpanded.toggle() }
                    } label: {
                        let appBundleId: String? = {
                            if let customId = config.customAppIconBundleId, !customId.isEmpty {
                                return customId
                            }
                            if config.isRestrictedToApps && config.targetApps.count == 1 {
                                return config.targetApps[0].bundleId
                            }
                            return nil
                        }()
                        
                        if let bundleId = appBundleId,
                           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
                           let nsImage = NSWorkspace.shared.icon(forFile: appURL.path) as NSImage? {
                            Image(nsImage: nsImage)
                                .resizable()
                                .frame(width: 112, height: 112)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(config.color.opacity(0.18))
                                    .frame(width: 112, height: 112)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                                            .stroke(config.color.opacity(0.35), lineWidth: 1.5)
                                    )
                                Image(systemName: config.iconName)
                                    .font(.system(size: 52, weight: .medium))
                                    .foregroundColor(config.color)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Click to change appearance")

                    // Folder Name (Double-click to inline edit)
                    if isEditingFolderName {
                        TextField("Folder Name", text: $tempFolderName)
                            .font(.system(size: 20, weight: .bold))
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .focused($isFolderNameFocused)
                            .onSubmit {
                                if !tempFolderName.isEmpty && tempFolderName != folderName {
                                    store.renameFolder(at: folderURL, newName: tempFolderName)
                                    folderName = tempFolderName
                                }
                                isFolderNameFocused = false
                                isEditingFolderName = false
                            }
                            .onChange(of: isFolderNameFocused) { _, focused in
                                if !focused {
                                    if !tempFolderName.isEmpty && tempFolderName != folderName {
                                        store.renameFolder(at: folderURL, newName: tempFolderName)
                                        folderName = tempFolderName
                                    }
                                    isEditingFolderName = false
                                }
                            }
                            .onAppear {
                                isFolderNameFocused = true
                            }
                    } else {
                        Text(folderName.toTitleCase())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                tempFolderName = folderName
                                isEditingFolderName = true
                            }
                    }

                    // Macro Count
                    Text("\(itemCount) Macros")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.70))

                    // Edit Macros (Selects first macro inside this folder)
                    Button {
                        if let node = findFolderNode(path: folderURL.path, in: store.treeNodes) {
                            if case .folder(_, _, _, let children) = node {
                                if let firstMacro = findFirstMacro(in: children) {
                                    store.selectedFilePath = firstMacro.fileURL.path
                                    store.selectedFolderPath = nil
                                }
                            }
                        }
                    } label: {
                        Text("Edit Macros")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(config.color)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)

                // ═══════════════════════════════════════════════════
                // FOLDER STATUS CARD
                // ═══════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: config.isEnabled ? "play.circle.fill" : "pause.circle.fill")
                            .foregroundColor(config.isEnabled ? .green : .orange)
                            .font(.system(size: 14, weight: .semibold))
                        Text(config.isEnabled ? "Folder is Active" : "Folder is Disabled")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { config.isEnabled },
                            set: { newValue in
                                config.isEnabled = newValue
                                saveConfig()
                            }
                        ))
                        .toggleStyle(.switch)
                    }

                    Text("When disabled, all macro shortcuts inside this folder are temporarily suspended.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(white: 0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Color(white: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // ═══════════════════════════════════════════════════
                // TARGET APPLICATIONS CARD
                // ═══════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "macwindow.on.rectangle")
                            .foregroundColor(Color(red: 0.30, green: 0.65, blue: 0.95))
                            .font(.system(size: 14, weight: .semibold))
                        Text("Target Applications")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: $config.isRestrictedToApps)
                            .toggleStyle(.switch)
                            .onChange(of: config.isRestrictedToApps) {
                                saveConfig()
                            }
                    }

                    Text("When enabled, shortcuts inside this folder will only run when one of the specified applications is active and focused.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(white: 0.55))
                        .fixedSize(horizontal: false, vertical: true)

                    if config.isRestrictedToApps {
                        // Applications List
                        if !config.targetApps.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(config.targetApps) { target in
                                    HStack(spacing: 12) {
                                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleId) {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                                .resizable()
                                                .frame(width: 22, height: 22)
                                        } else {
                                            Image(systemName: "app.fill")
                                                .foregroundColor(.accentColor)
                                                .frame(width: 22, height: 22)
                                        }

                                        Text(target.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)

                                        Spacer()

                                        Button {
                                            config.targetApps.removeAll { $0.bundleId == target.bundleId }
                                            saveConfig()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(Color(white: 0.45))
                                                .font(.system(size: 15))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove application")
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color(white: 0.20))
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                            }
                        }

                        // Minimalist "+ Add" Button
                        Menu {
                            Section("Running Applications") {
                                ForEach(runningApps, id: \.processIdentifier) { app in
                                    if let bId = app.bundleIdentifier, let name = app.localizedName {
                                        Button {
                                            if !config.targetApps.contains(where: { $0.bundleId == bId }) {
                                                config.targetApps.append(TargetApp(name: name, bundleId: bId))
                                                saveConfig()
                                            }
                                        } label: {
                                            if let icon = app.icon {
                                                Image(nsImage: icon)
                                            }
                                            Text(name)
                                        }
                                    }
                                }
                            }

                            Divider()

                            Button {
                                pickAppFromDisk()
                            } label: {
                                Label("Browse /Applications…", systemImage: "folder")
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 13))
                                Text("Add")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(Color(white: 0.80))
                        }
                        .menuStyle(.borderlessButton)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(Color(white: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // ═══════════════════════════════════════════════════
                // FOLDER APPEARANCE CARD
                // ═══════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAppearanceExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "paintpalette.fill")
                                .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.65))
                                .font(.system(size: 14, weight: .semibold))
                            Text("Folder Appearance")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: isAppearanceExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(white: 0.50))
                        }
                    }
                    .buttonStyle(.plain)

                    if isAppearanceExpanded {
                        // Color Palette
                        VStack(alignment: .leading, spacing: 8) {
                            Text("COLOR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(white: 0.5))

                            HStack(spacing: 10) {
                                ForEach(availableColors, id: \.name) { item in
                                    Button {
                                        config.colorName = item.name
                                        saveConfig()
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(item.color)
                                                .frame(width: 26, height: 26)
                                            if config.colorName.lowercased() == item.name.lowercased() {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 4)

                        Divider().background(Color(white: 0.25))

                        // Icon Grid
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ICON")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(white: 0.5))

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                                ForEach(availableIcons, id: \.self) { icon in
                                    let isSelected = config.iconName == icon && config.customAppIconBundleId == nil
                                    Button {
                                        config.customAppIconBundleId = nil
                                        config.iconName = icon
                                        saveConfig()
                                    } label: {
                                        ZStack {
                                            Image(systemName: icon)
                                                .font(.system(size: 16))
                                                .foregroundColor(isSelected ? config.color : Color(white: 0.85))
                                                .frame(width: 38, height: 38)
                                                .background(Color.clear)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .stroke(isSelected ? config.color : Color.clear, lineWidth: 1.5)
                                                )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        Divider().background(Color(white: 0.25))

                        // Custom App Icon from Running Apps
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("APP ICON (RUNNING APPS)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(white: 0.5))
                                Spacer()
                                if config.customAppIconBundleId != nil {
                                    Button("Reset to Folder Icon") {
                                        config.customAppIconBundleId = nil
                                        saveConfig()
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .buttonStyle(.plain)
                                    .foregroundColor(.red)
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(runningApps, id: \.processIdentifier) { app in
                                        if let bId = app.bundleIdentifier, let name = app.localizedName, let icon = app.icon {
                                            let isSelected = config.customAppIconBundleId == bId
                                            Button {
                                                config.customAppIconBundleId = bId
                                                saveConfig()
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Image(nsImage: icon)
                                                        .resizable()
                                                        .frame(width: 36, height: 36)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                                .stroke(isSelected ? config.color : Color.clear, lineWidth: 2)
                                                        )
                                                    Text(name)
                                                        .font(.system(size: 9))
                                                        .foregroundColor(isSelected ? .white : Color(white: 0.7))
                                                        .lineLimit(1)
                                                        .frame(width: 54)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(white: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 12)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            folderName = folderURL.lastPathComponent
            tempFolderName = folderName
            config = initialConfig
        }
        .onChange(of: folderURL) { _, newURL in
            folderName = newURL.lastPathComponent
            tempFolderName = folderName
            config = store.loadFolderConfig(at: newURL)
        }
    }

    private func saveConfig() {
        store.saveFolderConfig(config, for: folderURL)
    }

    private func pickAppFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        if panel.runModal() == .OK, let url = panel.url {
            let bundle = Bundle(url: url)
            let bundleId = bundle?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
            let name = bundle?.infoDictionary?["CFBundleName"] as? String ??
                       bundle?.infoDictionary?["CFBundleDisplayName"] as? String ??
                       url.deletingPathExtension().lastPathComponent
            
            if !config.targetApps.contains(where: { $0.bundleId == bundleId }) {
                config.targetApps.append(TargetApp(name: name, bundleId: bundleId))
                saveConfig()
            }
        }
    }

    private func findFolderNode(path: String, in nodes: [FileSystemNode]) -> FileSystemNode? {
        for node in nodes {
            switch node {
            case .folder(_, let url, _, let children):
                if url.path == path { return node }
                if let found = findFolderNode(path: path, in: children) { return found }
            case .macro:
                break
            }
        }
        return nil
    }

    private func findFirstMacro(in nodes: [FileSystemNode]) -> MacroItem? {
        for node in nodes {
            switch node {
            case .macro(let item):
                return item
            case .folder(_, _, _, let children):
                if let found = findFirstMacro(in: children) {
                    return found
                }
            }
        }
        return nil
    }
}

// ==========================================
// MARK: - Native Visual Effect View (macOS Tahoe Liquid Glass)
// ==========================================
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// ==========================================
// MARK: - Sidebar Tree Node View (macOS Tahoe / Finder Style)
// ==========================================
struct FolderPromptState: Identifiable {
    let id = UUID()
    let isNewFolder: Bool
    let targetURL: URL?
    var initialName: String
}

struct SidebarNodeView: View {
    let node: FileSystemNode
    let depth: Int
    @Binding var expandedFolders: Set<String>
    @Binding var selectedPaths: Set<String>
    @ObservedObject var store = MacroStore.shared
    var onSelect: (String, NSEvent.ModifierFlags) -> Void
    var onPromptFolder: (Bool, URL?, String) -> Void

    @State private var isDropTarget = false
    @State private var isHovered = false

    var body: some View {
        switch node {
        case .folder(let name, let url, let config, let children):
            let isSelected = selectedPaths.contains(url.path) || store.selectedFolderPath == url.path
            let isExpanded = Binding<Bool>(
                get: { expandedFolders.contains(url.path) },
                set: { val in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if val {
                            _ = expandedFolders.insert(url.path)
                        } else {
                            _ = expandedFolders.remove(url.path)
                        }
                    }
                }
            )
            
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(children) { child in
                    SidebarNodeView(
                        node: child,
                        depth: depth + 1,
                        expandedFolders: $expandedFolders,
                        selectedPaths: $selectedPaths,
                        onSelect: onSelect,
                        onPromptFolder: onPromptFolder
                    )
                }
            } label: {
                HStack(spacing: 6) {
                    let appBundleId: String? = {
                        if let customId = config.customAppIconBundleId, !customId.isEmpty {
                            return customId
                        }
                        if config.isRestrictedToApps && config.targetApps.count == 1 {
                            return config.targetApps[0].bundleId
                        }
                        return nil
                    }()
                    
                    if let bundleId = appBundleId,
                       let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
                       let nsImage = NSWorkspace.shared.icon(forFile: appURL.path) as NSImage? {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .opacity(config.isEnabled ? 1.0 : 0.4)
                    } else {
                        Image(systemName: config.iconName)
                            .foregroundColor(isSelected ? Color.accentColor : (config.isEnabled ? config.color : Color.gray.opacity(0.5)))
                            .font(.system(size: 14))
                            .frame(width: 18, height: 18)
                    }

                    Text(name.toTitleCase())
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? Color.accentColor : (config.isEnabled ? Color(white: 0.92) : Color.secondary.opacity(0.7)))
                        .strikethrough(!config.isEnabled, color: Color.secondary.opacity(0.6))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(children.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(isSelected ? Color.accentColor : Color(white: 0.55))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    let flags = NSEvent.modifierFlags
                    if flags.contains(.command) || flags.contains(.shift) {
                        onSelect(url.path, flags)
                    } else {
                        store.selectedFolderPath = url.path
                        store.selectedFilePath = nil
                        onSelect(url.path, flags)
                    }
                }
                .onDrag {
                    let pathsToDrag = selectedPaths.contains(url.path) ? Array(selectedPaths) : [url.path]
                    return NSItemProvider(object: pathsToDrag.joined(separator: "\n") as NSString)
                }
                .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isDropTarget) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                            guard let str = string as? String else { return }
                            let paths = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                            DispatchQueue.main.async {
                                store.moveItems(paths: paths, toFolder: url)
                            }
                        }
                    }
                    return true
                }
                .contextMenu {
                    Button {
                        store.selectedFolderPath = url.path
                        store.selectedFilePath = nil
                    } label: {
                        Label("Folder Settings…", systemImage: "gearshape")
                    }

                    Button {
                        var newConfig = config
                        newConfig.isEnabled.toggle()
                        store.saveFolderConfig(newConfig, for: url)
                    } label: {
                        if config.isEnabled {
                            Label("Disable Folder", systemImage: "pause.circle")
                        } else {
                            Label("Enable Folder", systemImage: "play.circle")
                        }
                    }

                    Divider()

                    Button {
                        store.createNewMacro(inFolder: url)
                    } label: {
                        Label("New Macro in Folder", systemImage: "plus.circle")
                    }

                    Button {
                        onPromptFolder(true, url, "")
                    } label: {
                        Label("New Subfolder…", systemImage: "folder.badge.plus")
                    }

                    Divider()

                    if store.copiedMacroURL != nil {
                        Button {
                            store.pasteCopiedMacro(toFolder: url)
                        } label: {
                            Label("Paste Macro", systemImage: "doc.on.clipboard")
                        }
                        Divider()
                    }

                    Button {
                        onPromptFolder(false, url, name)
                    } label: {
                        Label("Rename Folder…", systemImage: "pencil")
                    }

                    Button {
                        store.revealFolderInFinder(url)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Divider()

                    Button(role: .destructive) {
                        store.deleteFolder(at: url)
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                }
                .tag(url.path)
            }

        case .macro(let macro):
            let isSelected = selectedPaths.contains(macro.fileURL.path) || (store.selectedFilePath == macro.fileURL.path && selectedPaths.isEmpty)

            HStack(spacing: 8) {
                let mainAction = macro.actionItems.first?.action
                let iconName = mainAction?.iconName ?? "bolt.fill"
                let iconColor = mainAction?.color ?? squircleColor(for: macro.fileName.hashValue)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(macro.isEnabled ? iconColor : Color.gray.opacity(0.5))
                        .frame(width: 18, height: 18)
                    Image(systemName: iconName)
                        .foregroundColor(.white)
                        .font(.system(size: 9, weight: .bold))
                }

                Text(macro.fileName.replacingOccurrences(of: ".shortking", with: "").toTitleCase())
                    .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? Color.accentColor : (macro.isEnabled ? Color(white: 0.90) : Color.secondary.opacity(0.7)))
                    .strikethrough(!macro.isEnabled, color: Color.secondary.opacity(0.6))
                    .lineLimit(1)

                Spacer()

                if !macro.isEnabled {
                    Text("Off")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                ShortcutBadgeView(trigger: macro.trigger, isDimmedMini: true, isSelected: isSelected)
                    .opacity(isSelected ? 0.6 : (macro.isEnabled ? 1.0 : 0.4))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let flags = NSEvent.modifierFlags
                if flags.contains(.command) || flags.contains(.shift) {
                    onSelect(macro.fileURL.path, flags)
                } else {
                    store.selectedFilePath = macro.fileURL.path
                    store.selectedFolderPath = nil
                    onSelect(macro.fileURL.path, flags)
                }
            }
            .opacity(macro.isEnabled ? 1.0 : 0.65)
            .onDrag {
                let pathsToDrag = selectedPaths.contains(macro.fileURL.path) ? Array(selectedPaths) : [macro.fileURL.path]
                return NSItemProvider(object: pathsToDrag.joined(separator: "\n") as NSString)
            }
            .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isDropTarget) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                        guard let str = string as? String else { return }
                        let paths = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                        DispatchQueue.main.async {
                            let parentFolderURL = macro.fileURL.deletingLastPathComponent()
                            store.moveItems(paths: paths, toFolder: parentFolderURL)
                        }
                    }
                }
                return true
            }
            .contextMenu {
                Button {
                    store.toggleMacroEnabled(macro)
                } label: {
                    if macro.isEnabled {
                        Label("Disable Macro", systemImage: "bolt.slash")
                    } else {
                        Label("Enable Macro", systemImage: "bolt.fill")
                    }
                }
                
                Divider()

                Button {
                    store.runMacro(macro)
                } label: {
                    Label("Run Macro", systemImage: "play.fill")
                }

                Divider()

                Button {
                    store.duplicateMacro(macro)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                
                Button {
                    store.copiedMacroURL = macro.fileURL
                    store.copiedActions = []
                } label: {
                    Label("Copy Macro", systemImage: "doc.on.doc")
                }
                
                if store.copiedMacroURL != nil {
                    Button {
                        let parentFolderURL = macro.fileURL.deletingLastPathComponent()
                        store.pasteCopiedMacro(toFolder: parentFolderURL)
                    } label: {
                        Label("Paste Macro", systemImage: "doc.on.clipboard")
                    }
                }

                Button {
                    store.revealInFinder(macro)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Divider()

                Button(role: .destructive) {
                    if !selectedPaths.isEmpty {
                        store.deleteItems(paths: Array(selectedPaths))
                        selectedPaths.removeAll()
                    } else {
                        store.deleteMacro(macro)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .tag(macro.fileURL.path)
        }
    }

    private func squircleColor(for hash: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.05, green: 0.5, blue: 0.95), // Blue
            Color.purple,
            Color.orange,
            Color.green,
            Color(red: 0.95, green: 0.45, blue: 0.5), // Pink
            Color.indigo,
            Color.teal
        ]
        let idx = abs(hash) % colors.count
        return colors[idx]
    }
}

class DraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
}

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView {
        return DraggableNSView()
    }
    func updateNSView(_ nsView: DraggableNSView, context: Context) {}
}

// ==========================================
// MARK: - Main Editor View (macOS Tahoe Safari / Finder Style)
// ==========================================
struct MainEditorView: View {
    @ObservedObject var store = MacroStore.shared
    @State private var searchText = ""
    @State private var expandedFolders: Set<String> = []
    @State private var selectedPaths: Set<String> = []
    @State private var lastClickedPath: String? = nil
    @State private var isRootDropTarget = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    // Folder modal/alert states
    @State private var folderPrompt: FolderPromptState?
    @State private var folderInputText = ""
    @State private var showingFolderAlert = false
    @FocusState private var isSearchFocused: Bool
    @State private var keyMonitor: Any? = nil
    @AppStorage("alwaysOnTop") private var alwaysOnTop: Bool = false
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 260

    var displayNodes: [FileSystemNode] {
        if searchText.isEmpty {
            return store.treeNodes
        } else {
            return filterTree(nodes: store.treeNodes, query: searchText)
        }
    }

    func filterTree(nodes: [FileSystemNode], query: String) -> [FileSystemNode] {
        var result: [FileSystemNode] = []
        for node in nodes {
            switch node {
            case .folder(let name, let url, let config, let children):
                let matching = filterTree(nodes: children, query: query)
                let nameMatches = fuzzyMatch(query, in: name).matches
                if !matching.isEmpty || nameMatches {
                    result.append(.folder(name: name, url: url, config: config, children: matching))
                }
            case .macro(let item):
                let fileMatches = fuzzyMatch(query, in: item.fileName).matches
                let trigMatches = fuzzyMatch(query, in: item.trigger.displayString).matches
                if fileMatches || trigMatches {
                    result.append(.macro(item: item))
                }
            }
        }
        return result
    }

    func getVisiblePaths(from nodes: [FileSystemNode]) -> [String] {
        var paths: [String] = []
        for node in nodes {
            switch node {
            case .folder(_, let url, _, let children):
                paths.append(url.path)
                if expandedFolders.contains(url.path) {
                    paths.append(contentsOf: getVisiblePaths(from: children))
                }
            case .macro(let item):
                paths.append(item.fileURL.path)
            }
        }
        return paths
    }

    func findFolderInfo(path: String, in nodes: [FileSystemNode]) -> (name: String, url: URL, config: FolderConfig, count: Int)? {
        for node in nodes {
            switch node {
            case .folder(let name, let url, let config, let children):
                if url.path == path {
                    return (name, url, config, children.count)
                }
                if let found = findFolderInfo(path: path, in: children) {
                    return found
                }
            case .macro:
                break
            }
        }
        return nil
    }

    func handleSelect(path: String, modifiers: NSEvent.ModifierFlags) {
        store.focusedPane = .left
        if modifiers.contains(.command) {
            if selectedPaths.contains(path) {
                selectedPaths.remove(path)
            } else {
                selectedPaths.insert(path)
            }
            lastClickedPath = path
        } else if modifiers.contains(.shift), let last = lastClickedPath {
            let allPaths = getVisiblePaths(from: displayNodes)
            if let i1 = allPaths.firstIndex(of: last), let i2 = allPaths.firstIndex(of: path) {
                let range = min(i1, i2)...max(i1, i2)
                for p in allPaths[range] {
                    selectedPaths.insert(p)
                }
            } else {
                selectedPaths.insert(path)
            }
        } else {
            selectedPaths = [path]
            lastClickedPath = path
        }
        
        if let macro = store.macros.first(where: { selectedPaths.contains($0.fileURL.path) }) {
            store.selectedFilePath = macro.fileURL.path
            store.selectedFolderPath = nil
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // LEFT SIDEBAR (macOS Tahoe Safari/Finder Style)
            VStack(alignment: .leading, spacing: 0) {
                // Tahoe Glass Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(isSearchFocused ? .accentColor : .secondary)
                        .font(.system(size: 12, weight: .semibold))
                    TextField("Search macros (⌘F)", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                        .onSubmit {
                            isSearchFocused = false
                        }
                        .tint(.accentColor)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSearchFocused ? Color.accentColor : Color.white.opacity(0.12), lineWidth: 1)
                        .animation(.easeInOut(duration: 0.15), value: isSearchFocused)
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .zIndex(100)

                // Section Header
                HStack {
                    Text("MACROS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.secondary.opacity(0.8))
                        .tracking(0.6)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 4)

                // Hierarchical List (Sidebar style)
                List(selection: $selectedPaths) {
                    if displayNodes.isEmpty {
                        Text(searchText.isEmpty ? "No macros or folders yet" : "No matching macros")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                    } else {
                        ForEach(displayNodes) { node in
                            SidebarNodeView(
                                node: node,
                                depth: 0,
                                expandedFolders: $expandedFolders,
                                selectedPaths: $selectedPaths,
                                onSelect: handleSelect,
                                onPromptFolder: { isNew, url, name in
                                    folderPrompt = FolderPromptState(isNewFolder: isNew, targetURL: url, initialName: name)
                                    folderInputText = name
                                    showingFolderAlert = true
                                }
                            )
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    // Finder-style Frosted Bottom Action Bar matching AppleMusicUI template
                    HStack(spacing: 12) {
                        Button {
                            store.createNewMacro()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help("New Macro (⌘N)")

                        Button {
                            folderPrompt = FolderPromptState(isNewFolder: true, targetURL: nil, initialName: "")
                            folderInputText = ""
                            showingFolderAlert = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12))
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help("New Folder (⇧⌘N)")

                        if !selectedPaths.isEmpty || store.selectedMacro != nil {
                            Button {
                                if !selectedPaths.isEmpty {
                                    store.deleteItems(paths: Array(selectedPaths))
                                    selectedPaths.removeAll()
                                } else if let m = store.selectedMacro {
                                    store.deleteMacro(m)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.85))
                                    .frame(width: 28, height: 28)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.red.opacity(0.2), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Delete Selected Items")
                        }
                        
                        Button {
                            if let appDelegate = NSApp.delegate as? AppDelegate {
                                appDelegate.relaunchApp()
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Relaunch App")

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isRootDropTarget) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                            guard let str = string as? String else { return }
                            let paths = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                            DispatchQueue.main.async {
                                store.moveItems(paths: paths, toFolder: store.watchDirectoryURL)
                            }
                        }
                    }
                    return true
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            GeometryReader { detailGeo in
                if let macro = store.selectedMacro {
                    MacroInspectorView(macro: macro, detailWidth: detailGeo.size.width)
                        .id(macro.id)
                } else if let folderPath = store.selectedFolderPath,
                          let folderInfo = findFolderInfo(path: folderPath, in: store.treeNodes) {
                    FolderInspectorView(
                        folderURL: folderInfo.url,
                        initialConfig: folderInfo.config,
                        itemCount: folderInfo.count
                    )
                    .id(folderPath)
                } else {
                    ZStack(alignment: .top) {
                        VStack(spacing: 16) {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color(white: 0.18))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "bolt.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
                            }
                            Text("No Selection")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Choose a macro or folder from the sidebar.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Button {
                                store.createNewMacro()
                            } label: {
                                Text("Create New Macro")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                        
                        // Top Header Bar (unified transparent bar matching AppleMusicUI)
                        HStack(spacing: 12) {
                            Spacer()

                            Button {
                                alwaysOnTop.toggle()
                                if let appDelegate = NSApp.delegate as? AppDelegate {
                                    appDelegate.updateAlwaysOnTop()
                                }
                            } label: {
                                Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(alwaysOnTop ? .accentColor : .secondary)
                                    .frame(width: 30, height: 30)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Always on Top")
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                        .background(WindowDragView())
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationSplitViewStyle(.balanced)
        .background(
            ZStack {
                VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
                Color.black.opacity(0.12)
            }
            .ignoresSafeArea()
        )
        .onChange(of: columnVisibility) { _, newValue in
            store.isSidebarVisible = (newValue != .detailOnly)
        }
        .onChange(of: store.isSidebarVisible) { _, newValue in
            columnVisibility = newValue ? .all : .detailOnly
        }
        .onChange(of: selectedPaths) { _, newPaths in
            if let path = newPaths.first {
                if path.hasSuffix(".shortking") {
                    store.selectedFilePath = path
                    store.selectedFolderPath = nil
                } else {
                    store.selectedFolderPath = path
                    store.selectedFilePath = nil
                }
            } else {
                store.selectedFilePath = nil
                store.selectedFolderPath = nil
            }
        }
        .onChange(of: store.selectedFilePath) { _, newPath in
            if let path = newPath {
                if !selectedPaths.contains(path) {
                    selectedPaths = [path]
                }
            }
        }
        .onChange(of: store.selectedFolderPath) { _, newPath in
            if let path = newPath {
                if !selectedPaths.contains(path) {
                    selectedPaths = [path]
                }
            }
        }
        .alert(isPresented: $showingFolderAlert) {
            let isNew = folderPrompt?.isNewFolder ?? true
            return Alert(
                title: Text(isNew ? "New Folder" : "Rename Folder"),
                message: Text("Enter folder name:"),
                primaryButton: .default(Text(isNew ? "Create" : "Rename")) {
                    guard !folderInputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    if isNew {
                        store.createFolder(name: folderInputText, parentURL: folderPrompt?.targetURL)
                    } else if let url = folderPrompt?.targetURL {
                        store.renameFolder(at: url, newName: folderInputText)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            for node in store.treeNodes {
                if case .folder(_, let url, _, _) = node {
                    _ = expandedFolders.insert(url.path)
                }
            }
            
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "f" {
                    isSearchFocused = true
                    return nil // consume
                }
                if event.keyCode == 123 || event.keyCode == 124 {
                    let targetPath = store.selectedFolderPath ?? selectedPaths.first
                    if let path = targetPath, !path.hasSuffix(".shortking") {
                        if event.keyCode == 123 { // Collapse
                            if expandedFolders.contains(path) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    _ = expandedFolders.remove(path)
                                }
                                return nil // consume
                            }
                        } else if event.keyCode == 124 { // Expand
                            if !expandedFolders.contains(path) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    _ = expandedFolders.insert(path)
                                }
                                return nil // consume
                            }
                        }
                    }
                } else if event.keyCode == 125 || event.keyCode == 126 { // Down or Up
                    if let responder = NSApp.keyWindow?.firstResponder {
                        if let tv = responder as? NSTextView, tv.isEditable { return event }
                        if let tf = responder as? NSTextField, tf.isEditable { return event }
                    }
                    if store.focusedPane == .right {
                        if event.keyCode == 125 {
                            store.moveActionSelectionDown()
                        } else {
                            store.moveActionSelectionUp()
                        }
                        return nil // consume
                    } else {
                        if event.keyCode == 125 { // Down
                            store.moveSelectionDown(expandedFolders: expandedFolders)
                            if let current = store.selectedFilePath ?? store.selectedFolderPath {
                                selectedPaths = [current]
                                lastClickedPath = current
                            }
                            return nil // consume
                        } else { // Up
                            store.moveSelectionUp(expandedFolders: expandedFolders)
                            if let current = store.selectedFilePath ?? store.selectedFolderPath {
                                selectedPaths = [current]
                                lastClickedPath = current
                            }
                            return nil // consume
                        }
                    }
                } else if event.keyCode == 51 || event.keyCode == 117 { // Delete or Backspace
                    if let responder = NSApp.keyWindow?.firstResponder {
                        if let tv = responder as? NSTextView, tv.isEditable { return event }
                        if let tf = responder as? NSTextField, tf.isEditable { return event }
                    }
                    if store.focusedPane == .left {
                        let pathsToDelete: [String] = {
                            if !selectedPaths.isEmpty {
                                return Array(selectedPaths)
                            } else if let filePath = store.selectedFilePath {
                                return [filePath]
                            } else if let folderPath = store.selectedFolderPath {
                                return [folderPath]
                            }
                            return []
                        }()
                        
                        if !pathsToDelete.isEmpty {
                            store.deleteItems(paths: pathsToDelete)
                            selectedPaths.removeAll()
                            store.selectedFilePath = nil
                            store.selectedFolderPath = nil
                            return nil // consume
                        }
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

class EditorWindow: NSWindow {
    override var undoManager: UndoManager? {
        return MacroStore.shared.undoManager
    }
    
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
    }
}

// ==========================================
// MARK: - App Delegate with Complete Standard Menu Bar & Settings Window
// ==========================================
