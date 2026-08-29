import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

struct ClickEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var xStr = ""
    @State private var yStr = ""
    @State private var buttonType: CGMouseButton = .left

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Button:").font(.system(size: 11)).foregroundColor(.secondary)
                Picker("", selection: $buttonType) {
                    Text("Left Click").tag(CGMouseButton.left)
                    Text("Right Click").tag(CGMouseButton.right)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                
                Spacer()
                
                Button("📍 Recapture") {
                    let curPt: CGPoint? = (Double(xStr) != nil && Double(yStr) != nil) ? CGPoint(x: Double(xStr)!, y: Double(yStr)!) : nil
                    CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .click(button: buttonType, initialPoint: curPt)) { newPoint in
                        let xv = Int(newPoint.x)
                        let yv = Int(newPoint.y)
                        xStr = String(xv)
                        yStr = String(yv)
                        save()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("X:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $xStr)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
                HStack(spacing: 4) {
                    Text("Y:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $yStr)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
        }
        .onAppear {
            if case .click(let point, let button) = action {
                let xv = Int(point.x)
                let yv = Int(point.y)
                buttonType = button
                xStr = String(xv)
                yStr = String(yv)
            }
        }
        .onChange(of: xStr) { _, _ in save() }
        .onChange(of: yStr) { _, _ in save() }
        .onChange(of: buttonType) { _, _ in save() }
    }

    private func save() {
        let x = Double(xStr) ?? 0.0
        let y = Double(yStr) ?? 0.0
        action = .click(point: CGPoint(x: x, y: y), button: buttonType)
        onSave()
    }
}

struct CurrentPositionEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var buttonType: CGMouseButton = .left

    var body: some View {
        HStack(spacing: 10) {
            Text("Button:").font(.system(size: 11)).foregroundColor(.secondary)
            Picker("", selection: $buttonType) {
                Text("Left Click").tag(CGMouseButton.left)
                Text("Right Click").tag(CGMouseButton.right)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .onAppear {
            if case .currentPosition(let btn) = action {
                buttonType = btn
            }
        }
        .onChange(of: buttonType) { _, newBtn in
            action = .currentPosition(button: newBtn)
            onSave()
        }
    }
}

struct DragEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var xStr = ""
    @State private var yStr = ""
    @State private var x2Str = ""
    @State private var y2Str = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Coordinates").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                Button("📍 Recapture") {
                    let startPt: CGPoint? = (Double(xStr) != nil && Double(yStr) != nil) ? CGPoint(x: Double(xStr)!, y: Double(yStr)!) : nil
                    let endPt: CGPoint? = (Double(x2Str) != nil && Double(y2Str) != nil) ? CGPoint(x: Double(x2Str)!, y: Double(y2Str)!) : nil
                    CaptureOverlayWindow.shared = CaptureOverlayWindow(mode: .drag(initialStart: startPt, initialEnd: endPt)) { ns, ne in
                        let xs = Int(ns.x)
                        let ys = Int(ns.y)
                        let xe = Int(ne.x)
                        let ye = Int(ne.y)
                        xStr = String(xs)
                        yStr = String(ys)
                        x2Str = String(xe)
                        y2Str = String(ye)
                        save()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Start X:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $xStr)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
                HStack(spacing: 4) {
                    Text("Y:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $yStr)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("End X:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $x2Str)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
                HStack(spacing: 4) {
                    Text("Y:").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("", text: $y2Str)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
        }
        .onAppear {
            if case .drag(let start, let end) = action {
                let sx = Int(start.x)
                let sy = Int(start.y)
                let ex = Int(end.x)
                let ey = Int(end.y)
                xStr = String(sx)
                yStr = String(sy)
                x2Str = String(ex)
                y2Str = String(ey)
            }
        }
        .onChange(of: xStr) { _, _ in save() }
        .onChange(of: yStr) { _, _ in save() }
        .onChange(of: x2Str) { _, _ in save() }
        .onChange(of: y2Str) { _, _ in save() }
    }

    private func save() {
        let x1 = Double(xStr) ?? 0
        let y1 = Double(yStr) ?? 0
        let x2 = Double(x2Str) ?? 0
        let y2 = Double(y2Str) ?? 0
        action = .drag(start: CGPoint(x: x1, y: y1), end: CGPoint(x: x2, y: y2))
        onSave()
    }
}

struct DelayEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var delayStr = ""

    var body: some View {
        HStack(spacing: 10) {
            Text("Duration (ms):").font(.system(size: 11)).foregroundColor(.secondary)
            TextField("", text: $delayStr)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
        .onAppear {
            if case .delay(let ms) = action {
                let mv = Int(ms)
                delayStr = String(mv)
            }
        }
        .onChange(of: delayStr) { _, _ in save() }
    }

    private func save() {
        let ms = UInt32(delayStr) ?? 0
        action = .delay(ms: ms)
        onSave()
    }
}

struct TextEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var textStr = ""
    @State private var textMode = 0 // 0: type, 1: paste

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $textMode) {
                Text("⌨️ Type").tag(0)
                Text("📋 Paste").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            
            HStack(spacing: 10) {
                Text("Text:").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("", text: $textStr)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onAppear {
            if case .typeText(let text) = action {
                textStr = text
                textMode = 0
            } else if case .pasteText(let text) = action {
                textStr = text
                textMode = 1
            }
        }
        .onChange(of: textStr) { _, _ in save() }
        .onChange(of: textMode) { _, _ in save() }
    }

    private func save() {
        action = (textMode == 0) ? .typeText(text: textStr) : .pasteText(text: textStr)
        onSave()
    }
}

struct KeyEditView: View {
    @Binding var action: MacroAction
    var onSave: () -> Void

    @State private var keyStr = ""

    var body: some View {
        HStack(spacing: 10) {
            Text("Key name:").font(.system(size: 11)).foregroundColor(.secondary)
            TextField("enter/space/a-z...", text: $keyStr)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
        }
        .onAppear {
            if case .pressKey(let keyCode) = action {
                keyStr = KeyMap.name(for: keyCode)
            }
        }
        .onChange(of: keyStr) { _, _ in save() }
    }

    private func save() {
        if let code = KeyMap.keyCode(for: keyStr) {
            action = .pressKey(keyCode: code)
            onSave()
        }
    }
}

// ==========================================
// MARK: - Inline Action Parameter Editors
// ==========================================
