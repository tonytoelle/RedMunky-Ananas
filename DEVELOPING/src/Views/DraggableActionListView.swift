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
    @ObservedObject var store = MacroStore.shared

    @FocusState private var isGroupFocused: Bool
    @State private var isCollapsed = false
    @State private var isEditingGroupName = false
    @State private var localGroupName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: detailWidth < 520 ? 8 : 12) {
                // Drag handle (hide if extremely small)
                if detailWidth >= 340 {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.system(size: 13))
                        .frame(width: 14)
                }

                // Squircle Icon with step ID inside
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.action.color)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: item.action.iconName)
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

                // Title & Parameters
                HStack(spacing: 8) {
                    if detailWidth >= 400 {
                        HStack(spacing: 4) {
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
                            
                            if item.repeatCount > 1 {
                                Text("\(item.repeatCount)x")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Render appropriate parameter editor/display
                    let isItemEditing = store.selectedActionIDs.contains(item.id)
                    switch item.action {
                    case .click(let point, let button):
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
                            .onTapGesture {
                                CaptureOverlayWindow.shared = CaptureOverlayWindow(
                                    mode: .click(button: button, initialPoint: point),
                                    onClickCaptured: { newPoint in
                                        onPreSave()
                                        item.action = .click(point: newPoint, button: button)
                                        onSave()
                                    },
                                    onClickRealTime: { tempPoint in
                                        item.action = .click(point: tempPoint, button: button)
                                    }
                                )
                            }
                    case .drag(let start, let end):
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
                            .onTapGesture {
                                CaptureOverlayWindow.shared = CaptureOverlayWindow(
                                    mode: .drag(initialStart: start, initialEnd: end),
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
                            
                            Button {
                                CaptureOverlayWindow.shared = CaptureOverlayWindow(
                                    initialPoints: points,
                                    defaultType: .move,
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
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Edit")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(Color.purple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    case .moveCursor(let point):
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
                            .onTapGesture {
                                CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .click(button: .left, initialPoint: point)) { newPoint in
                                    onPreSave()
                                    item.action = .moveCursor(point: newPoint)
                                    onSave()
                                }
                            }
                    case .windowTransform(let p1, let p2, let p3, _):
                        Button(action: {
                            let initialPoints: [SequencePoint] = (p1 == .zero && p2 == .zero) ? [] : [
                                SequencePoint(point: p1, type: .click),
                                SequencePoint(point: p2, type: .click),
                                SequencePoint(point: p3, type: .click)
                            ]
                            CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .windowTransform(initialPoints: initialPoints)) { np1, np2, np3, np4 in
                                onPreSave()
                                item.action = .windowTransform(p1: np1, p2: np2, p3: np3, p4: np4)
                                onSave()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                Text("Edit Area")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
            
            // Nested Group Preview
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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(white: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(store.selectedActionIDs.contains(item.id) ? Color.accentColor : Color.white.opacity(0.06),
                        lineWidth: store.selectedActionIDs.contains(item.id) ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags
            store.focusedPane = .right
            if let selected = MacroStore.shared.selectedMacro {
                store.handleActionSelect(item.id, items: selected.actionItems, modifiers: modifiers)
            }
        }
        .contextMenu {
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

    private func commitGroupName(subActions: [MacroActionItem]) {
        onPreSave()
        item.action = .group(name: localGroupName, actions: subActions)
        onSave()
    }
}

// ==========================================
// MARK: - Draggable Action List (macOS drag-reorder)
// ==========================================
struct DraggableActionList: View {
    @Binding var actionItems: [MacroActionItem]
    var onSave: () -> Void
    var onInsertTemplate: (String, Int) -> Void
    let detailWidth: CGFloat

    @State private var draggingID: UUID?
    @State private var draggingTemplate: String? = nil
    @State private var placeholderIndex: Int? = nil
    @State private var isListTargeted = false

    var body: some View {
        LazyVStack(spacing: 8) {
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
            
            // Show implicit "Origin Recorded" indicator when a doAgain(.origin) action exists
            if actionItems.contains(where: { if case .doAgain(let t) = $0.action, case .origin = t { return true }; return false }) {
                HStack(spacing: 6) {
                    Image(systemName: "smallcircle.filled.circle")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.12, green: 0.58, blue: 0.65).opacity(0.7))
                    Text("Cursor origin auto-recorded")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Image(systemName: "eye.slash")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.35))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.12, green: 0.58, blue: 0.65).opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(red: 0.12, green: 0.58, blue: 0.65).opacity(0.12), lineWidth: 1, antialiased: true)
                        )
                )
            }
            
            ForEach(actionItems) { actionItem in
                let itemID = actionItem.id
                if let index = actionItems.firstIndex(where: { $0.id == itemID }) {
                    let itemBinding = Binding<MacroActionItem>(
                        get: {
                            if let idx = actionItems.firstIndex(where: { $0.id == itemID }) {
                                return actionItems[idx]
                            }
                            return actionItem
                        },
                        set: { newValue in
                            if let idx = actionItems.firstIndex(where: { $0.id == itemID }) {
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
                                withAnimation(.easeInOut(duration: 0.15)) {
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
                            detailWidth: detailWidth
                        )
                        .onDrag {
                            draggingID = itemID
                            if let selected = MacroStore.shared.selectedMacro {
                                MacroStore.shared.registerUndoState(for: selected)
                            }
                            return NSItemProvider(object: itemID.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: ActionDropDelegate(
                            item: actionItem,
                            index: index,
                            items: $actionItems,
                            draggingID: $draggingID,
                            draggingTemplate: $draggingTemplate,
                            placeholderIndex: $placeholderIndex,
                            onSave: onSave,
                            onInsertTemplate: onInsertTemplate
                        ))
                        .opacity(draggingID == itemID ? 0.3 : 1.0)
                    }
                }
            }
            
            if placeholderIndex == actionItems.count, let templateName = draggingTemplate {
                PlaceholderSlotView(title: templateName)
            }
        }
        .onDrop(of: [.text], isTargeted: $isListTargeted) { providers in
            if draggingID != nil {
                draggingID = nil
                DispatchQueue.main.async {
                    onSave()
                }
                return true
            }
            if let provider = providers.first {
                _ = provider.loadObject(ofClass: NSString.self) { (str, error) in
                    if let s = str as? String, s.hasPrefix("action_template:") {
                        let typeName = s.replacingOccurrences(of: "action_template:", with: "")
                        DispatchQueue.main.async {
                            let targetIndex = placeholderIndex ?? actionItems.count
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
        .onChange(of: isListTargeted) { _, targeted in
            if !targeted {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    draggingTemplate = nil
                    placeholderIndex = nil
                }
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
                        guard let fromIdx = subActions.firstIndex(where: { $0.id == dragID }),
                              fromIdx != index else { return }
                        DispatchQueue.main.async {
                            onPreSave()
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                let movingItem = subActions.remove(at: fromIdx)
                                subActions.insert(movingItem, at: index)
                                groupItem.action = .group(name: groupName, actions: subActions)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ActionDropDelegate: DropDelegate {
    let item: MacroActionItem
    let index: Int
    @Binding var items: [MacroActionItem]
    @Binding var draggingID: UUID?
    @Binding var draggingTemplate: String?
    @Binding var placeholderIndex: Int?
    var onSave: () -> Void
    var onInsertTemplate: (String, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if draggingID != nil {
            draggingID = nil
            DispatchQueue.main.async {
                onSave()
            }
            return true
        }
        
        if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { (str, error) in
                if let s = str as? String, s.hasPrefix("action_template:") {
                    let typeName = s.replacingOccurrences(of: "action_template:", with: "")
                    DispatchQueue.main.async {
                        let targetIndex = placeholderIndex ?? index
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
        if draggingID == nil {
            if let provider = info.itemProviders(for: [.text]).first {
                _ = provider.loadObject(ofClass: NSString.self) { (str, error) in
                    if let s = str as? String, s.hasPrefix("action_template:") {
                        let typeName = s.replacingOccurrences(of: "action_template:", with: "")
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                draggingTemplate = typeName
                                placeholderIndex = index
                            }
                        }
                    }
                }
            }
        } else if let dragID = draggingID {
            let selectedIDs = MacroStore.shared.selectedActionIDs
            if selectedIDs.contains(dragID) {
                let indices = items.enumerated().filter { selectedIDs.contains($1.id) }.map { $0.offset }
                guard !indices.isEmpty else { return }
                if !selectedIDs.contains(item.id) {
                    let fromOffsets = IndexSet(indices)
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        let to = index > (indices.first ?? 0) ? index + 1 : index
                        items.move(fromOffsets: fromOffsets, toOffset: to)
                    }
                }
            } else {
                guard let fromIdx = items.firstIndex(where: { $0.id == dragID }),
                      fromIdx != index else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    items.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: index > fromIdx ? index + 1 : index)
                }
            }
        }
    }
}

