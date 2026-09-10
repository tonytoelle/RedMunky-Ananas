import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

struct ShortcutBadgeView: View {
    let trigger: Trigger
    var isDimmedMini: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: isDimmedMini ? 2 : 4) {
            if trigger.requireControl {
                keycap(symbol: "⌃", text: "Ctrl")
            }
            if trigger.requireOption {
                keycap(symbol: "⌥", text: "Opt")
            }
            if trigger.requireShift {
                keycap(symbol: "⇧", text: "Shift")
            }
            if trigger.requireCmd {
                keycap(symbol: "⌘", text: "Cmd")
            }
            
            if trigger.requireControl || trigger.requireOption || trigger.requireShift || trigger.requireCmd {
                Text("+")
                    .foregroundColor(isSelected ? .white : (isDimmedMini ? Color(white: 0.35) : .secondary))
                    .font(.system(size: isDimmedMini ? 8 : 11, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
            }
            
            Text(KeyMap.name(for: trigger.keyCode))
                .font(.system(size: isDimmedMini ? 8 : 10, weight: .bold))
                .foregroundColor(isSelected ? .white : (isDimmedMini ? Color(white: 0.6) : .accentColor))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, isDimmedMini ? 4 : 6)
                .padding(.vertical, isDimmedMini ? 1.5 : 2.5)
                .background(isDimmedMini ? Color(white: 0.16) : Color(white: 0.22))
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isDimmedMini ? Color(white: 0.22) : Color(white: 0.3), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    func keycap(symbol: String, text: String) -> some View {
        HStack(spacing: isDimmedMini ? 1 : 2) {
            Text(symbol)
                .foregroundColor(isSelected ? .white : (isDimmedMini ? Color(white: 0.45) : Color.gray))
                .font(.system(size: isDimmedMini ? 8 : 11, weight: .bold))
                .lineLimit(1)
                .fixedSize()
            Text(text)
                .foregroundColor(isSelected ? .white : (isDimmedMini ? Color(white: 0.55) : .white))
                .font(.system(size: isDimmedMini ? 7 : 10, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, isDimmedMini ? 4 : 6)
        .padding(.vertical, isDimmedMini ? 1.5 : 2.5)
        .background(isDimmedMini ? Color(white: 0.16) : Color(white: 0.22))
        .cornerRadius(3)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isDimmedMini ? Color(white: 0.22) : Color(white: 0.3), lineWidth: 0.5)
        )
    }
}

// ==========================================
// MARK: - HotKey Recorder
// ==========================================
struct HotKeyRecorder: View {
    @Binding var trigger: Trigger
    var onChanged: () -> Void

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

                    Text("Press shortcut... (Esc to cancel)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                } else {
                    ShortcutBadgeView(trigger: trigger)
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { event in
            let f = event.modifierFlags
            var kc = event.keyCode
            let isCmd = f.contains(.command), isShift = f.contains(.shift), isOpt = f.contains(.option), isCtrl = f.contains(.control)
            
            if event.type == .systemDefined && event.subtype.rawValue == 8 {
                let data1 = event.data1
                let mediaKeyCode = (data1 & 0xFFFF0000) >> 16
                let keyFlags = data1 & 0x0000FFFF
                let keyState = (keyFlags & 0xFF00) >> 8
                
                if keyState == 0x0A {
                    switch mediaKeyCode {
                    case 17, 18: // Rewind / Prev -> Physical F9
                        kc = 101
                    case 16:     // Play/Pause -> Physical F8
                        kc = 100
                    case 19:     // Fast Forward / Next -> Physical F10
                        kc = 109
                    case 1:      // Volume down -> F11
                        kc = 103
                    case 0:      // Volume up -> F12
                        kc = 111
                    default:
                        return event
                    }
                } else {
                    return event
                }
            } else if event.type != .keyDown {
                return event
            }
            
            // Esc alone = cancel
            if kc == 53 && !isCmd && !isShift && !isOpt && !isCtrl {
                DispatchQueue.main.async { self.stopRecording() }
                return nil
            }
            let newTrigger = Trigger(keyCode: kc, requireCmd: isCmd, requireShift: isShift, requireOption: isOpt, requireControl: isCtrl)
            DispatchQueue.main.async {
                if let selected = MacroStore.shared.selectedMacro {
                    MacroStore.shared.registerUndoState(for: selected)
                }
                self.trigger = newTrigger
                self.stopRecording()
                self.onChanged()
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

// ==========================================
// MARK: - Interactive Coordinate Capture Overlay Window (HUD Style)
// ==========================================

