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
                        .foregroundColor(.cyan)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.cyan)
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
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
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

