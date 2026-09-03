import Foundation
import Cocoa
import SwiftUI
import Carbon
import ScreenCaptureKit

final class ScreenAnnotationManager {
    static let shared = ScreenAnnotationManager()

    private var selectionWindows: [ScreenAnnotationSelectionWindow] = []
    private var activeAnnotationWindow: ScreenAnnotationWindow?
    private var isScreenshotHotKeySuspended = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localKeyMonitor: Any?

    private init() {}

    func start() {
        registerHotKey()
        installLowLevelTap()
    }

    func registerHotKey() {
        guard !isScreenshotHotKeySuspended else { return }
        CarbonHotKeyManager.shared.registerScreenshotF9 { [weak self] in
            DispatchQueue.main.async {
                self?.beginSelection()
            }
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

    private func installLowLevelTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << 14) // keyDown + NX_SYSDEFINED
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = ScreenAnnotationManager.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                if type == .keyDown {
                    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                    if keycode == 101 { // F9
                        DispatchQueue.main.async {
                            ScreenAnnotationManager.shared.beginSelection()
                        }
                        return nil // Swallow F9 globally
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 101 { // F9
                self?.beginSelection()
                return nil
            }
            return event
        }
    }

    func beginSelection() {
        // If an annotation window is already active, close it first
        closeActiveAnnotation()

        guard selectionWindows.isEmpty else { return }
        closeSelectionWindows()

        // Create overlay window on EVERY active screen for multi-monitor support
        for screen in NSScreen.screens {
            let win = ScreenAnnotationSelectionWindow(screen: screen, onSelected: { [weak self] rect in
                self?.closeSelectionWindows()
                self?.showAnnotationInput(for: rect)
            }, onCancel: { [weak self] in
                self?.closeSelectionWindows()
            })
            selectionWindows.append(win)
            win.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeSelectionWindows() {
        for win in selectionWindows {
            win.orderOut(nil)
        }
        selectionWindows.removeAll()
    }

    private func closeActiveAnnotation() {
        activeAnnotationWindow?.orderOut(nil)
        activeAnnotationWindow = nil
    }

    private func showAnnotationInput(for rect: CGRect) {
        guard rect.width >= 4, rect.height >= 4 else { return }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let screenshot = try await self.capture(rect: rect)
                let annotationWin = ScreenAnnotationWindow(
                    selectionRect: rect,
                    screenshot: screenshot,
                    onCommit: { [weak self] userNote in
                        self?.closeActiveAnnotation()
                        self?.renderAndCopyCompositeImage(selectionRect: rect, screenshot: screenshot, noteText: userNote)
                    },
                    onCancel: { [weak self] in
                        self?.closeActiveAnnotation()
                    }
                )
                self.activeAnnotationWindow = annotationWin
                annotationWin.show()
            } catch {
                print("⚠️ Screenshot capture failed: \(error)")
                NSSound.beep()
            }
        }
    }

    private func renderAndCopyCompositeImage(selectionRect: CGRect, screenshot: NSImage, noteText: String) {
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If user didn't write any note, copy the screenshot directly as pure image!
        if trimmedNote.isEmpty {
            copyImageOnly(screenshot)
            playCaptureFeedbackSound()
            return
        }

        // User typed a note -> Combine screenshot + text banner into ONE SINGLE IMAGE
        let width = max(screenshot.size.width, 240)
        let font = NSFont.systemFont(ofSize: 15, weight: .regular)
        let textPaddingH: CGFloat = 16
        let textPaddingV: CGFloat = 14
        let textWidth = max(1, width - textPaddingH * 2)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.alignment = .left

        let attributed = NSAttributedString(string: trimmedNote, attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ])

        let measured = attributed.boundingRect(
            with: NSSize(width: textWidth, height: 10000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let notePanelHeight = max(48, ceil(measured.height) + textPaddingV * 2)
        let outputSize = NSSize(width: width, height: screenshot.size.height + notePanelHeight)

        let compositeImage = NSImage(size: outputSize)
        compositeImage.lockFocus()

        // Draw squircle card background for entire composite
        let totalBounds = NSRect(origin: .zero, size: outputSize)
        let cardPath = NSBezierPath(roundedRect: totalBounds, xRadius: 14, yRadius: 14)
        cardPath.addClip()

        // 1. Draw Screenshot on top portion
        screenshot.draw(
            in: NSRect(x: 0, y: notePanelHeight, width: width, height: screenshot.size.height),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )

        // 2. Draw Note Bar on bottom portion (dark modern macOS panel)
        NSColor(calibratedWhite: 0.14, alpha: 1.0).setFill()
        let noteRect = NSRect(x: 0, y: 0, width: width, height: notePanelHeight)
        noteRect.fill()

        // Separator line between image and note
        NSColor(calibratedWhite: 0.28, alpha: 0.8).setStroke()
        let sepPath = NSBezierPath()
        sepPath.move(to: NSPoint(x: 0, y: notePanelHeight))
        sepPath.line(to: NSPoint(x: width, y: notePanelHeight))
        sepPath.lineWidth = 1.0
        sepPath.stroke()

        // 3. Draw Note Text
        let drawTextRect = NSRect(
            x: textPaddingH,
            y: textPaddingV,
            width: textWidth,
            height: notePanelHeight - textPaddingV * 2
        )
        attributed.draw(with: drawTextRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        compositeImage.unlockFocus()

        copyImageOnly(compositeImage)
        playCaptureFeedbackSound()
    }

    private func copyImageOnly(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Write PURE IMAGE DATA ONLY (PNG & TIFF) to pasteboard.
        // NEVER call pasteboard.setString(..., forType: .string) so applications always paste the graphic!
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            pasteboard.writeObjects([image])
            return
        }

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        item.setData(tiff, forType: .tiff)
        pasteboard.writeObjects([item])
        print("📸 Screenshot copied as PURE IMAGE to clipboard (\(Int(image.size.width))x\(Int(image.size.height)) px)")
    }

    private func playCaptureFeedbackSound() {
        if let sound = NSSound(named: "Screen Capture") ?? NSSound(named: "Tink") {
            sound.play()
        }
    }

    private func capture(rect: CGRect) async throws -> NSImage {
        let screen = NSScreen.screens.first { $0.frame.contains(rect.center) } ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSScreen.screens[0].frame
        let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            ?? CGMainDisplayID()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw NSError(domain: "ShortKingScreenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let scale = screen?.backingScaleFactor ?? 2.0
        configuration.width = max(1, Int(rect.width * scale))
        configuration.height = max(1, Int(rect.height * scale))
        configuration.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: cgImage, size: NSSize(width: rect.width, height: rect.height))
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - Selection Overlay Window (Multi-Monitor)
private final class ScreenAnnotationSelectionWindow: NSWindow {
    private let onSelected: (CGRect) -> Void
    private let onCancel: () -> Void

    init(screen: NSScreen, onSelected: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onSelected = onSelected
        self.onCancel = onCancel
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = ScreenAnnotationSelectionView(screenFrame: screen.frame, onSelected: onSelected, onCancel: onCancel)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Selection View with Crosshair & Live Dimensions
private final class ScreenAnnotationSelectionView: NSView {
    private let screenFrame: CGRect
    private let onSelected: (CGRect) -> Void
    private let onCancel: () -> Void
    private var start: CGPoint?
    private var current: CGPoint = .zero

    init(screenFrame: CGRect, onSelected: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.screenFrame = screenFrame
        self.onSelected = onSelected
        self.onCancel = onCancel
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

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
        let localRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        guard localRect.width >= 4, localRect.height >= 4 else {
            onCancel()
            return
        }

        let screenRect = window?.convertToScreen(localRect) ?? localRect
        onSelected(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let start = start else { return }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // Clear selection cutout
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        NSColor.clear.setFill()
        NSBezierPath(rect: rect).fill()

        // Selection Border
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
        NSColor(red: 0.15, green: 0.65, blue: 1.0, alpha: 1.0).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()

        // Dimension Badge
        let w = Int(rect.width)
        let h = Int(rect.height)
        let dimText = "\(w) × \(h)"
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (dimText as NSString).size(withAttributes: attr)
        let badgeRect = NSRect(
            x: max(8, min(rect.minX, bounds.width - textSize.width - 20)),
            y: max(8, rect.minY - 24),
            width: textSize.width + 12,
            height: 18
        )

        NSColor(white: 0.15, alpha: 0.9).setFill()
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
        badgePath.fill()
        NSColor(white: 0.35, alpha: 0.6).setStroke()
        badgePath.lineWidth = 0.5
        badgePath.stroke()

        (dimText as NSString).draw(
            at: NSPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 2),
            withAttributes: attr
        )
    }
}

// MARK: - Screen Annotation Window (Text Penampang Input Box)
private final class ScreenAnnotationWindow: NSPanel {
    private let onCommit: (String) -> Void
    private let onCancel: () -> Void

    init(selectionRect: CGRect, screenshot: NSImage, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCommit = onCommit
        self.onCancel = onCancel

        let panelWidth = max(selectionRect.width, 180)
        let notePanelHeight: CGFloat = 124
        let imageHeight = max(1, selectionRect.height * panelWidth / max(selectionRect.width, 1))
        let totalHeight = imageHeight + notePanelHeight

        // Keep the annotation window attached to the selected region.
        var winY = selectionRect.minY - totalHeight - 8
        if winY < 20 {
            winY = selectionRect.maxY + 8
        }
        let winX = selectionRect.minX

        let frame = NSRect(x: winX, y: winY, width: panelWidth, height: totalHeight)

        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = ScreenAnnotationContentView(
            width: panelWidth,
            imageHeight: imageHeight,
            screenshot: screenshot,
            notePanelHeight: notePanelHeight,
            onCommit: onCommit,
            onCancel: onCancel
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Screen Annotation Content View (Typing UI)
private final class ScreenAnnotationContentView: NSView {
    private let onCommit: (String) -> Void
    private let onCancel: () -> Void
    private let imageView: NSImageView
    private let textView: NSTextView
    private let hintLabel: NSTextField

    init(width: CGFloat, imageHeight: CGFloat, screenshot: NSImage, notePanelHeight: CGFloat,
         onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCommit = onCommit
        self.onCancel = onCancel

        let textInsetH: CGFloat = 12
        let textViewHeight: CGFloat = notePanelHeight - 34

        imageView = NSImageView(image: screenshot)
        textView = NSTextView(frame: NSRect(
            x: textInsetH,
            y: 26,
            width: width - textInsetH * 2,
            height: textViewHeight
        ))

        hintLabel = NSTextField(labelWithString: "↩ Enter to copy image  •  ESC to copy without note")
        hintLabel.frame = NSRect(x: textInsetH, y: 7, width: width - textInsetH * 2, height: 16)

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: imageHeight + notePanelHeight))

        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 0.96).cgColor
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(white: 0.30, alpha: 0.8).cgColor

        imageView.frame = NSRect(x: 0, y: notePanelHeight, width: width, height: imageHeight)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.borderWidth = 1.0
        imageView.layer?.borderColor = NSColor(white: 0.85, alpha: 0.75).cgColor
        addSubview(imageView)

        // Text view setup
        textView.font = .systemFont(ofSize: 14)
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

        // Hint label setup
        hintLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        hintLabel.textColor = NSColor(white: 0.60, alpha: 1.0)
        addSubview(hintLabel)
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
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Check modifier: Shift+Enter allows newline in note, Enter commits
            if NSEvent.modifierFlags.contains(.shift) {
                return false // Insert newline
            }
            onCommit(textView.string)
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // ESC key: commit whatever is typed, or if empty commit empty (pure screenshot)
            if textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onCancel()
            } else {
                onCommit(textView.string)
            }
            return true
        }

        return false
    }
}
