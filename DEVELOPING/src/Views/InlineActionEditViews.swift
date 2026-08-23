import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

struct InlineTextEditView: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    let detailWidth: CGFloat
    
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField("Text", text: $textValue)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .focused($isFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isFocused ? Color(white: 0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isFocused ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
            )
            .frame(width: detailWidth < 400 ? 90 : (detailWidth < 520 ? 120 : 160))
            .multilineTextAlignment(.leading)
            .onSubmit {
                save()
                isFocused = false
            }
            .onAppear {
                if case .typeText(let text) = action {
                    textValue = text
                } else if case .pasteText(let text) = action {
                    textValue = text
                }
            }
            .onChange(of: action) { _, newValue in
                if case .typeText(let text) = newValue {
                    textValue = text
                } else if case .pasteText(let text) = newValue {
                    textValue = text
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    save()
                }
            }
    }
    
    private func save() {
        onPreSave()
        if case .typeText = action {
            action = .typeText(text: textValue)
        } else if case .pasteText = action {
            action = .pasteText(text: textValue)
        }
        onSave()
    }
}

struct InlineCustomActionEditView: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    let detailWidth: CGFloat
    
    @State private var scriptValue: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField("Shell command/script", text: $scriptValue)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .focused($isFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isFocused ? Color(white: 0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isFocused ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
            )
            .frame(width: detailWidth < 400 ? 120 : (detailWidth < 520 ? 180 : 260))
            .multilineTextAlignment(.leading)
            .onSubmit {
                save()
                isFocused = false
            }
            .onAppear {
                if case .customAction(let script) = action {
                    scriptValue = script
                }
            }
            .onChange(of: action) { _, newValue in
                if case .customAction(let script) = newValue {
                    scriptValue = script
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    save()
                }
            }
    }
    
    private func save() {
        onPreSave()
        action = .customAction(script: scriptValue)
        onSave()
    }
}

