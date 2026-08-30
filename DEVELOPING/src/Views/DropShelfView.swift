import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import PDFKit

// ==========================================
// MARK: - QuickLook & Finder Thumbnail Cache
// ==========================================

class FileThumbnailCache {
    static let shared = FileThumbnailCache()
    private var cache = NSCache<NSString, NSImage>()
    
    func thumbnail(for path: String, targetSize: CGSize = CGSize(width: 128, height: 128), completion: @escaping (NSImage) -> Void) {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            var resultImage: NSImage?
            
            // 1. Image formats
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp", "svg", "icns"]
            if imageExtensions.contains(ext) {
                if let img = NSImage(contentsOfFile: path) {
                    resultImage = img
                }
            }
            // 2. Video formats
            else if ["mp4", "mov", "m4v", "mkv", "avi"].contains(ext) {
                let asset = AVAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: targetSize.width * 2, height: targetSize.height * 2)
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    resultImage = NSImage(cgImage: cgImage, size: targetSize)
                }
            }
            // 3. PDF formats
            else if ext == "pdf" {
                if let pdfDoc = PDFDocument(url: url), let page = pdfDoc.page(at: 0) {
                    let pageRect = page.bounds(for: .mediaBox)
                    let img = NSImage(size: pageRect.size)
                    img.lockFocus()
                    if let context = NSGraphicsContext.current?.cgContext {
                        context.setFillColor(NSColor.white.cgColor)
                        context.fill(pageRect)
                        page.draw(with: .mediaBox, to: context)
                    }
                    img.unlockFocus()
                    resultImage = img
                }
            }
            
            // 4. Default / Fallback: Native Finder Icon
            if resultImage == nil {
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = targetSize
                resultImage = icon
            }
            
            let finalImage = resultImage ?? NSWorkspace.shared.icon(forFile: path)
            self?.cache.setObject(finalImage, forKey: key)
            
            DispatchQueue.main.async {
                completion(finalImage)
            }
        }
    }
}

struct AsyncFileThumbnailView: View {
    let path: String
    let size: CGFloat
    @State private var image: NSImage?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size > 50 ? 12 : 9, style: .continuous)
                .fill(Color(white: 0.16).opacity(0.7))
            
            Group {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size > 50 ? 11 : 8, style: .continuous))
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size > 50 ? 12 : 9, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
        .onAppear {
            loadImage()
        }
        .onChange(of: path) { _, _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        FileThumbnailCache.shared.thumbnail(for: path, targetSize: CGSize(width: size * 2, height: size * 2)) { loaded in
            self.image = loaded
        }
    }
}

// PreferenceKey for tracking item frame coordinates for marquee selection
struct ItemFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// ==========================================
// MARK: - Native Window Dragging Top Bar Area
// ==========================================

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        return WindowDragNSView()
    }
    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        self.window?.performDrag(with: event)
    }
}

// ==========================================
// MARK: - Main Drop Shelf View
// ==========================================

struct DropShelfView: View {
    @ObservedObject var manager: DropShelfManager
    @State private var isTargeted = false
    @State private var selectedPaths: Set<String> = []
    @State private var lastClickedPath: String? = nil
    @State private var isExpanded = false
    @State private var plungePulse = false
    
    // Freeform desktop canvas positions & live drag offsets
    @State private var itemPositions: [String: CGPoint] = [:]
    @State private var activeDragOffsets: [String: CGSize] = [:]
    
    // Marquee Selection State
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var marqueeStart: CGPoint? = nil
    @State private var marqueeCurrent: CGPoint? = nil
    @State private var initialSelectionBeforeMarquee: Set<String> = []
    
    private var marqueeRect: CGRect? {
        guard let s = marqueeStart, let c = marqueeCurrent else { return nil }
        let x = min(s.x, c.x)
        let y = min(s.y, c.y)
        let w = abs(s.x - c.x)
        let h = abs(s.y - c.y)
        guard w > 2 || h > 2 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    var body: some View {
        GeometryReader { outerGeo in
            ZStack {
                // Native macOS Glass Background
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.88))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isTargeted ? Color.accentColor : Color.white.opacity(0.15), lineWidth: isTargeted ? 1.5 : 0.5)
                    )
                    .animation(.easeInOut(duration: 0.2), value: isTargeted)
                
