import Cocoa

/// Single entry point for macro execution.
///
/// A dedicated serial queue prevents multiple macros from fighting over the
/// cursor, keyboard, clipboard, and frontmost window at the same time.
final class MacroRuntime {
    static let shared = MacroRuntime()

    private let executionQueue = DispatchQueue(
        label: "com.redmunky.shortking.macro-runtime",
        qos: .userInitiated
    )

    private init() {}

    func run(
        items: [MacroActionItem],
        macroID: UUID?,
        origin: CGPoint,
        windowRect: CGRect?
    ) {
        executionQueue.async {
            InputSimulator.execute(
                items: items,
                preRecordedOrigin: origin,
                preRecordedWindowRect: windowRect,
                macroID: macroID
            )
        }
    }

    func run(_ macro: MacroItem) {
        let origin = Self.currentCursorPosition()
        let windowRect = InputSimulator.getFrontmostWindowRect()
        run(items: macro.actionItems, macroID: macro.id, origin: origin, windowRect: windowRect)
    }

    func emergencyStop() {
        InputSimulator.isEmergencyStopped = true
        InputSimulator.releaseModifiers()
    }

    static func currentCursorPosition() -> CGPoint {
        if let location = CGEvent(source: nil)?.location, location != .zero {
            return location
        }

        let cocoaPoint = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
        return CGPoint(x: cocoaPoint.x, y: screenHeight - cocoaPoint.y)
    }
}
