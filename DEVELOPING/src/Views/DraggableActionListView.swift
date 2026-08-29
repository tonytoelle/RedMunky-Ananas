import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

struct ActionCardView: View {
    let index: Int
    @Binding var item: MacroActionItem
    var onDelete: () -> Void
    var onPreSave: () -> Void
    var onSave: () -> Void
    let detailWidth: CGFloat
    var store = MacroStore.shared
    
    var isDragging: Bool = false
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: ((DragGesture.Value) -> Void)? = nil

    @FocusState private var isGroupFocused: Bool
    @State private var isCollapsed = false
    @State private var isEditingGroupName = false
    @State private var localGroupName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeaderRow
            nestedGroupPreview
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(white: isDragging ? 0.22 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(store.selectedActionIDs.contains(item.id) || isDragging ? Color.accentColor : Color.white.opacity(0.06),
                        lineWidth: store.selectedActionIDs.contains(item.id) || isDragging ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { val in onDragChanged?(val) }
                .onEnded { val in onDragEnded?(val) }
        )
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags
            store.focusedPane = .right
            if let selected = MacroStore.shared.selectedMacro {
                store.handleActionSelect(item.id, items: selected.actionItems, modifiers: modifiers)
            }
        }
        .contextMenu {
            contextMenuItems
        }
        .onAppear {
            if case .group(let name, _) = item.action {
                localGroupName = name
            }
        }
        .onChange(of: item) { _, newItem in
            if case .group(let name, _) = newItem.action {
                localGroupName = name
            }
        }
    }

    @ViewBuilder
    private var cardHeaderRow: some View {
        HStack(spacing: detailWidth < 520 ? 8 : 12) {
            dragHandleView
            stepBadgeIcon

            HStack(spacing: 8) {
                if detailWidth >= 400 {
                    HStack(spacing: 4) {
                        cardTitleView
                        shortcutKeycapsView
                    }
                }
                
                Spacer()
                
                parameterEditorView
            }
            
            groupToggleButton
        }
    }

    @ViewBuilder
    private var shortcutKeycapsView: some View {
        if case .pressShortcut(let t) = item.action {
            HStack(spacing: 4) {
                if t.requireCmd { KeyCap(text: "⌘") }
                if t.requireShift { KeyCap(text: "⇧") }
                if t.requireOption { KeyCap(text: "⌥") }
                if t.requireControl { KeyCap(text: "⌃") }
                KeyCap(text: KeyMap.name(for: t.keyCode))
            }
        }
    }

    @ViewBuilder
    private var groupToggleButton: some View {
        if case .group = item.action {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCollapsed.toggle()
                }
            }) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var nestedGroupPreview: some View {
        if case .group(let name, let subActions) = item.action, !isCollapsed {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(subActions.enumerated()), id: \.element.id) { subIndex, subItem in
                    let subItemBinding = Binding<MacroActionItem>(
                        get: {
                            if subIndex < subActions.count {
                                return subActions[subIndex]
                            } else {
                                return subItem
                            }
                        },
                        set: { newValue in
                            onPreSave()
                            var newSubActions = subActions
                            if subIndex < newSubActions.count {
                                newSubActions[subIndex] = newValue
                                item.action = .group(name: name, actions: newSubActions)
                                onSave()
                            }
                        }
                    )
                    
                    ActionCardView(
                        index: subIndex,
                        item: subItemBinding,
                        onDelete: {
                            onPreSave()
                            var newSubActions = subActions
                            newSubActions.remove(at: subIndex)
                            item.action = .group(name: name, actions: newSubActions)
                            onSave()
                        },
                        onPreSave: onPreSave,
                        onSave: onSave,
                        detailWidth: detailWidth
                    )
                    .onDrag {
                        return NSItemProvider(object: subItem.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: GroupActionDropDelegate(
                        item: subItem,
                        index: subIndex,
                        groupItem: $item,
                        onSave: onSave,
                        onPreSave: onPreSave
                    ))
                }
            }
            .padding(.top, 4)
            .padding(.leading, 0)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
            if !store.selectedActionIDs.isEmpty {
                Button("Group Selected Actions") {
                    if let selected = MacroStore.shared.selectedMacro {
                        store.registerUndoState(for: selected)
                        let itemsToGroup = selected.actionItems.filter { store.selectedActionIDs.contains($0.id) }
                        guard !itemsToGroup.isEmpty else { return }
                        
                        if let firstIdx = selected.actionItems.firstIndex(where: { store.selectedActionIDs.contains($0.id) }) {
                            selected.actionItems.removeAll { store.selectedActionIDs.contains($0.id) }
                            let groupItem = MacroActionItem(action: .group(name: "New Group", actions: itemsToGroup))
                            selected.actionItems.insert(groupItem, at: firstIdx)
                            store.selectedActionIDs = [groupItem.id]
                            store.saveMacro(selected)
                        }
                    }
                }
            }
            
            if case .group(_, let subActions) = item.action {
                Button("Ungroup Actions") {
                    if let selected = MacroStore.shared.selectedMacro,
                       let idx = selected.actionItems.firstIndex(where: { $0.id == item.id }) {
                        store.registerUndoState(for: selected)
                        selected.actionItems.remove(at: idx)
                        selected.actionItems.insert(contentsOf: subActions, at: idx)
                        store.selectedActionIDs.removeAll()
                        store.saveMacro(selected)
                    }
                }
            }

            Divider()

            Button {
                if let selected = MacroStore.shared.selectedMacro {
                    MacroStore.shared.registerUndoState(for: selected)
                }
                MacroStore.shared.moveSelectedActionsUp()
            } label: {
                Label("Move Up (⌥↑)", systemImage: "arrow.up")
            }

            Button {
                if let selected = MacroStore.shared.selectedMacro {
                    MacroStore.shared.registerUndoState(for: selected)
                }
                MacroStore.shared.moveSelectedActionsDown()
            } label: {
                Label("Move Down (⌥↓)", systemImage: "arrow.down")
            }
            
            Divider()
            
            Button("Duplicate") {
                if let selected = MacroStore.shared.selectedMacro,
                   let idx = selected.actionItems.firstIndex(where: { $0.id == item.id }) {
                    store.registerUndoState(for: selected)
                    let clone = MacroActionItem(action: item.action, repeatCount: item.repeatCount)
                    selected.actionItems.insert(clone, at: idx + 1)
                    store.saveMacro(selected)
                }
            }
            
            Button("Copy Action") {
                if let selected = MacroStore.shared.selectedMacro {
                    let selectedItems = selected.actionItems.filter { store.selectedActionIDs.contains($0.id) }
                    if !selectedItems.isEmpty {
                        store.copiedActions = selectedItems
                    } else {
                        store.copiedActions = [item]
                    }
                }
            }
            
            Button("Paste Action") {
                if let selected = MacroStore.shared.selectedMacro,
                   !store.copiedActions.isEmpty {
                    store.registerUndoState(for: selected)
                    let clonedPasted = store.copiedActions.map { MacroActionItem(action: $0.action, repeatCount: $0.repeatCount) }
                    if let idx = selected.actionItems.firstIndex(where: { $0.id == item.id }) {
                        selected.actionItems.insert(contentsOf: clonedPasted, at: idx + 1)
                    } else {
                        selected.actionItems.append(contentsOf: clonedPasted)
                    }
                    store.saveMacro(selected)
                }
            }
            .disabled(store.copiedActions.isEmpty)
            
            Button("Delete") {
                onDelete()
            }
            
            Divider()
            
            Menu("Repeat Action") {
                ForEach([1, 2, 3, 4, 5, 10, 20, 50], id: \.self) { count in
                    Button("\(count)x") {
                        if let selected = MacroStore.shared.selectedMacro,
                           let idx = selected.actionItems.firstIndex(where: { $0.id == item.id }) {
                            store.registerUndoState(for: selected)
                            selected.actionItems[idx].repeatCount = count
                            store.saveMacro(selected)
                        }
                    }
                }
                
                Button("Custom...") {
                    let alert = NSAlert()
                    alert.messageText = "Repeat Action"
                    alert.informativeText = "Enter custom repeat count:"
                    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
                    input.stringValue = "\(item.repeatCount)"
                    alert.accessoryView = input
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let val = Int(input.stringValue), val > 0,
                           let selected = MacroStore.shared.selectedMacro,
                           let idx = selected.actionItems.firstIndex(where: { $0.id == item.id }) {
                            store.registerUndoState(for: selected)
                            selected.actionItems[idx].repeatCount = val
                            store.saveMacro(selected)
                        }
                    }
                }
            }
        }

    @ViewBuilder
    private var stepBadgeIcon: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(getActionColor(for: item.action))
                .frame(width: 32, height: 32)
            
            Image(systemName: getActionIcon(for: item.action))
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .semibold))
                .offset(x: item.repeatCount > 1 ? -2 : 0, y: item.repeatCount > 1 ? 2 : 0)
            
            Text("\(index + 1)")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 2)
                .padding(.trailing, 4)
            
            if item.repeatCount > 1 {
                Text("\(item.repeatCount)x")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.bottom, 2)
                    .padding(.leading, 4)
            }
        }
        .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private var dragHandleView: some View {
        if detailWidth >= 340 {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(isDragging ? Color.accentColor : Color.secondary.opacity(0.6))
                .font(.system(size: 13, weight: isDragging ? .bold : .regular))
                .frame(width: 20, height: 26)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { val in onDragChanged?(val) }
                        .onEnded { val in onDragEnded?(val) }
                )
        }
    }

    @ViewBuilder
    private var parameterEditorView: some View {
        let isItemEditing = store.selectedActionIDs.contains(item.id)
        switch item.action {
        case .click:
            InlineClickEditView(action: $item.action, onPreSave: onPreSave, onSave: onSave, detailWidth: detailWidth)
        case .drag(let start, let end):
            ActionCardEditButton {
                CaptureOverlayWindow.shared = CaptureOverlayWindow(
                    mode: .drag(initialStart: start == .zero ? nil : start, initialEnd: end == .zero ? nil : end),
                    onDragCaptured: { newStart, newEnd in
                        onPreSave()
                        item.action = .drag(start: newStart, end: newEnd)
                        onSave()
                    },
                    onDragRealTime: { tempStart, tempEnd in
                        item.action = .drag(start: tempStart, end: tempEnd)
                    }
                )
            }
        case .path(let points):
            HStack(spacing: 8) {
                Text("\(points.count) pts")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                
                ActionCardEditButton {
                    CaptureOverlayWindow.shared = CaptureOverlayWindow(
                        initialPoints: points,
                        defaultType: .click,
                        onSequenceCaptured: { newPts in
                            guard !newPts.isEmpty else { return }
                            onPreSave()
                            item.action = .path(points: newPts)
                            onSave()
                        },
                        onSequenceRealTime: { tempPts in
                            item.action = .path(points: tempPts)
                        }
                    )
                }
            }
        case .moveCursor(let point):
            ActionCardEditButton {
                CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .click(button: .left, initialPoint: point == .zero ? nil : point)) { newPoint in
                    onPreSave()
                    item.action = .moveCursor(point: newPoint)
                    onSave()
                }
            }
        case .windowTransform(let p1, _, let p3, _):
            ActionCardEditButton(action: {
                let initialPoints: [SequencePoint] = (p1 == .zero && p3 == .zero) ? [] : [
                    SequencePoint(point: p1, type: .click),
                    SequencePoint(point: p3, type: .click)
                ]
                CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .windowTransform(initialPoints: initialPoints)) { np1, np2, np3, np4 in
                    onPreSave()
                    item.action = .windowTransform(p1: np1, p2: np2, p3: np3, p4: np4)
                    onSave()
                }
            }, title: "Edit Area")
        case .typeText, .pasteText:
            InlineTextEditView(action: $item.action, onPreSave: onPreSave, onSave: onSave, detailWidth: detailWidth)
        case .openFile:
            InlineOpenFileEditView(action: $item.action, onPreSave: onPreSave, onSave: onSave, detailWidth: detailWidth)
        case .customAction:
            InlineCustomActionEditView(action: $item.action, onPreSave: onPreSave, onSave: onSave, detailWidth: detailWidth)
        case .delay:
            InlineDelayEditView(action: $item.action, onPreSave: onPreSave, onSave: onSave, detailWidth: detailWidth)
        case .pressKey, .pressShortcut:
            InlineKeyRecorder(action: $item.action, onPreSave: onPreSave, onSave: onSave, detailWidth: detailWidth)
        case .originAction:
            InlineOriginPicker(action: $item.action, onPreSave: onPreSave, onSave: onSave, detailWidth: detailWidth)
        case .doAgain:
            if let selected = MacroStore.shared.selectedMacro {
                InlineDoAgainPicker(action: $item.action, actionItems: selected.actionItems, currentIndex: index, onPreSave: onPreSave, onSave: onSave, detailWidth: detailWidth)
            } else {
                Text(item.action.parameterString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isItemEditing ? Color(white: 0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isItemEditing ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
                    )
            }
        case .group(_, let subActions):
            Text("\(subActions.count) actions")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isItemEditing ? Color(white: 0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isItemEditing ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
                )
        default:
            Text(item.action.parameterString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isItemEditing ? Color(white: 0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isItemEditing ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var cardTitleView: some View {
        if case .group(let name, let subActions) = item.action {
            if isEditingGroupName {
                TextField("Group Name", text: $localGroupName)
                    .textFieldStyle(.plain)
                    .font(.system(size: detailWidth < 520 ? 11 : 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .frame(width: 140)
                    .focused($isGroupFocused)
                    .onSubmit {
                        commitGroupName(subActions: subActions)
                        isGroupFocused = false
                        isEditingGroupName = false
                    }
                    .onChange(of: isGroupFocused) { _, focused in
                        if !focused {
                            commitGroupName(subActions: subActions)
                            isEditingGroupName = false
                        }
                    }
                    .onAppear {
                        isGroupFocused = true
                    }
            } else {
                Text(name.isEmpty ? "Group Action" : name)
                    .font(.system(size: detailWidth < 520 ? 11 : 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        isEditingGroupName = true
                    }
            }
        } else {
            Text(item.action.title)
                .font(.system(size: detailWidth < 520 ? 11 : 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func commitGroupName(subActions: [MacroActionItem]) {
        onPreSave()
        item.action = .group(name: localGroupName, actions: subActions)
        onSave()
    }
    
    private func getActionColor(for action: MacroAction) -> Color {
        if case .doAgain(let target) = action {
            let actionItems = store.selectedMacro?.actionItems ?? []
            switch target {
            case .origin:
                return Color(red: 0.28, green: 0.52, blue: 0.92)
            case .originWindow:
                return Color(red: 0.1, green: 0.58, blue: 0.8)
            case .step(let idx):
                let targetIdx = idx - 1
                if targetIdx >= 0 && targetIdx < actionItems.count {
                    return getActionColor(for: actionItems[targetIdx].action)
                }
            case .action(let tid):
                if let targetItem = actionItems.first(where: { $0.id == tid }) {
                    return getActionColor(for: targetItem.action)
                }
            }
        }
        return action.color
    }

    private func getActionIcon(for action: MacroAction) -> String {
        if case .doAgain(let target) = action {
            let actionItems = store.selectedMacro?.actionItems ?? []
            switch target {
            case .origin:
                return "cursorarrow.motionlines"
            case .originWindow:
                return "macwindow"
            case .step(let idx):
                let targetIdx = idx - 1
                if targetIdx >= 0 && targetIdx < actionItems.count {
                    return getActionIcon(for: actionItems[targetIdx].action)
                }
            case .action(let tid):
                if let targetItem = actionItems.first(where: { $0.id == tid }) {
                    return getActionIcon(for: targetItem.action)
                }
            }
        }
        return action.iconName
    }
}

struct CardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

// ==========================================
// MARK: - Draggable Action List (Fluid Apple Physics)
// ==========================================
struct DraggableActionList: View {
    @Binding var actionItems: [MacroActionItem]
    var onSave: () -> Void
    var onInsertTemplate: (String, Int) -> Void
    let detailWidth: CGFloat

    // Gesture-driven Fluid Physics State
    @State private var draggingAnchorID: UUID? = nil
    @State private var activeBatchIDs: Set<UUID> = []
    @State private var dragOffsetY: CGFloat = 0
    @State private var initialAnchorIndex: Int? = nil
    @State private var currentTargetIndex: Int? = nil
    @State private var cardHeights: [UUID: CGFloat] = [:]

    // Template Drop State
    @State private var draggingTemplate: String? = nil
    @State private var placeholderIndex: Int? = nil

    private let defaultCardHeight: CGFloat = 58.0
    private let cardSpacing: CGFloat = 8.0

    private func offsetForCard(at index: Int, id: UUID) -> CGFloat {
        guard let _ = draggingAnchorID,
              let fromIdx = initialAnchorIndex,
              let targetIdx = currentTargetIndex else { return 0 }
        
        if activeBatchIDs.contains(id) {
            return dragOffsetY
        }
        
        let batchTotalHeight = activeBatchIDs.reduce(0.0) { sum, batchID in
            sum + (cardHeights[batchID] ?? defaultCardHeight) + cardSpacing
        }
        
        if fromIdx < targetIdx {
            // Dragged downwards: intermediate non-selected items shift UP
            if index > fromIdx && index <= targetIdx {
                return -batchTotalHeight
            }
        } else if fromIdx > targetIdx {
            // Dragged upwards: intermediate non-selected items shift DOWN
            if index >= targetIdx && index < fromIdx {
                return batchTotalHeight
            }
        }
        return 0
    }

    var body: some View {
        VStack(spacing: cardSpacing) {
            if actionItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    Text("Add action from below")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [4, 4]))
                )
                .padding(.vertical, 4)
            }
            
            ForEach(Array(actionItems.enumerated()), id: \.element.id) { index, actionItem in
                let itemID = actionItem.id
                let isDraggingThis = activeBatchIDs.contains(itemID)
                let itemBinding = Binding<MacroActionItem>(
                    get: {
                        if index < actionItems.count && actionItems[index].id == itemID {
                            return actionItems[index]
                        }
                        return actionItems.first(where: { $0.id == itemID }) ?? actionItem
                    },
                    set: { newValue in
                        if index < actionItems.count && actionItems[index].id == itemID {
                            actionItems[index] = newValue
                        } else if let idx = actionItems.firstIndex(where: { $0.id == itemID }) {
                            actionItems[idx] = newValue
                        }
                    }
                )
                
                Group {
                    if index == placeholderIndex, let templateName = draggingTemplate {
                        PlaceholderSlotView(title: templateName)
                    }
                    
                    ActionCardView(
                        index: index,
                        item: itemBinding,
                        onDelete: {
                            if let selected = MacroStore.shared.selectedMacro {
                                MacroStore.shared.registerUndoState(for: selected)
                            }
                            withAnimation(.easeInOut(duration: 0.12)) {
                                actionItems.removeAll { $0.id == itemID }
                            }
                            if MacroStore.shared.selectedActionIDs.contains(itemID) {
                                MacroStore.shared.selectedActionIDs.remove(itemID)
                            }
                            onSave()
                        },
                        onPreSave: {
                            if let selected = MacroStore.shared.selectedMacro {
                                MacroStore.shared.registerUndoState(for: selected)
                            }
                        },
                        onSave: onSave,
                        detailWidth: detailWidth,
                        isDragging: isDraggingThis,
                        onDragChanged: { gestureValue in
                            if draggingAnchorID == nil {
                                let selected = MacroStore.shared.selectedActionIDs
                                if selected.contains(itemID) && selected.count > 1 {
                                    activeBatchIDs = selected
                                } else {
                                    activeBatchIDs = [itemID]
                                    MacroStore.shared.selectedActionIDs = [itemID]
                                    MacroStore.shared.lastSelectedActionID = itemID
                                }
                                draggingAnchorID = itemID
                                initialAnchorIndex = index
                                currentTargetIndex = index
                                if let selectedMacro = MacroStore.shared.selectedMacro {
                                    MacroStore.shared.registerUndoState(for: selectedMacro)
                                }
                            }
                            
                            dragOffsetY = gestureValue.translation.height
                            
                            let singleStep = (cardHeights[itemID] ?? defaultCardHeight) + cardSpacing
                            let steps = Int(round(dragOffsetY / singleStep))
                            let newTarget = min(max(0, (initialAnchorIndex ?? index) + steps), actionItems.count - 1)
                            
                            if newTarget != currentTargetIndex {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                    currentTargetIndex = newTarget
                                }
                            }
                        },
                        onDragEnded: { _ in
                            guard let fromIdx = initialAnchorIndex,
                                  let toIdx = currentTargetIndex,
                                  fromIdx != toIdx,
                                  !activeBatchIDs.isEmpty else {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                    draggingAnchorID = nil
                                    activeBatchIDs.removeAll()
                                    dragOffsetY = 0
                                    initialAnchorIndex = nil
                                    currentTargetIndex = nil
                                }
                                return
                            }
                            
                            let movingIDs = activeBatchIDs
                            let selectedIndices = actionItems.enumerated()
                                .filter { movingIDs.contains($1.id) }
                                .map { $0.offset }
                                
                            guard !selectedIndices.isEmpty, let minIdx = selectedIndices.first else {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                    draggingAnchorID = nil
                                    activeBatchIDs.removeAll()
                                    dragOffsetY = 0
                                    initialAnchorIndex = nil
                                    currentTargetIndex = nil
                                }
                                return
                            }
                            
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                let fromOffsets = IndexSet(selectedIndices)
                                let destination = toIdx > minIdx ? min(toIdx + 1, actionItems.count) : toIdx
                                actionItems.move(fromOffsets: fromOffsets, toOffset: destination)
                                draggingAnchorID = nil
                                activeBatchIDs.removeAll()
                                dragOffsetY = 0
                                initialAnchorIndex = nil
                                currentTargetIndex = nil
                            }
                            onSave()
                        }
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: CardHeightPreferenceKey.self, value: [itemID: geo.size.height])
                        }
                    )
                    .offset(y: offsetForCard(at: index, id: itemID))
                    .zIndex(isDraggingThis ? 100 : Double(index))
                    .shadow(
                        color: isDraggingThis ? Color.black.opacity(0.4) : Color.clear,
                        radius: isDraggingThis ? 14 : 0,
                        x: 0,
                        y: isDraggingThis ? 8 : 0
                    )
                    .scaleEffect(isDraggingThis ? 1.02 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.82), value: offsetForCard(at: index, id: itemID))
                    .onDrop(of: [.text], delegate: TemplateDropDelegate(
                        item: actionItem,
                        index: index,
                        items: $actionItems,
                        draggingTemplate: $draggingTemplate,
                        placeholderIndex: $placeholderIndex,
                        onInsertTemplate: onInsertTemplate
                    ))
                }
            }
            
            if placeholderIndex == actionItems.count, let templateName = draggingTemplate {
                PlaceholderSlotView(title: templateName)
            }
        }
        .onPreferenceChange(CardHeightPreferenceKey.self) { preferences in
            for (k, v) in preferences {
                cardHeights[k] = v
            }
        }
    }
}

