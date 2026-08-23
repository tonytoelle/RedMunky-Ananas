import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

class CaptureOverlayState: ObservableObject {
    enum Phase {
        case recording   // Placing points sequentially on screen
        case editing     // Reviewing, dragging pins, toggling types, confirming
    }
    
    @Published var phase: Phase = .recording
    @Published var mode: CaptureOverlayWindow.Mode = .click(button: .left, initialPoint: nil)
    @Published var currentLocation: CGPoint = .zero       // In Cocoa window coordinates (bottom-left origin)
    @Published var quartzLocation: CGPoint = .zero        // In Quartz display coordinates (top-left origin)
    var onIsFollowingCursorChanged: ((Bool) -> Void)? = nil
    @Published var isFollowingCursor: Bool = true {
        didSet {
            onIsFollowingCursorChanged?(isFollowingCursor)
        }
    }
    
    var onPassThroughChanged: ((Bool) -> Void)? = nil
    @Published var lastPassthroughHUDLocation: CGPoint? = nil
    @Published var isPassThroughMode: Bool = false {
        didSet {
            if isPassThroughMode {
                // Lock current HUD position so it doesn't move during passthrough
                lastPassthroughHUDLocation = lastHudCenter
            } else {
                lastPassthroughHUDLocation = nil
            }
            onPassThroughChanged?(isPassThroughMode)
        }
    }
    
    var onPointsCommitted: (([SequencePoint]) -> Void)? = nil
    var onPointsRealtime: (([SequencePoint]) -> Void)? = nil
    @Published var points: [SequencePoint] = []
    
    func notifyPointsCommitted() {
        onPointsCommitted?(points)
    }
    
    func notifyPointsRealtime() {
        onPointsRealtime?(points)
    }
    @Published var activeDraggingIndex: Int? = nil
    @Published var hoveredIndex: Int? = nil
    @Published var selectedPointIndex: Int? = nil
    @Published var defaultPointType: SequencePointType = .move
    @Published var isHoveringHud: Bool = false
    @Published var lastHudCenter: CGPoint = .zero
    @Published var hudDragOffset: CGSize = CGSize(width: 100, height: 100) // Default relative distance offset
    
    var isHudVisible: Bool {
        guard case .sequence = mode else { return false }
        if isPassThroughMode { return true }
        if isFollowingCursor { return true }
        if selectedPointIndex != nil || activeDraggingIndex != nil || isHoveringHud { return true }
        if hoveredIndex != nil { return true }
        for p in points {
            let dx = quartzLocation.x - p.point.x
            let dy = quartzLocation.y - p.point.y
            if sqrt(dx * dx + dy * dy) <= 45 {
                return true
            }
        }
        return false
    }
    
    var onConfirmAll: (() -> Void)? = nil
    var onCancelAction: (() -> Void)? = nil
    var onResetAction: (() -> Void)? = nil
    
    func cycleType(at index: Int) {
        guard index >= 0 && index < points.count else { return }
        switch points[index].type {
        case .move:
            points[index].type = .drag
        case .drag:
            points[index].type = .click
        case .click:
            points[index].type = .move
        }
        notifyPointsCommitted()
    }
    
    func setType(_ type: SequencePointType, at index: Int) {
        guard index >= 0 && index < points.count else { return }
        points[index].type = type
        notifyPointsCommitted()
    }
    
    func removePoint(at index: Int) {
        guard index >= 0 && index < points.count else { return }
        points.remove(at: index)
        if points.isEmpty {
            phase = .recording
            isFollowingCursor = true
            selectedPointIndex = nil
        } else {
            selectedPointIndex = min(index, points.count - 1)
        }
        notifyPointsCommitted()
    }
    
    func insertPoint() {
        guard !isFollowingCursor else { return }
        isFollowingCursor = true
    }
}

func blendColors(typeA: SequencePointType, typeB: SequencePointType) -> Color {
    let r1, g1, b1: Double
    switch typeA {
    case .click: (r1, g1, b1) = (0.08, 0.55, 1.0)
    case .drag: (r1, g1, b1) = (0.68, 0.32, 0.87)
    case .move: (r1, g1, b1) = (0.28, 0.72, 0.52)
    }
    
    let r2, g2, b2: Double
    switch typeB {
    case .click: (r2, g2, b2) = (0.08, 0.55, 1.0)
    case .drag: (r2, g2, b2) = (0.68, 0.32, 0.87)
    case .move: (r2, g2, b2) = (0.28, 0.72, 0.52)
    }
    
    return Color(red: (r1 + r2) / 2.0, green: (g1 + g2) / 2.0, blue: (b1 + b2) / 2.0)
}

// ==========================================
// MARK: - Capture Overlay SwiftUI View (Minimalist Compact HUD)
// ==========================================
struct CaptureOverlaySwiftUIView: View {
    @ObservedObject var state: CaptureOverlayState
    @State private var dragStartOffset: CGSize = .zero
    @State private var pinDragStartPoint: CGPoint? = nil
    @State private var areaDragStartPoints: (CGPoint, CGPoint)? = nil
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Completely transparent background with no dimming in any phase
                Color.clear
                    .edgesIgnoringSafeArea(.all)
                