struct InlineOpenFileEditView: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    let detailWidth: CGFloat
    
    @State private var pathValue: String = ""
    
    var body: some View {
        HStack(spacing: 6) {
            Button(action: {
                selectFile()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                    Text(pathValue.isEmpty ? "Choose File..." : URL(fileURLWithPath: pathValue).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(pathValue.isEmpty ? "No file selected" : pathValue)
        }
        .onAppear {
            if case .openFile(let path) = action {
                pathValue = path
            }
        }
        .onChange(of: action) { _, newValue in
            if case .openFile(let path) = newValue {
                pathValue = path
            }
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Select File or Application to Open"
        
        // Force the modal to run on main thread to avoid threading issues
        if Thread.isMainThread {
            if panel.runModal() == .OK, let url = panel.url {
                onPreSave()
                pathValue = url.path
                action = .openFile(path: url.path)
                onSave()
            }
        } else {
            DispatchQueue.main.sync {
                if panel.runModal() == .OK, let url = panel.url {
                    onPreSave()
                    pathValue = url.path
                    action = .openFile(path: url.path)
                    onSave()
                }
            }
        }
    }
}

struct InlineDelayEditView: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    let detailWidth: CGFloat
    
    @State private var msValue: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            TextField("ms", text: $msValue)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .focused($isFocused)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isFocused ? Color(white: 0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isFocused ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
                )
                .frame(width: detailWidth < 400 ? 50 : 70)
                .multilineTextAlignment(.center)
                .onSubmit {
                    save()
                    isFocused = false
                }
                .onAppear {
                    if case .delay(let ms) = action {
                        msValue = String(ms)
                    }
                }
                .onChange(of: action) { _, newValue in
                    if case .delay(let ms) = newValue {
                        msValue = String(ms)
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        save()
                    }
                }
            if detailWidth >= 400 {
                Text("ms")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func save() {
        onPreSave()
        let ms = UInt32(msValue) ?? 0
        action = .delay(ms: ms)
        onSave()
    }
}

struct InlineKeyRecorder: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    let detailWidth: CGFloat
    
    @State private var isRecording = false
    @State private var monitor: Any?
    
    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            HStack(spacing: 8) {
                if isRecording {
                    Image(systemName: "record.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 13))
                    Text(detailWidth < 400 ? "Press key..." : "Press key/shortcut... (Esc to cancel)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                } else {
                    switch action {
                    case .pressShortcut(let trig):
                        ShortcutBadgeView(trigger: trig, isDimmedMini: false)
                    case .pressKey(let k):
                        ShortcutBadgeView(trigger: Trigger(keyCode: k, requireCmd: false, requireShift: false, requireOption: false, requireControl: false), isDimmedMini: false)
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isRecording ? Color.red.opacity(0.12) : Color(white: 0.22))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isRecording ? Color.red : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    func startRecording() {
        isRecording = true
        CarbonHotKeyManager.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let f = event.modifierFlags
            let kc = event.keyCode
            let isCmd = f.contains(.command), isShift = f.contains(.shift), isOpt = f.contains(.option), isCtrl = f.contains(.control)
            
            // Esc alone = cancel
            if kc == 53 && !isCmd && !isShift && !isOpt && !isCtrl {
                DispatchQueue.main.async { self.stopRecording() }
                return nil
            }
            
            let newAction: MacroAction
            if isCmd || isShift || isOpt || isCtrl {
                let trigger = Trigger(keyCode: kc, requireCmd: isCmd, requireShift: isShift, requireOption: isOpt, requireControl: isCtrl)
                newAction = .pressShortcut(trigger: trigger)
            } else {
                newAction = .pressKey(keyCode: kc)
            }
            
            DispatchQueue.main.async {
                self.onPreSave()
                self.action = newAction
                self.stopRecording()
                self.onSave()
            }
            return nil
        }
    }
    
    func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        MacroStore.shared.registerAllCarbonHotKeys()
    }
}

struct InlineDoAgainPicker: View {
    @Binding var action: MacroAction
    var actionItems: [MacroActionItem]
    var currentIndex: Int
    var onPreSave: () -> Void
    var onSave: () -> Void
    let detailWidth: CGFloat
    
    var body: some View {
        if case .doAgain(let currentTarget) = action {
            Menu {
                Button(action: {
                    onPreSave()
                    action = .doAgain(target: .origin)
                    onSave()
                }) {
                    HStack {
                        Text("Move Cursor to Origin")
                        if currentTarget == .origin {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Button(action: {
                    onPreSave()
                    action = .doAgain(target: .originWindow)
                    onSave()
                }) {
                    HStack {
                        Text("Origin Window Transformation")
                        if currentTarget == .originWindow {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(0..<actionItems.count, id: \.self) { idx in
                    let otherItem = actionItems[idx]
                    if idx != currentIndex, otherItem.action.hasCoordinates {
                        Button(action: {
                            onPreSave()
                            action = .doAgain(target: .action(otherItem.id))
                            onSave()
                        }) {
                            HStack {
                                Text("Action \(idx + 1): \(otherItem.action.title) (\(otherItem.action.parameterString))")
                                if case .action(let tid) = currentTarget, tid == otherItem.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(targetLabel(for: currentTarget))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(getTargetColor(for: currentTarget))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
    
    private func getTargetColor(for target: DoAgainTarget) -> Color {
        let items = actionItems
        switch target {
        case .origin:
            return Color(red: 0.28, green: 0.52, blue: 0.92)
        case .originWindow:
            return Color(red: 0.1, green: 0.58, blue: 0.8)
        case .step(let idx):
            let targetIdx = idx - 1
            if targetIdx >= 0 && targetIdx < items.count {
                return items[targetIdx].action.color
            }
        case .action(let tid):
            if let targetItem = items.first(where: { $0.id == tid }) {
                return targetItem.action.color
            }
        }
        return .cyan
    }
    
    private func targetLabel(for target: DoAgainTarget) -> String {
        switch target {
        case .origin:
            return "Move Cursor to Origin"
        case .originWindow:
            return "Origin Window Transformation"
        case .step(let idx):
            return "Action \(idx)"
        case .action(let tid):
            if let idx = actionItems.firstIndex(where: { $0.id == tid }) {
                return "Action \(idx + 1)"
            }
            return "Action"
        }
    }
}

struct InlineOriginPicker: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    let detailWidth: CGFloat
    
    var body: some View {
        if case .originAction(let currentType) = action {
            Menu {
                ForEach(OriginType.allCases, id: \.self) { type in
                    Button(action: {
                        onPreSave()
                        action = .originAction(type: type)
                        onSave()
                    }) {
                        HStack {
                            Text(type.title)
                            if currentType == type {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentType.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.pink)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

struct InlineClickEditView: View {
    @Binding var action: MacroAction
    var onPreSave: () -> Void
    var onSave: () -> Void
    let detailWidth: CGFloat
    
    @State private var xStr = ""
    @State private var yStr = ""
    @State private var buttonType: CGMouseButton = .left
    @State private var clickAtCurrent = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Button Type Selector
            Menu {
                Button("Left Click") { setButton(.left) }
                Button("Right Click") { setButton(.right) }
            } label: {
                Text(buttonType == .left ? "Left Click" : "Right Click")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.blue)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Toggle for Current Position
            Toggle(isOn: $clickAtCurrent) {
                Text("Current Pos")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .toggleStyle(.checkbox)
            
            if !clickAtCurrent {
                HStack(spacing: 4) {
                    TextField("X", text: $xStr)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 45)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .onSubmit { save() }
                    
                    TextField("Y", text: $yStr)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 45)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .onSubmit { save() }
                }
                
                Button("📍") {
                    let curPt = CGPoint(x: Double(xStr) ?? 0, y: Double(yStr) ?? 0)
                    CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .click(button: buttonType, initialPoint: curPt)) { newPoint in
                        xStr = String(Int(newPoint.x))
                        yStr = String(Int(newPoint.y))
                        save()
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("(current location)")
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadValues()
        }
        .onChange(of: action) { _, _ in
            loadValues()
        }
        .onChange(of: clickAtCurrent) { _, newValue in
            if newValue {
                xStr = "-9999"
                yStr = "-9999"
            } else {
                if xStr == "-9999" && yStr == "-9999" {
                    xStr = "0"
                    yStr = "0"
                }
            }
            save()
        }
    }
    
    private func loadValues() {
        if case .click(let point, let button) = action {
            buttonType = button
            if point.x == -9999 && point.y == -9999 {
                clickAtCurrent = true
                xStr = "-9999"
                yStr = "-9999"
            } else {
                clickAtCurrent = false
                xStr = String(Int(point.x))
                yStr = String(Int(point.y))
            }
        }
    }
    
    private func setButton(_ b: CGMouseButton) {
        buttonType = b
        save()
    }
    
    private func save() {
        onPreSave()
        let x = clickAtCurrent ? -9999.0 : (Double(xStr) ?? 0.0)
        let y = clickAtCurrent ? -9999.0 : (Double(yStr) ?? 0.0)
        action = .click(point: CGPoint(x: x, y: y), button: buttonType)
        onSave()
    }
}