struct PlaceholderSlotView: View {
    let title: String
    
    var body: some View {
        HStack {
            Image(systemName: "plus.circle")
                .foregroundColor(.accentColor)
                .font(.system(size: 14))
            
            Text("Insert \(title) Here")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.accentColor)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

struct TemplateDropDelegate: DropDelegate {
    let item: MacroActionItem
    let index: Int
    @Binding var items: [MacroActionItem]
    @Binding var draggingTemplate: String?
    @Binding var placeholderIndex: Int?
    var onInsertTemplate: (String, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { (str, error) in
                if let s = str as? String, s.hasPrefix("action_template:") {
                    let typeName = s.replacingOccurrences(of: "action_template:", with: "")
                    DispatchQueue.main.async {
                        let targetIndex = placeholderIndex ?? (items.firstIndex(where: { $0.id == item.id }) ?? index)
                        onInsertTemplate(typeName, targetIndex)
                        draggingTemplate = nil
                        placeholderIndex = nil
                    }
                }
            }
            return true
        }
        draggingTemplate = nil
        placeholderIndex = nil
        return false
    }

    func dropEntered(info: DropInfo) {
        if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { (str, error) in
                if let s = str as? String, s.hasPrefix("action_template:") {
                    let typeName = s.replacingOccurrences(of: "action_template:", with: "")
                    DispatchQueue.main.async {
                        let currIdx = items.firstIndex(where: { $0.id == item.id }) ?? index
                        withAnimation(.easeInOut(duration: 0.12)) {
                            draggingTemplate = typeName
                            placeholderIndex = currIdx
                        }
                    }
                }
            }
        }
    }
}

struct GroupActionDropDelegate: DropDelegate {
    let item: MacroActionItem
    let index: Int
    @Binding var groupItem: MacroActionItem
    var onSave: () -> Void
    var onPreSave: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onSave()
        return true
    }

    func dropEntered(info: DropInfo) {
        if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { (str, error) in
                if let s = str as? String, let dragID = UUID(uuidString: s) {
                    if case .group(let groupName, var subActions) = groupItem.action {
                        guard let targetIdx = subActions.firstIndex(where: { $0.id == item.id }) else { return }
                        guard let fromIdx = subActions.firstIndex(where: { $0.id == dragID }),
                              fromIdx != targetIdx else { return }
                        DispatchQueue.main.async {
                            onPreSave()
                            withAnimation(.easeInOut(duration: 0.12)) {
                                let movingItem = subActions.remove(at: fromIdx)
                                subActions.insert(movingItem, at: targetIdx)
                                groupItem.action = .group(name: groupName, actions: subActions)
                            }
                        }
                    }
                }
            }
        }
    }
}