                VStack(spacing: 0) {
                    // Header Area (Draggable Window Area)
                    ZStack {
                        WindowDragArea()
                            .frame(height: 38)
                        
                        HStack(spacing: 6) {
                            // Close Button (X)
                            Button {
                                manager.closeShelf()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(width: 26, height: 26)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            
                            if !manager.heldItems.isEmpty {
                                Text(selectedPaths.count == manager.heldItems.count ? "\(manager.heldItems.count) items (all selected)" : "\(selectedPaths.count) of \(manager.heldItems.count) selected")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.leading, 4)
                            }
                            
                            Spacer()
                            
                            if !manager.heldItems.isEmpty {
                                // AirDrop / Share Button
                                Button {
                                    shareSelectedOrAll()
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                        .frame(width: 26, height: 26)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("AirDrop / Share")
                            }
                            
                            // Options Menu (...)
                            Menu {
                                if !manager.heldItems.isEmpty {
                                    Button("Select All (⌘A)") {
                                        selectedPaths = Set(manager.heldItems)
                                    }
                                    
                                    if !selectedPaths.isEmpty {
                                        Button("Deselect All") {
                                            selectedPaths.removeAll()
                                            lastClickedPath = nil
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Button(isExpanded ? "Compact View (194x204)" : "Expand View (4x4 Grid)") {
                                        toggleExpand()
                                    }
                                    
                                    Button("Clean Up / Align to Grid") {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            realignToGrid(canvasWidth: outerGeo.size.width)
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    if let first = selectedPaths.first ?? manager.heldItems.first {
                                        let url = URL(fileURLWithPath: first)
                                        Button("Open with Default App") {
                                            let targetUrls = activeTargetPaths().map { URL(fileURLWithPath: $0) }
                                            for u in targetUrls { NSWorkspace.shared.open(u) }
                                        }
                                        
                                        Button("Show in Finder") {
                                            let targetUrls = activeTargetPaths().map { URL(fileURLWithPath: $0) }
                                            NSWorkspace.shared.activateFileViewerSelecting(targetUrls)
                                        }
                                        
                                        Button("Quick Look (Space)") {
                                            NSWorkspace.shared.open(url)
                                        }
                                        
                                        Divider()
                                        
                                        Button("Copy to Clipboard (⌘C)") {
                                            let pasteboard = NSPasteboard.general
                                            pasteboard.clearContents()
                                            pasteboard.writeObjects(activeTargetPaths().map { URL(fileURLWithPath: $0) as NSURL })
                                        }
                                        
                                        Button("AirDrop / Share...") {
                                            shareSelectedOrAll()
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Button("Clear Shelf") {
                                        manager.closeShelf()
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(width: 26, height: 26)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                    }
                    .frame(height: 38)
                    
                    // Drop Content Area / Freeform Desktop Canvas with Marquee Selection
                    Group {
                        if manager.heldItems.isEmpty {
                            // Empty State (Waiting for Drop)
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            isTargeted ? Color.accentColor : Color.white.opacity(0.25),
                                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                                        )
                                        .frame(width: 140, height: 110)
                                        .background(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    
                                    VStack(spacing: 6) {
                                        Image(systemName: isTargeted ? "arrow.down.circle.fill" : "plus.rectangle.on.folder")
                                            .font(.system(size: 30, weight: .light))
                                            .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.6))
                                            .scaleEffect(isTargeted ? 1.2 : 1.0)
                                        
                                        Text(isTargeted ? "Drop to Hold" : "Drop files here")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.6))
                                    }
                                }
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // Freeform Desktop Canvas: Move items freely anywhere!
                            ZStack(alignment: .topLeading) {
                                // Background Canvas Area for Marquee Drag & Tap Deselect
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // Tap outside icons deselects all items
                                        selectedPaths.removeAll()
                                        lastClickedPath = nil
                                    }
                                    .gesture(
                                        DragGesture(minimumDistance: 4, coordinateSpace: .named("DropShelfCanvasSpace"))
                                            .onChanged { value in
                                                if marqueeStart == nil {
                                                    marqueeStart = value.startLocation
                                                    if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                                                        initialSelectionBeforeMarquee = selectedPaths
                                                    } else {
                                                        initialSelectionBeforeMarquee = []
                                                        selectedPaths.removeAll()
                                                    }
                                                }
                                                marqueeCurrent = value.location
                                                
                                                if let rect = marqueeRect {
                                                    var newlySelected = initialSelectionBeforeMarquee
                                                    for (path, frame) in itemFrames {
                                                        if rect.intersects(frame) {
                                                            newlySelected.insert(path)
                                                        }
                                                    }
                                                    selectedPaths = newlySelected
                                                }
                                            }
                                            .onEnded { _ in
                                                marqueeStart = nil
                                                marqueeCurrent = nil
                                                initialSelectionBeforeMarquee.removeAll()
                                            }
                                    )
                                
                                // Freeform Icons on Canvas
                                ForEach(manager.heldItems, id: \.self) { itemPath in
                                    let itemURL = URL(fileURLWithPath: itemPath)
                                    let isSelected = selectedPaths.contains(itemPath)
                                    let pos = currentPosition(for: itemPath, in: outerGeo.size)
                                    let dragPayload = selectedPaths.contains(itemPath) && !selectedPaths.isEmpty ? Array(selectedPaths) : [itemPath]
                                    
                                    DraggableCardContainer(
                                        filePaths: dragPayload,
                                        onClick: {
                                            handleItemClick(itemPath)
                                        },
                                        onDoubleClick: {
                                            NSWorkspace.shared.open(itemURL)
                                        }
                                    ) {
                                        VStack(spacing: 4) {
                                            AsyncFileThumbnailView(path: itemPath, size: manager.heldItems.count == 1 ? 64 : 46)
                                            
                                            Text(itemURL.lastPathComponent)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                                .truncationMode(.middle)
                                                .frame(width: 72, height: 26, alignment: .top)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(
                                                    isSelected ?
                                                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor) :
                                                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.clear)
                                                )
                                        }
                                        .padding(4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                        .background(
                                            GeometryReader { geo in
                                                Color.clear.preference(
                                                    key: ItemFramePreference.self,
                                                    value: [itemPath: geo.frame(in: .named("DropShelfCanvasSpace"))]
                                                )
                                            }
                                        )
                                        .contextMenu {
                                            fileContextMenu(for: selectedPaths.contains(itemPath) ? Array(selectedPaths) : [itemPath])
                                        }
                                    }
                                    .position(x: pos.x, y: pos.y)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.4).combined(with: .opacity).combined(with: .offset(y: -20)),
                                        removal: .opacity
                                    ))
                                }
                                
                                // Visual Finder-style Marquee Box Overlay
                                if let rect = marqueeRect {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.18))
                                        .overlay(
                                            Rectangle()
                                                .stroke(Color.accentColor.opacity(0.75), lineWidth: 1)
                                        )
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                        .allowsHitTesting(false)
                                }
                            }
                            .coordinateSpace(name: "DropShelfCanvasSpace")
                            .onPreferenceChange(ItemFramePreference.self) { frames in
                                self.itemFrames = frames
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isTargeted) { providers in
                        var loadedPaths: [String] = []
                        let group = DispatchGroup()
                        
                        for provider in providers {
                            group.enter()
                            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                                _ = provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, _) in
                                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                        loadedPaths.append(url.path)
                                    } else if let url = item as? URL {
                                        loadedPaths.append(url.path)
                                    } else if let str = item as? String, let url = URL(string: str) {
                                        loadedPaths.append(url.path)
                                    }
                                    group.leave()
                                }
                            } else {
                                _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                                    if let str = string as? String {
                                        let lines = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                                        for line in lines {
                                            if line.hasPrefix("file://"), let u = URL(string: line) {
                                                loadedPaths.append(u.path)
                                            } else if FileManager.default.fileExists(atPath: line) {
                                                loadedPaths.append(line)
                                            }
                                        }
                                    }
                                    group.leave()
                                }
                            }
                        }
                        
                        group.notify(queue: .main) {
                            guard !loadedPaths.isEmpty else { return }
                            var current = manager.heldItems
                            for p in loadedPaths {
                                if !current.contains(p) {
                                    current.append(p)
                                }
                            }
                            
                            // Trigger "Nyemplung" Plunge Bounce Animation & DEFAULT SELECT ALL!
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.58, blendDuration: 0.2)) {
                                manager.heldItems = current
                                selectedPaths = Set(current) // Default: Select All so user can immediately drag to Finder!
                                plungePulse = true
                            }
                            
                            // Auto expand to 4x4 if more than 4 items dropped
                            if current.count > 4 && !isExpanded {
                                toggleExpand()
                            }
                        }
                        return true
                    }
                    
                    // Bottom Compact / See More Pill (Only if more than 4 items)
                    if manager.heldItems.count > 4 {
                        Button {
                            toggleExpand()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 8, weight: .bold))
                                Text(isExpanded ? "Compact" : "See More")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 6)
                    } else {
                        Spacer()
                            .frame(height: 4)
                    }
                }
            }
        }
        .frame(minWidth: 194, maxWidth: .infinity, minHeight: 204, maxHeight: .infinity)
    }
    
    private func currentPosition(for path: String, in size: CGSize = CGSize(width: 194, height: 204)) -> CGPoint {
        if let pos = itemPositions[path] {
            return pos
        }
        guard let idx = manager.heldItems.firstIndex(of: path) else {
            return CGPoint(x: 50, y: 50)
        }
        
        let cols = max(2, Int((size.width - 20) / 80))
        let col = idx % cols
        let row = idx / cols
        let startX: CGFloat = 50
        let startY: CGFloat = 50
        let spacingX: CGFloat = 80
        let spacingY: CGFloat = 85
        return CGPoint(x: startX + CGFloat(col) * spacingX, y: startY + CGFloat(row) * spacingY)
    }
    
    private func realignToGrid(canvasWidth: CGFloat) {
        let cols = max(2, Int((canvasWidth - 20) / 80))
        for (idx, path) in manager.heldItems.enumerated() {
            let col = idx % cols
            let row = idx / cols
            let startX: CGFloat = 50
            let startY: CGFloat = 50
            let spacingX: CGFloat = 80
            let spacingY: CGFloat = 85
            itemPositions[path] = CGPoint(x: startX + CGFloat(col) * spacingX, y: startY + CGFloat(row) * spacingY)
        }
    }
    
    private func handleItemClick(_ itemPath: String) {
        let isShift = NSEvent.modifierFlags.contains(.shift)
        let isCmd = NSEvent.modifierFlags.contains(.command)
        
        if isShift, let last = lastClickedPath, let lastIdx = manager.heldItems.firstIndex(of: last), let currentIdx = manager.heldItems.firstIndex(of: itemPath) {
            let lower = min(lastIdx, currentIdx)
            let upper = max(lastIdx, currentIdx)
            let rangeItems = manager.heldItems[lower...upper]
            selectedPaths.formUnion(rangeItems)
        } else if isCmd {
            if selectedPaths.contains(itemPath) {
                selectedPaths.remove(itemPath)
            } else {
                selectedPaths.insert(itemPath)
            }
            lastClickedPath = itemPath
        } else {
            if selectedPaths.contains(itemPath) && selectedPaths.count == 1 {
                selectedPaths.removeAll()
                lastClickedPath = nil
            } else {
                selectedPaths = [itemPath]
                lastClickedPath = itemPath
            }
        }
    }
    
    private func toggleExpand() {
        isExpanded.toggle()
        if isExpanded {
            manager.expandWindow(width: 380, height: 390)
        } else {
            manager.expandWindow(width: 194, height: 204)
        }
    }
    
    private func activeTargetPaths() -> [String] {
        if !selectedPaths.isEmpty {
            return Array(selectedPaths)
        }
        return manager.heldItems
    }
    
    private func shareSelectedOrAll() {
        let targets = activeTargetPaths()
        guard !targets.isEmpty else { return }
        let urls = targets.map { URL(fileURLWithPath: $0) }
        
        let picker = NSSharingServicePicker(items: urls)
        if let window = manager.shelfWindow {
            picker.show(relativeTo: NSRect(x: window.frame.width - 60, y: window.frame.height - 30, width: 30, height: 30), of: window.contentView ?? NSView(), preferredEdge: .minY)
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(for paths: [String]) -> some View {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        
        Button {
            for u in urls { NSWorkspace.shared.open(u) }
        } label: {
            Label(paths.count > 1 ? "Open \(paths.count) Items" : "Open", systemImage: "arrow.up.forward.app")
        }
        
        Button {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
        
        if let first = urls.first {
            Button {
                NSWorkspace.shared.open(first)
            } label: {
                Label("Quick Look", systemImage: "eye")
            }
        }
        
        Divider()
        
        Button {
            shareSelectedOrAll()
        } label: {
            Label("AirDrop / Share...", systemImage: "square.and.arrow.up")
        }
        
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        
        Divider()
        
        Button(role: .destructive) {
            for p in paths {
                let fileURL = URL(fileURLWithPath: p)
                try? FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                manager.heldItems.removeAll { $0 == p }
            }
            selectedPaths.removeAll()
            if manager.heldItems.isEmpty {
                manager.closeShelf()
            }
        } label: {
            Label(paths.count > 1 ? "Move \(paths.count) to Trash" : "Move to Trash", systemImage: "trash")
        }
    }
}

// ==========================================
// MARK: - Native AppKit Dragging Source Container
// ==========================================

struct DraggableCardContainer<Content: View>: NSViewRepresentable {
    let filePaths: [String]
    var onClick: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    let content: Content
    
    init(filePaths: [String], onClick: (() -> Void)? = nil, onDoubleClick: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.filePaths = filePaths
        self.onClick = onClick
        self.onDoubleClick = onDoubleClick
        self.content = content()
    }
    
    func makeNSView(context: Context) -> DraggableContainerNSView {
        let view = DraggableContainerNSView()
        view.filePaths = filePaths
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        view.hostingView = hosting
        return view
    }
    
    func updateNSView(_ nsView: DraggableContainerNSView, context: Context) {
        nsView.filePaths = filePaths
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
        if let hosting = nsView.hostingView as? NSHostingView<Content> {
            hosting.rootView = content
        }
    }
}

class DraggableContainerNSView: NSView, NSDraggingSource {
    var filePaths: [String] = []
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var hostingView: NSView?
    private var dragStartLocation: NSPoint?
    private var hasInitiatedDrag = false
    
    override var mouseDownCanMoveWindow: Bool {
        return false // Prevents the OS from dragging the window when clicking/dragging the card!
    }
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .move, .generic, .every]
    }
    
    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
        hasInitiatedDrag = false
        if event.clickCount == 2 {
            onDoubleClick?()
        } else if event.clickCount == 1 {
            onClick?()
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartLocation, !hasInitiatedDrag else { return }
        let current = event.locationInWindow
        let dist = hypot(current.x - start.x, current.y - start.y)
        guard dist > 3 else { return }
        
        hasInitiatedDrag = true
        dragStartLocation = nil
        
        guard !filePaths.isEmpty else { return }
        
        let urls = filePaths.map { URL(fileURLWithPath: $0) }
        let draggingItems: [NSDraggingItem] = urls.map { url in
            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            
            let img = NSWorkspace.shared.icon(forFile: url.path)
            img.size = NSSize(width: 48, height: 48)
            let dragRect = NSRect(x: (self.bounds.width - 48)/2, y: (self.bounds.height - 48)/2, width: 48, height: 48)
            draggingItem.setDraggingFrame(dragRect, contents: img)
            return draggingItem
        }
        
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }
    
    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        hasInitiatedDrag = false
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // If the item was successfully dropped into Finder or another target
        if operation != [] {
            DispatchQueue.main.async {
                for p in self.filePaths {
                    DropShelfManager.shared.heldItems.removeAll { $0 == p }
                }
                if DropShelfManager.shared.heldItems.isEmpty {
                    DropShelfManager.shared.closeShelf()
                }
            }
        }
    }
}