                // ─────────────────────────────────────────────
                // CONNECTING PATH LINES BETWEEN PINS (Color Gradient)
                // ─────────────────────────────────────────────
                if case .windowTransform = state.mode {
                    if state.points.count >= 2 {
                        let p1 = state.points[0].point
                        let p3 = state.points[1].point
                        let minX = min(p1.x, p3.x)
                        let minY = min(p1.y, p3.y)
                        let maxX = max(p1.x, p3.x)
                        let maxY = max(p1.y, p3.y)
                        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                        
                        // Fill overlay (draggable in edit mode)
                        Rectangle()
                            .fill(Color.blue.opacity(state.phase == .editing ? 0.12 : 0.08))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(state.phase == .editing)
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { val in
                                        guard state.phase == .editing, !state.isPassThroughMode else { return }
                                        if areaDragStartPoints == nil {
                                            areaDragStartPoints = (state.points[0].point, state.points[1].point)
                                        }
                                        if let (origP1, origP3) = areaDragStartPoints {
                                            state.points[0].point = CGPoint(
                                                x: max(0, min(origP1.x + val.translation.width, geo.size.width)),
                                                y: max(0, min(origP1.y + val.translation.height, geo.size.height))
                                            )
                                            state.points[1].point = CGPoint(
                                                x: max(0, min(origP3.x + val.translation.width, geo.size.width)),
                                                y: max(0, min(origP3.y + val.translation.height, geo.size.height))
                                            )
                                            state.notifyPointsRealtime()
                                        }
                                    }
                                    .onEnded { _ in
                                        areaDragStartPoints = nil
                                        state.notifyPointsCommitted()
                                    }
                            )
                        
                        // Dashed border
                        Path { path in path.addRect(rect) }
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .allowsHitTesting(false)
                        
                        // ── 2 Diagonal round pins without labels ──
                        if state.phase == .editing {
                            ForEach(0..<2, id: \.self) { idx in
                                let isSelected = state.selectedPointIndex == idx
                                Circle()
                                    .stroke(Color.white, lineWidth: isSelected ? 3.0 : 2.0)
                                    .background(Circle().fill(Color.blue))
                                    .frame(width: isSelected ? 24 : 20, height: isSelected ? 24 : 20)
                                    .shadow(color: Color.black.opacity(0.35), radius: 2)
                                    .position(state.points[idx].point)
                                    .gesture(
                                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                            .onChanged { val in
                                                state.activeDraggingIndex = idx
                                                state.selectedPointIndex = idx
                                                if pinDragStartPoint == nil {
                                                    pinDragStartPoint = state.points[idx].point
                                                }
                                                if let startPt = pinDragStartPoint {
                                                    let newX = max(0, min(startPt.x + val.translation.width, geo.size.width))
                                                    let newY = max(0, min(startPt.y + val.translation.height, geo.size.height))
                                                    state.points[idx].point = CGPoint(x: newX, y: newY)
                                                    state.notifyPointsRealtime()
                                                }
                                            }
                                            .onEnded { _ in
                                                state.activeDraggingIndex = nil
                                                pinDragStartPoint = nil
                                                state.notifyPointsCommitted()
                                            }
                                    )
                                    .onTapGesture {
                                        state.selectedPointIndex = idx
                                    }
                            }
                        }
                    }
                } else if state.points.count > 1 {
                    ForEach(0..<(state.points.count - 1), id: \.self) { idx in
                        let start = state.points[idx].point
                        let end = state.points[idx + 1].point
                        let ptA = state.points[idx]
                        let ptB = state.points[idx + 1]
                        
                        let isLineBeingBypassed = state.isFollowingCursor && state.selectedPointIndex == idx
                        let lineOpacityMultiplier: Double = isLineBeingBypassed ? 0.0 : (state.isPassThroughMode ? 0.35 : 1.0)
                        
                        let midColor = blendColors(typeA: ptA.type, typeB: ptB.type)
                        
                        let grad = LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: ptA.type.color.opacity(0.0), location: 0.0),
                                .init(color: midColor.opacity(0.95 * lineOpacityMultiplier), location: 0.5),
                                .init(color: ptB.type.color.opacity(0.0), location: 1.0)
                            ]),
                            startPoint: UnitPoint(x: start.x / max(1, geo.size.width), y: start.y / max(1, geo.size.height)),
                            endPoint: UnitPoint(x: end.x / max(1, geo.size.width), y: end.y / max(1, geo.size.height))
                        )
                        
                        Path { path in
                            path.move(to: start)
                            path.addLine(to: end)
                        }
                        .stroke(
                            grad,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 5])
                        )
                        .allowsHitTesting(false)
                    }
                }
                
                // Active cursor preview lines (if inserting a point in between existing points)
                if state.isFollowingCursor, let sel = state.selectedPointIndex, sel < state.points.count {
                    let start = state.points[sel].point
                    let end = state.quartzLocation
                    let ptA = state.points[sel]
                    
                    let lineOpacityMultiplier: Double = state.isPassThroughMode ? 0.35 : 1.0
                    let midColor = blendColors(typeA: ptA.type, typeB: state.defaultPointType)
                    let grad = LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: ptA.type.color.opacity(0.0), location: 0.0),
                            .init(color: midColor.opacity(0.95 * lineOpacityMultiplier), location: 0.5),
                            .init(color: state.defaultPointType.color.opacity(0.0), location: 1.0)
                        ]),
                        startPoint: UnitPoint(x: start.x / max(1, geo.size.width), y: start.y / max(1, geo.size.height)),
                        endPoint: UnitPoint(x: end.x / max(1, geo.size.width), y: end.y / max(1, geo.size.height))
                    )
                    
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                    .stroke(
                        grad,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 5])
                    )
                    
                    // If not at the very end, also draw line from cursor to the next point
                    if sel + 1 < state.points.count {
                        let nextPt = state.points[sel + 1]
                        let nextStart = end
                        let nextEnd = nextPt.point
                        
                        let midColor2 = blendColors(typeA: state.defaultPointType, typeB: nextPt.type)
                        let nextGrad = LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: state.defaultPointType.color.opacity(0.0), location: 0.0),
                                .init(color: midColor2.opacity(0.95 * lineOpacityMultiplier), location: 0.5),
                                .init(color: nextPt.type.color.opacity(0.0), location: 1.0)
                            ]),
                            startPoint: UnitPoint(x: nextStart.x / max(1, geo.size.width), y: nextStart.y / max(1, geo.size.height)),
                            endPoint: UnitPoint(x: nextEnd.x / max(1, geo.size.width), y: nextEnd.y / max(1, geo.size.height))
                        )
                        
                        Path { path in
                            path.move(to: nextStart)
                            path.addLine(to: nextEnd)
                        }
                        .stroke(
                            nextGrad,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 5])
                        )
                    }
                }
                
                // ─────────────────────────────────────────────
                // PINS RENDERING (Compact Clean Minimal Circles)
                // ─────────────────────────────────────────────
                // PINS RENDERING (Compact Clean Minimal Circles)
                // ─────────────────────────────────────────────
                if !state.mode.isWindowTransform {
                    ForEach(Array(state.points.enumerated()), id: \.element.id) { idx, item in
                        let isHovered = state.hoveredIndex == idx
                        let isDragging = state.activeDraggingIndex == idx
                        let isSelected = state.selectedPointIndex == idx
                        
                        Group {
                            pinMarker(
                                number: "\(idx + 1)",
                                type: item.type,
                                isSelected: isSelected,
                                isHovered: isHovered,
                                isDragging: isDragging,
                                repeatCount: item.repeatCount
                            )
                        }
                        .position(x: item.point.x, y: item.point.y)
                        .opacity(state.isPassThroughMode ? 0.35 : 1.0)
                        .allowsHitTesting(!state.isPassThroughMode)
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { val in
                                    state.activeDraggingIndex = idx
                                    state.selectedPointIndex = idx
                                    if pinDragStartPoint == nil {
                                        pinDragStartPoint = item.point
                                    }
                                    if let startPt = pinDragStartPoint {
                                        let newX = max(0, min(startPt.x + val.translation.width, geo.size.width))
                                        let newY = max(0, min(startPt.y + val.translation.height, geo.size.height))
                                        
                                        state.points[idx].point = CGPoint(x: newX, y: newY)
                                    }
                                }
                                .onEnded { _ in
                                    state.activeDraggingIndex = nil
                                    pinDragStartPoint = nil
                                    state.notifyPointsCommitted()
                                }
                        )
                        .onTapGesture {
                            state.selectedPointIndex = idx
                        }
                    }
                }
                
                
                // ─────────────────────────────────────────────
                // FLOATING COMPACT HUD CARD (Hover-based visibility, sequence only)
                // ─────────────────────────────────────────────
                if case .sequence = state.mode {
                    let pos = hudPosition(in: geo.size)
                    floatingHUDCard
                        .position(pos)
                        .opacity(state.isHudVisible ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.15), value: state.isHudVisible)
                        .onAppear { state.lastHudCenter = pos }
                        .onChange(of: pos) { _, newPos in state.lastHudCenter = newPos }
                        .allowsHitTesting(true)
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { val in
                                    guard !state.isPassThroughMode else { return }
                                    if dragStartOffset == .zero {
                                        dragStartOffset = state.hudDragOffset
                                    }
                                    state.hudDragOffset = CGSize(
                                        width: dragStartOffset.width + val.translation.width,
                                        height: dragStartOffset.height + val.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    dragStartOffset = .zero
                                }
                        )
                } else if case .windowTransform = state.mode, state.phase == .editing {
                    let pos = hudPosition(in: geo.size)
                    windowTransformHUDCard
                        .position(pos)
                        .opacity(1.0)
                        .onAppear { state.lastHudCenter = pos }
                        .onChange(of: pos) { _, newPos in state.lastHudCenter = newPos }
                        .allowsHitTesting(true)
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { val in
                                    guard !state.isPassThroughMode else { return }
                                    if dragStartOffset == .zero {
                                        dragStartOffset = state.hudDragOffset
                                    }
                                    state.hudDragOffset = CGSize(
                                        width: dragStartOffset.width + val.translation.width,
                                        height: dragStartOffset.height + val.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    dragStartOffset = .zero
                                }
                        )
                }
                
                if state.isFollowingCursor && !state.isPassThroughMode {
                    ZStack {
                        // Outer circular outline
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                            .frame(width: 28, height: 28)
                            .shadow(color: Color.black.opacity(0.35), radius: 2)
                        
                        // Solid centered dot with action color
                        Circle()
                            .fill(state.defaultPointType.color)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.black.opacity(0.35), radius: 1.5)
                    }
                    .position(state.quartzLocation)
                    .allowsHitTesting(false)
                }
            }
        }
    }
    
    // MARK: - Minimal Compact Pin Marker
    @ViewBuilder
    private func pinMarker(
        number: String,
        type: SequencePointType,
        isSelected: Bool,
        isHovered: Bool,
        isDragging: Bool,
        repeatCount: Int = 1
    ) -> some View {
        ZStack {
            // Outer highlight ring when active
            if isHovered || isDragging || isSelected {
                Circle()
                    .stroke(type.color.opacity(0.4), lineWidth: 3.5)
                    .frame(width: 32, height: 32)
            }
            
            // White outline circular ring (similar to cursor ring)
            Circle()
                .stroke(Color.white, lineWidth: isSelected ? 2.5 : 1.5)
                .frame(width: 26, height: 26)
                .shadow(color: Color.black.opacity(0.35), radius: 2)
            
            // Solid center action type dot
            Circle()
                .fill(type.color)
                .frame(width: 8, height: 8)
                .shadow(color: Color.black.opacity(0.2), radius: 1)
            
            // Minimal text indicator above or below the circle to not block center dot
            Text(repeatCount > 1 ? "\(number) (x\(repeatCount))" : number)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .offset(y: -18)
        }
        .frame(width: 32, height: 32)
        .contentShape(Circle())
    }
    
    @ViewBuilder
    private func circlePin(at point: CGPoint, label: String, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 26, height: 26)
                .shadow(color: Color.black.opacity(0.35), radius: 2)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .offset(y: -18)
        }
        .position(point)
    }
    
    // MARK: - Minimal Compact Floating Action HUD Card
    @ViewBuilder
    private var floatingHUDCard: some View {
        let currentType: SequencePointType = {
            if state.phase == .editing, let sel = state.selectedPointIndex, sel < state.points.count {
                return state.points[sel].type
            }
            if let last = state.points.last {
                return last.type
            }
            return state.defaultPointType
        }()
        
        return HStack(spacing: 8) {
            // Left: Squircle Action Type Icon Button
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(currentType.color)
                    .frame(width: 34, height: 34)
                    .shadow(color: currentType.color.opacity(0.4), radius: 3)
                
                Image(systemName: currentType.icon == "hand.draw" ? "hand.tap.fill" : currentType.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .opacity(state.isPassThroughMode ? 0.35 : 1.0)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !state.isPassThroughMode else { return }
                if let sel = state.selectedPointIndex, sel < state.points.count {
                    state.cycleType(at: sel)
                    state.defaultPointType = state.points[sel].type
                } else if !state.points.isEmpty {
                    let lastIdx = state.points.count - 1
                    state.cycleType(at: lastIdx)
                    state.defaultPointType = state.points[lastIdx].type
                } else {
                    switch state.defaultPointType {
                    case .move: state.defaultPointType = .drag
                    case .drag: state.defaultPointType = .click
                    case .click: state.defaultPointType = .move
                    }
                }
            }
            
            // Plus button to insert/add a point
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 34, height: 34)
                
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            .opacity(state.isPassThroughMode ? 0.35 : 1.0)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !state.isPassThroughMode else { return }
                state.insertPoint()
            }
            
            // Minus button to delete/remove the selected or last point
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 34, height: 34)
                
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            .opacity(state.isPassThroughMode ? 0.35 : 1.0)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !state.isPassThroughMode else { return }
                if let sel = state.selectedPointIndex, sel < state.points.count {
                    state.removePoint(at: sel)
                } else if !state.points.isEmpty {
                    state.removePoint(at: state.points.count - 1)
                }
            }
            
            // Pass-Through Toggle Button (Allows clicking apps underneath while seeing 20% opacity pins)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(state.isPassThroughMode ? Color.accentColor : Color.white.opacity(0.15))
                    .frame(width: 34, height: 34)
                
                Image(systemName: state.isPassThroughMode ? "cursorarrow.slash" : "cursorarrow.and.square.on.square.dashed")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                state.isPassThroughMode.toggle()
            }
            
            // Repeat Point Dropdown Menu
            let selectedPointRepeat: Int = {
                if let sel = state.selectedPointIndex, sel < state.points.count {
                    return state.points[sel].repeatCount
                }
                return 1
            }()
            
            Menu {
                ForEach([1, 2, 3, 5, 10], id: \.self) { r in
                    Button(r == 1 ? "1x (No Repeat)" : "Repeat \(r)x") {
                        if let sel = state.selectedPointIndex, sel < state.points.count {
                            state.points[sel].repeatCount = r
                            state.notifyPointsRealtime()
                        }
                    }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selectedPointRepeat > 1 ? Color.purple : Color.white.opacity(0.15))
                        .frame(width: 44, height: 34)
                    
                    Text("\(selectedPointRepeat)x")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .menuStyle(.borderlessButton)
            .opacity(state.selectedPointIndex != nil && !state.isPassThroughMode ? 1.0 : 0.35)
            .disabled(state.selectedPointIndex == nil || state.isPassThroughMode)
            
            // Green Confirm/Save Checkmark Button
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green)
                    .frame(width: 34, height: 34)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                state.onConfirmAll?()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.05).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(state.isPassThroughMode ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.65), radius: 8, y: 3)
    }
    
    @ViewBuilder
    private var windowTransformHUDCard: some View {
        HStack(spacing: 12) {
            Text("Edit Window Transform")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            
            Button(action: {
                state.onCancelAction?()
            }) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green)
                    .frame(width: 34, height: 34)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                state.onConfirmAll?()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.05).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.65), radius: 8, y: 3)
    }
    
    // MARK: - HUD Dynamic Position Following Cursor / Active Pin
    private func hudPosition(in size: CGSize) -> CGPoint {
        // If in passthrough mode, use the locked HUD location so it doesn't run away from the cursor
        if let lockedLoc = state.lastPassthroughHUDLocation {
            return lockedLoc
        }
        
        let targetPt: CGPoint
        if !state.isFollowingCursor, let sel = state.selectedPointIndex, sel < state.points.count {
            targetPt = state.points[sel].point
        } else {
            targetPt = state.quartzLocation
        }
        
        var x = targetPt.x + state.hudDragOffset.width
        var y = targetPt.y + state.hudDragOffset.height
        
        // Prevent HUD going off screen
        if x + 75 > size.width {
            x = size.width - 75
        }
        if y + 25 > size.height {
            y = size.height - 25
        }
        if x < 75 { x = 75 }
        if y < 25 { y = 25 }
        
        return CGPoint(x: x, y: y)
    }
}

