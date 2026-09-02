import Foundation
import Cocoa
import SwiftUI
import Carbon
import ScreenCaptureKit

final class ScreenAnnotationManager {
    static let shared = ScreenAnnotationManager()

    private var activeWindow: NSWindow?
    private var isScreenshotHotKeySuspended = false

    private init() {}

    func start() {
        registerHotKey()
    }

    func registerHotKey() {
        guard !isScreenshotHotKeySuspended else { return }
        CarbonHotKeyManager.shared.registerScreenshotF9 { [weak self] in
            self?.beginSelection()
        }
    }

    func suspendHotKey() {
        isScreenshotHotKeySuspended = true
        CarbonHotKeyManager.shared.unregisterScreenshotF9()
    }

    func resumeHotKey() {
        isScreenshotHotKeySuspended = false
        registerHotKey()
    }

    func beginSelection() {
        guard activeWindow == nil else { return }
        activeWindow = ScreenAnnotationSelectionWindow { [weak self] rect in
            self?.activeWindow = nil
            self?.showAnnotation(for: rect)
        } onCancel: { [weak self] in
            self?.activeWindow = nil
        }
        activeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAnnotation(for rect: CGRect) {
        guard rect.width >= 2, rect.height >= 2 else { return }
        // Capture before displaying the annotation window so the preview stays visible while typing.
        Task { @MainActor [weak self] in
            guard let self = self, let screenshot = try? await self.capture(rect: rect) else {
                NSSound.beep()
                return
            }
            let annotation = ScreenAnnotationWindow(selectionRect: rect, screenshot: screenshot) { [weak self] text in
                self?.copyComposition(selectionRect: rect, screenshot: screenshot, text: text)
                self?.activeWindow = nil
            }
            self.activeWindow = annotation
            annotation.show()
        }
    }

    private func copyComposition(selectionRect: CGRect, screenshot: NSImage, text: String) {
            let width = selectionRect.width
            let font = NSFont.systemFont(ofSize: 16)
            let textInset: CGFloat = 14
            let textWidth = max(1, width - textInset * 2)
            let attributed = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.white
            ])
            let measured = attributed.boundingRect(with: NSSize(width: textWidth, height: 10000),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading])
            let panelHeight = max(52, ceil(measured.height) + textInset * 2)
            let outputSize = NSSize(width: width, height: selectionRect.height + panelHeight)
            let output = NSImage(size: outputSize)
            output.lockFocus()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: outputSize), xRadius: 24, yRadius: 24).addClip()
            screenshot.draw(in: NSRect(x: 0, y: panelHeight, width: width, height: selectionRect.height),
                            from: .zero, operation: .copy, fraction: 1)
            NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: width, height: panelHeight).fill()
            attributed.draw(with: NSRect(x: textInset, y: textInset, width: textWidth, height: panelHeight - textInset),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
            output.unlockFocus()

            guard let tiff = output.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                NSSound.beep()
                return
            }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        pasteboard.setString(text, forType: .string)
    }

    private func capture(rect: CGRect) async throws -> NSImage {
        let screen = NSScreen.screens.first { $0.frame.contains(rect.center) } ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSScreen.screens[0].frame
        let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            ?? CGMainDisplayID()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw NSError(domain: "ShortKingScreenshot", code: 1)
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: rect.minX - screenFrame.minX,
                                          y: screenFrame.maxY - rect.maxY,
                                          width: rect.width, height: rect.height)
        configuration.width = max(1, Int(rect.width * 2))
        configuration.height = max(1, Int(rect.height * 2))
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: image, size: NSSize(width: rect.width, height: rect.height))
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private final class ScreenAnnotationSelectionWindow: NSWindow {
    private let onSelected: (CGRect) -> Void
    private let onCancel: () -> Void

    init(onSelected: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onSelected = onSelected
        self.onCancel = onCancel
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.28)
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = ScreenAnnotationSelectionView(onSelected: onSelected, onCancel: onCancel)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class ScreenAnnotationSelectionView: NSView {
    private let onSelected: (CGRect) -> Void
    private let onCancel: () -> Void
    private var start: CGPoint?
    private var current: CGPoint = .zero

    init(onSelected: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onSelected = onSelected
        self.onCancel = onCancel
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start ?? .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = start else { return }
        let localRect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                               width: abs(current.x - start.x), height: abs(current.y - start.y))
        guard localRect.width >= 2, localRect.height >= 2 else { return }
        let screenRect = window?.convertToScreen(localRect) ?? localRect
        window?.orderOut(nil)
        onSelected(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.orderOut(nil)
            onCancel()
        } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let start = start else { return }
        let rect = NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
        NSColor.black.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: rect).fill()
    }
}

private final class ScreenAnnotationWindow: NSPanel {
    private let onComplete: (String) -> Void

    init(selectionRect: CGRect, screenshot: NSImage, onComplete: @escaping (String) -> Void) {
        self.onComplete = onComplete
        let width = selectionRect.width
        let panelHeight: CGFloat = 144
        super.init(contentRect: NSRect(x: selectionRect.minX, y: selectionRect.minY - panelHeight,
                                       width: width, height: selectionRect.height + panelHeight),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = ScreenAnnotationContentView(width: width, imageHeight: selectionRect.height,
                                                   screenshot: screenshot, panelHeight: panelHeight,
                                                   onComplete: onComplete)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class ScreenAnnotationContentView: NSView {
    private let onComplete: (String) -> Void
    private let imageView: NSImageView
    private let textView: NSTextView

    init(width: CGFloat, imageHeight: CGFloat, screenshot: NSImage, panelHeight: CGFloat,
         onComplete: @escaping (String) -> Void) {
        self.onComplete = onComplete
        imageView = NSImageView(image: screenshot)
        textView = NSTextView(frame: NSRect(x: 14, y: 14, width: max(20, width - 28), height: panelHeight - 28))
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: imageHeight + panelHeight))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        imageView.frame = NSRect(x: 0, y: panelHeight, width: width, height: imageHeight)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = self
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(textView)
        }
    }
}

extension ScreenAnnotationContentView: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) ||
            commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onComplete(textView.string)
            window?.orderOut(nil)
            return true
        }
        return false
    }
}