// ==========================================
// MARK: - Capture Overlay NSView Host
// ==========================================
class CaptureOverlayHostingView: NSView {
    var mode: CaptureOverlayWindow.Mode
    var onFinishSequence: ([SequencePoint]) -> Void
    var onCancel: () -> Void
    var onPointsChanged: ([SequencePoint]) -> Void
    var onWindowTransformCaptured: ((CGPoint, CGPoint, CGPoint, CGPoint) -> Void)? = nil
    
    private var trackingArea: NSTrackingArea?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var stateModel = CaptureOverlayState()
    private var isDrawingNewRect = false
    
    init(mode: CaptureOverlayWindow.Mode,
         initialPoints: [SequencePoint] = [],
         defaultType: SequencePointType = .move,
         onFinishSequence: @escaping ([SequencePoint]) -> Void,
         onCancel: @escaping () -> Void,
         onPointsCommitted: @escaping ([SequencePoint]) -> Void,
         onPointsRealtime: @escaping ([SequencePoint]) -> Void) {
        self.mode = mode
        self.onFinishSequence = onFinishSequence
        self.onCancel = onCancel
        self.onPointsChanged = onPointsCommitted
        super.init(frame: .zero)
        
        stateModel.onPointsCommitted = onPointsCommitted
        stateModel.onPointsRealtime = onPointsRealtime
        
        stateModel.mode = mode
        stateModel.defaultPointType = defaultType
        stateModel.points = initialPoints
        
        // Instantly initialize mouse location to prevent (0,0) startup coordinate lag/flicker
        let initialMouseLoc = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
        stateModel.quartzLocation = CGPoint(x: initialMouseLoc.x, y: screenHeight - initialMouseLoc.y)
        
        if !initialPoints.isEmpty {
            stateModel.phase = .editing
            stateModel.selectedPointIndex = nil
            stateModel.isFollowingCursor = false
        } else {
            stateModel.phase = .recording
            stateModel.isFollowingCursor = true
        }
        
        stateModel.onIsFollowingCursorChanged = { [weak self] following in
            guard let self = self else { return }
            self.window?.invalidateCursorRects(for: self)
            if following && !self.stateModel.isPassThroughMode {
                NSCursor.hide()
                self.window?.ignoresMouseEvents = false
                
                // Get current mouse location instantly
                let mouseLoc = NSEvent.mouseLocation
                let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
                let quartzPt = CGPoint(x: mouseLoc.x, y: screenHeight - mouseLoc.y)
                self.stateModel.quartzLocation = quartzPt
            } else {
                NSCursor.unhide()
            }
        }
        
        stateModel.onPassThroughChanged = { [weak self] isPassThrough in
            guard let self = self else { return }
            self.window?.invalidateCursorRects(for: self)
            if isPassThrough {
                NSCursor.unhide()
            } else if self.stateModel.isFollowingCursor {
                NSCursor.hide()
            } else {
                NSCursor.unhide()
            }
        }
        
        stateModel.onConfirmAll = { [weak self] in
            guard let self = self else { return }
            self.cleanupMonitors()
            self.onFinishSequence(self.stateModel.points)
        }
        stateModel.onCancelAction = { [weak self] in
            self?.cleanupMonitors()
            self?.onCancel()
        }
        stateModel.onResetAction = { [weak self] in
            self?.stateModel.points.removeAll()
            self?.stateModel.phase = .recording
            self?.stateModel.isFollowingCursor = true
            self?.stateModel.activeDraggingIndex = nil
            self?.stateModel.hoveredIndex = nil
            self?.stateModel.selectedPointIndex = nil
        }
        
        let swiftUIView = CaptureOverlaySwiftUIView(state: stateModel)
        let host = NSHostingView(rootView: swiftUIView)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    deinit {
        CaptureOverlayHostingView.safeUnhideCursor()
        cleanupMonitors()
    }

    private static var cursorHideCount = 0

    static func safeHideCursor() {
        if cursorHideCount == 0 {
            NSCursor.hide()
        }
        cursorHideCount += 1
    }

    static func safeUnhideCursor() {
        while cursorHideCount > 0 {
            NSCursor.unhide()
            cursorHideCount -= 1
        }
        NSCursor.unhide()
        // Force Cocoa to set cursor back to arrow state
        DispatchQueue.main.async {
            NSCursor.arrow.set()
        }
    }

    private func cleanupMonitors() {
        CaptureOverlayHostingView.safeUnhideCursor()
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let win = window {
            if stateModel.isFollowingCursor && !stateModel.isPassThroughMode {
                CaptureOverlayHostingView.safeHideCursor()
            }
            let screenPt = NSEvent.mouseLocation
            let winLoc = win.convertPoint(fromScreen: screenPt)
            let screenHeight = win.screen?.frame.height ?? NSScreen.main?.frame.height ?? bounds.height
            let quartzPt = CGPoint(x: winLoc.x, y: screenHeight - winLoc.y)
            stateModel.currentLocation = winLoc
            stateModel.quartzLocation = quartzPt
            win.makeFirstResponder(self)
            
            if localKeyMonitor == nil {
                localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self = self else { return event }
                    if event.keyCode == 53 { // Escape
                        self.stateModel.onCancelAction?()
                        return nil
                    } else if event.keyCode == 36 || event.keyCode == 76 { // Enter / Return
                        self.stateModel.onConfirmAll?()
                        return nil
                    }
                    return event
                }
            }
            
            if globalKeyMonitor == nil {
                globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self = self else { return }
                    if event.keyCode == 53 { // Escape
                        self.stateModel.onCancelAction?()
                    } else if event.keyCode == 36 || event.keyCode == 76 { // Enter / Return
                        self.stateModel.onConfirmAll?()
                    }
                }
            }
            
            if globalMouseMonitor == nil {
                globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]) { [weak self] event in
                    guard let self = self, let win = self.window else { return }
                    let screenPt = NSEvent.mouseLocation
                    let winLoc = win.convertPoint(fromScreen: screenPt)
                    let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
                    let quartzPt = CGPoint(x: winLoc.x, y: screenHeight - winLoc.y)
                    
                    DispatchQueue.main.async {
                        self.stateModel.currentLocation = winLoc
                        self.stateModel.quartzLocation = quartzPt
                        self.updateHover(quartzPt: quartzPt)
                        self.updatePassthrough(quartzPt: quartzPt)
                    }
                }
            }
            
            if localMouseMonitor == nil {
                localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]) { [weak self] event in
                    guard let self = self, let win = self.window else { return event }
                    let screenPt = NSEvent.mouseLocation
                    let winLoc = win.convertPoint(fromScreen: screenPt)
                    let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
                    let quartzPt = CGPoint(x: winLoc.x, y: screenHeight - winLoc.y)
                    
                    self.stateModel.currentLocation = winLoc
                    self.stateModel.quartzLocation = quartzPt
                    self.updateHover(quartzPt: quartzPt)
                    self.updatePassthrough(quartzPt: quartzPt)
                    
                    return event
                }
            }
        } else {
            cleanupMonitors()
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            stateModel.onCancelAction?()
        } else if event.keyCode == 36 || event.keyCode == 76 {
            stateModel.onConfirmAll?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let ta = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }
    
    private func dist(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    private func updateHover(quartzPt: CGPoint) {
        var foundIdx: Int? = nil
        for (i, p) in stateModel.points.enumerated() {
            if dist(quartzPt, p.point) <= 26 {
                foundIdx = i
                break
            }
        }
        stateModel.hoveredIndex = foundIdx
    }
    
    // Dynamically toggle window.ignoresMouseEvents for full passthrough in edit mode
    private func updatePassthrough(quartzPt: CGPoint) {
        guard let win = self.window else { return }
        
        // In pass-through mode: ONLY HUD card can be clicked, everything else clicks through to apps underneath!
        if stateModel.isPassThroughMode {
            if stateModel.isHudVisible {
                let hud = stateModel.lastHudCenter
                if CGRect(x: hud.x - 110, y: hud.y - 30, width: 220, height: 60).contains(quartzPt) {
                    win.ignoresMouseEvents = false
                    return
                }
            }
            win.ignoresMouseEvents = true
            return
        }
        
        // If we are actively placing a point (following cursor), we must capture clicks!
        guard !stateModel.isFollowingCursor else {
            win.ignoresMouseEvents = false
            return
        }
        
        guard stateModel.activeDraggingIndex == nil else {
            win.ignoresMouseEvents = false
            return
        }
        
        // Check proximity to any pin
        for p in stateModel.points {
            if dist(quartzPt, p.point) <= 30 {
                win.ignoresMouseEvents = false
                return
            }
        }
        
        // Check if cursor is inside the windowTransform rectangle area
        if case .windowTransform = stateModel.mode, stateModel.points.count == 2 {
            let p1 = stateModel.points[0].point
            let p3 = stateModel.points[1].point
            let rect = CGRect(
                x: min(p1.x, p3.x) - 4,
                y: min(p1.y, p3.y) - 4,
                width: abs(p3.x - p1.x) + 8,
                height: abs(p3.y - p1.y) + 8
            )
            if rect.contains(quartzPt) {
                win.ignoresMouseEvents = false
                return
            }
        }
        
        // Check HUD card
        if stateModel.isHudVisible {
            let hud = stateModel.lastHudCenter
            if CGRect(x: hud.x - 130, y: hud.y - 30, width: 260, height: 60).contains(quartzPt) {
                win.ignoresMouseEvents = false
                return
            }
        }
        
        // Empty area: let all events pass through to the window underneath
        win.ignoresMouseEvents = true
    }
    
    private func updateMouse(event: NSEvent) {
        let winLoc = event.locationInWindow
        let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let quartzPt = CGPoint(x: winLoc.x, y: screenHeight - winLoc.y)
        
        stateModel.currentLocation = winLoc
        stateModel.quartzLocation = quartzPt
        updateHover(quartzPt: quartzPt)
    }
    
    // MARK: - Accepts First Mouse (Instant interaction even when background apps are active)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }
    
    // MARK: - Hit Testing (Native macOS Click-Through)
    override func hitTest(_ point: NSPoint) -> NSView? {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let quartzPt = CGPoint(x: point.x, y: screenHeight - point.y)
        
        // In pass-through mode: ONLY HUD card can be clicked!
        if stateModel.isPassThroughMode {
            if stateModel.isHudVisible {
                let hudPos = stateModel.lastHudCenter
                let hudRect = CGRect(x: hudPos.x - 160, y: hudPos.y - 30, width: 320, height: 60)
                if hudRect.contains(quartzPt) {
                    return super.hitTest(point)
                }
            }
            return nil
        }
        
        if stateModel.isFollowingCursor {
            return super.hitTest(point)
        }
        
        // During edit: only capture clicks directly on/near pins
        for p in stateModel.points {
            if dist(quartzPt, p.point) <= 26 {
                return super.hitTest(point)
            }
        }
        
        // Or clicks directly on the HUD card
        if stateModel.isHudVisible {
            let hudPos = stateModel.lastHudCenter
            let hudRect = CGRect(x: hudPos.x - 160, y: hudPos.y - 30, width: 320, height: 60)
            if hudRect.contains(quartzPt) {
                return super.hitTest(point)
            }
        }
        
        // Return nil on empty background so macOS WindowServer natively delivers
        // all clicks, scrolls, drags, right-clicks to the window underneath!
        return nil
    }
    
    override func mouseMoved(with event: NSEvent) {
        updateMouse(event: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        updateMouse(event: event)
        if let idx = stateModel.activeDraggingIndex, idx < stateModel.points.count {
            stateModel.points[idx].point = stateModel.quartzLocation
            stateModel.notifyPointsRealtime()
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let wasDragging = (stateModel.activeDraggingIndex != nil)
        stateModel.activeDraggingIndex = nil
        if isDrawingNewRect {
            isDrawingNewRect = false
            stateModel.phase = .editing
            stateModel.selectedPointIndex = nil
            stateModel.notifyPointsCommitted()
            CaptureOverlayHostingView.safeUnhideCursor()
            // Keep window interactive and key so Enter/Esc work
            window?.ignoresMouseEvents = false
            window?.makeKey()
            window?.makeFirstResponder(self)
        } else if wasDragging {
            stateModel.notifyPointsCommitted()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        updateMouse(event: event)
        
        if stateModel.isFollowingCursor {
            let newPt = SequencePoint(point: stateModel.quartzLocation, type: stateModel.defaultPointType)
            
            switch stateModel.mode {
            case .click:
                stateModel.points = [newPt]
                stateModel.isFollowingCursor = false
                stateModel.onConfirmAll?()
                return
                
            case .drag:
                if stateModel.points.isEmpty {
                    stateModel.points.append(newPt)
                    stateModel.selectedPointIndex = 0
                    stateModel.notifyPointsCommitted()
                } else {
                    stateModel.points.append(newPt)
                    stateModel.isFollowingCursor = false
                    stateModel.onConfirmAll?()
                    return
                }
                
            case .sequence:
                let insertIndex: Int
                if let sel = stateModel.selectedPointIndex, sel < stateModel.points.count {
                    insertIndex = sel + 1
                } else {
                    insertIndex = stateModel.points.count
                }
                
                if insertIndex >= stateModel.points.count {
                    stateModel.points.append(newPt)
                    stateModel.selectedPointIndex = stateModel.points.count - 1
                } else {
                    stateModel.points.insert(newPt, at: insertIndex)
                    stateModel.selectedPointIndex = insertIndex
                }
                // Set following cursor to false so user has to click HUD "+" button to add another point
                stateModel.isFollowingCursor = false
                stateModel.phase = .editing
                
                // Keep windows ignores mouse events updated
                updatePassthrough(quartzPt: stateModel.quartzLocation)
                stateModel.notifyPointsCommitted()
                
            case .windowTransform:
                stateModel.points = [newPt, newPt]
                stateModel.selectedPointIndex = 1
                stateModel.activeDraggingIndex = 1
                isDrawingNewRect = true
                stateModel.isFollowingCursor = false
                window?.ignoresMouseEvents = false
                stateModel.notifyPointsRealtime()
            }
        } else {
            // Edit phase: handled when clicking directly on a pin
            var found: Int? = nil
            for (i, p) in stateModel.points.enumerated() {
                if dist(stateModel.quartzLocation, p.point) <= 26 {
                    found = i
                    break
                }
            }
            
            if let f = found {
                stateModel.selectedPointIndex = f
                stateModel.activeDraggingIndex = f
                window?.ignoresMouseEvents = false  // Must receive drag events
            } else {
                stateModel.selectedPointIndex = nil
                stateModel.activeDraggingIndex = nil
            }
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }
    
}

// ==========================================
// MARK: - Execution Cursor Ghost Overlay
// ==========================================
/// Floating window that renders an exact clone of the macOS default arrow cursor
/// at the resting origin coordinate while a macro is executing.
class ExecutionCursorOverlayWindow: NSPanel {
    static var shared: ExecutionCursorOverlayWindow?

    // Show the ghost cursor at the given Quartz (top-left origin) point
    static func show(at quartzPoint: CGPoint) {
        DispatchQueue.main.async {
            shared?.close()
            shared = nil

            // Find which screen contains this point
            let screen = NSScreen.screens.first {
                let f = $0.frame
                return f.contains(CGPoint(x: quartzPoint.x, y: f.height - quartzPoint.y + f.minY))
            } ?? NSScreen.main

            let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            // Convert Quartz top-left → Cocoa bottom-left
            let cocoaX = quartzPoint.x
            let cocoaY = screenFrame.maxY - quartzPoint.y

            // Fetch the system cursor scale factor (defaults to 1.0, e.g. normal size)
            let scaleFactor: CGFloat = {
                if let val = CFPreferencesCopyAppValue("mouseDriverCursorSize" as CFString, "com.apple.universalaccess" as CFString) as? Float {
                    return CGFloat(val)
                }
                return 1.0
            }()

            let cursorImage = NSCursor.arrow.image
            let baseSize = cursorImage.size
            let targetW = baseSize.width * scaleFactor
            let targetH = baseSize.height * scaleFactor

            // Offset the window slightly (5px left, 4px up) to align the cursor arrow's tip/hotspot with the target coordinate
            let offsetLeft = 5.0 * scaleFactor
            let offsetTop = 4.0 * scaleFactor
            let frame = NSRect(x: cocoaX - offsetLeft, y: (cocoaY - targetH) + offsetTop, width: targetW, height: targetH)

            let win = ExecutionCursorOverlayWindow(contentRect: frame, cursorImage: cursorImage)
            win.orderFrontRegardless()
            shared = win
        }
    }

    static func hide() {
        DispatchQueue.main.async {
            shared?.close()
            shared = nil
        }
    }

    init(contentRect: NSRect, cursorImage: NSImage) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height))
        imageView.image = cursorImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTopLeft
        contentView = imageView
    }
}

// ==========================================
// MARK: - Capture Overlay Window
// ==========================================
class CaptureOverlayWindow: NSPanel {
    static var shared: CaptureOverlayWindow? {
        didSet {
            if let old = oldValue, old !== shared {
                old.close()
            }
        }
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    enum Mode {
        case click(button: CGMouseButton = .left, initialPoint: CGPoint? = nil)
        case drag(initialStart: CGPoint? = nil, initialEnd: CGPoint? = nil)
        case sequence(initialPoints: [SequencePoint] = [])
        case windowTransform(initialPoints: [SequencePoint] = [])
        
        var isWindowTransform: Bool {
            if case .windowTransform = self { return true }
            return false
        }
    }
    
    private var mode: Mode
    private var onClickCaptured: ((CGPoint) -> Void)?
    private var onClickRealTime: ((CGPoint) -> Void)?
    
    private var onDragCaptured: ((CGPoint, CGPoint) -> Void)?
    private var onDragRealTime: ((CGPoint, CGPoint) -> Void)?
    
    private var onSequenceCaptured: (([SequencePoint]) -> Void)?
    private var onSequenceRealTime: (([SequencePoint]) -> Void)?
    
    var onWindowTransformCaptured: ((CGPoint, CGPoint, CGPoint, CGPoint) -> Void)?
    
    init(mode: Mode = .click(button: .left, initialPoint: nil), 
         onClickCaptured: @escaping (CGPoint) -> Void,
         onClickRealTime: ((CGPoint) -> Void)? = nil) {
        self.mode = mode
        self.onClickCaptured = onClickCaptured
        self.onClickRealTime = onClickRealTime
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(contentRect: screenRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        
        var initPoints: [SequencePoint] = []
        if case .click(_, let pt) = mode, let pt = pt {
            initPoints = [SequencePoint(point: pt, type: .click)]
        }
        setupWindow(initialPoints: initPoints, defaultType: .click)
    }
    
    init(mode: Mode = .drag(initialStart: nil, initialEnd: nil), 
         onDragCaptured: @escaping (CGPoint, CGPoint) -> Void,
         onDragRealTime: ((CGPoint, CGPoint) -> Void)? = nil) {
        self.mode = mode
        self.onDragCaptured = onDragCaptured
        self.onDragRealTime = onDragRealTime
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(contentRect: screenRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        
        var initPoints: [SequencePoint] = []
        if case .drag(let s, let e) = mode {
            if let s = s, let e = e {
                initPoints = [SequencePoint(point: s, type: .drag), SequencePoint(point: e, type: .drag)]
            } else if let s = s {
                initPoints = [SequencePoint(point: s, type: .drag)]
            }
        }
        setupWindow(initialPoints: initPoints, defaultType: .drag)
    }
    
    init(initialPoints: [SequencePoint] = [], 
         defaultType: SequencePointType = .move, 
         onSequenceCaptured: @escaping ([SequencePoint]) -> Void,
         onSequenceRealTime: (([SequencePoint]) -> Void)? = nil) {
        self.mode = .sequence(initialPoints: initialPoints)
        self.onSequenceCaptured = onSequenceCaptured
        self.onSequenceRealTime = onSequenceRealTime
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(contentRect: screenRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        setupWindow(initialPoints: initialPoints, defaultType: defaultType)
    }
    
    init(mode: Mode = .windowTransform(initialPoints: []), 
         onWindowTransformCaptured: @escaping (CGPoint, CGPoint, CGPoint, CGPoint) -> Void) {
        self.mode = mode
        self.onWindowTransformCaptured = onWindowTransformCaptured
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(contentRect: screenRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        
        var initPoints: [SequencePoint] = []
        if case .windowTransform(let pts) = mode {
            initPoints = pts
        }
        setupWindow(initialPoints: initPoints, defaultType: .click)
    }
    
    private func setupWindow(initialPoints: [SequencePoint], defaultType: SequencePointType) {
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let contentView = CaptureOverlayHostingView(mode: self.mode,
                                                   initialPoints: initialPoints,
                                                   defaultType: defaultType,
                                                   onFinishSequence: { [weak self] finalPoints in
            guard let self = self else { return }
            self.close()
            CaptureOverlayWindow.shared = nil
            
            switch self.mode {
            case .click:
                if let pt = finalPoints.first?.point {
                    self.onClickCaptured?(pt)
                }
            case .drag:
                if finalPoints.count >= 2 {
                    self.onDragCaptured?(finalPoints[0].point, finalPoints[1].point)
                }
            case .sequence:
                self.onSequenceCaptured?(finalPoints)
            case .windowTransform:
                if finalPoints.count >= 2 {
                    let p1 = finalPoints[0].point
                    let p3 = finalPoints[1].point
                    let p2 = CGPoint(x: p3.x, y: p1.y)
                    let p4 = CGPoint(x: p1.x, y: p3.y)
                    self.onWindowTransformCaptured?(p1, p2, p3, p4)
                }
            }
        }, onCancel: { [weak self] in
            self?.close()
            CaptureOverlayWindow.shared = nil
        }, onPointsCommitted: { [weak self] currentPoints in
            guard let self = self else { return }
            switch self.mode {
            case .click:
                if let pt = currentPoints.first?.point {
                    self.onClickCaptured?(pt)
                }
            case .drag:
                if currentPoints.count >= 2 {
                    self.onDragCaptured?(currentPoints[0].point, currentPoints[1].point)
                }
            case .sequence:
                self.onSequenceRealTime?(currentPoints)
            case .windowTransform:
                break
            }
        }, onPointsRealtime: { [weak self] currentPoints in
            guard let self = self else { return }
            switch self.mode {
            case .click:
                if let pt = currentPoints.first?.point {
                    self.onClickRealTime?(pt)
                }
            case .drag:
                if currentPoints.count >= 2 {
                    self.onDragRealTime?(currentPoints[0].point, currentPoints[1].point)
                }
            case .sequence:
                self.onSequenceRealTime?(currentPoints)
            case .windowTransform:
                break
            }
        })
        
        contentView.onWindowTransformCaptured = self.onWindowTransformCaptured
        self.contentView = contentView
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// ==========================================
// MARK: - Action Card View (macOS System Settings Card Style)
// ==========================================
