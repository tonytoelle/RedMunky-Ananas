import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import PDFKit
import ImageIO

// ==========================================
// MARK: - Image Export Formats & Conversion Manager
// ==========================================

enum ImageExportFormat: String, CaseIterable, Identifiable {
    case jpg = "JPG"
    case png = "PNG"
    case webp = "WebP"
    case original = "Original"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .jpg: return "jpg"
        case .png: return "png"
        case .webp: return "webp"
        case .original: return ""
        }
    }
}

class ImageExportManager {
    static func convertAndSave(
        sourceURL: URL,
        format: ImageExportFormat,
        destinationDirectory: URL,
        quality: CGFloat = 0.92
    ) -> URL? {
        let fileManager = FileManager.default
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        
        if format == .original {
            var destURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            destURL = uniqueURL(for: destURL)
            do {
                try fileManager.copyItem(at: sourceURL, to: destURL)
                return destURL
            } catch {
                return nil
            }
        }
        
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            // Fallback via NSImage
            if let nsImage = NSImage(contentsOf: sourceURL),
               let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let cg = bitmap.cgImage {
                return exportCGImage(cg, format: format, destinationDirectory: destinationDirectory, baseName: baseName, quality: quality)
            }
            return nil
        }
        
        return exportCGImage(cgImage, format: format, destinationDirectory: destinationDirectory, baseName: baseName, quality: quality)
    }
    
    static func exportCGImage(
        _ cgImage: CGImage,
        format: ImageExportFormat,
        destinationDirectory: URL,
        baseName: String,
        quality: CGFloat = 0.92
    ) -> URL? {
        let ext = format.fileExtension
        var destURL = destinationDirectory.appendingPathComponent("\(baseName).\(ext)")
        destURL = uniqueURL(for: destURL)
        
        let uti: CFString
        switch format {
        case .jpg:
            uti = UTType.jpeg.identifier as CFString
        case .png:
            uti = UTType.png.identifier as CFString
        case .webp:
            uti = (UTType(filenameExtension: "webp")?.identifier ?? "org.webmproject.webp") as CFString
        case .original:
            uti = UTType.png.identifier as CFString
        }
        
        if let destination = CGImageDestinationCreateWithURL(destURL as CFURL, uti, 1, nil) {
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                return destURL
            }
        }
        
        // Fallback for JPEG / PNG via NSBitmapImageRep
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        if format == .jpg, let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality]) {
            try? data.write(to: destURL)
            return destURL
        } else if format == .png, let data = bitmapRep.representation(using: .png, properties: [:]) {
            try? data.write(to: destURL)
            return destURL
        }
        return nil
    }
    
    private static func uniqueURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return url }
        
        let dir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        
        var counter = 1
        while true {
            let newName = "\(name) (\(counter))"
            let newURL = ext.isEmpty ? dir.appendingPathComponent(newName) : dir.appendingPathComponent(newName).appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: newURL.path) {
                return newURL
            }
            counter += 1
        }
    }
}

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
    
    // Export / Save to Folder State
    @State private var isShowingSaveSheet = false
    @State private var exportFormat: ImageExportFormat = .jpg
    @State private var exportFolderURL: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
    @State private var exportTargetPaths: [String] = []
    @State private var isSaving = false
    
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
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
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
                            
                            Spacer()
                                .allowsHitTesting(false)
                            
                            // Expand / Compact Toggle Icon Button
                            if !manager.heldItems.isEmpty {
                                Button {
                                    toggleExpand()
                                } label: {
                                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                        .frame(width: 26, height: 26)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help(isExpanded ? "Compact View" : "Expand View")
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
                                    
                                    Button("Save All to Folder...") {
                                        openSaveDialog()
                                    }
                                    
                                    if !selectedPaths.isEmpty {
                                        Button("Save Selected (\(selectedPaths.count)) to Folder...") {
                                            openSaveDialog(for: Array(selectedPaths))
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Button(isExpanded ? "Compact View (200x240)" : "Expand View (4x4 Grid)") {
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
                            // Freeform Desktop Canvas with Native macOS ProMotion Scrolling
                            ScrollView(.vertical, showsIndicators: false) {
                                let itemsMaxY = manager.heldItems.map { (itemPositions[$0]?.y ?? currentPosition(for: $0, in: CGSize(width: 200, height: outerGeo.size.height)).y) }.max() ?? 0
                                let canvasHeight = max(outerGeo.size.height - 40, itemsMaxY + 55)
                                
                                ZStack(alignment: .topLeading) {
                                    // Background Canvas Area for Marquee Drag & Tap Deselect
                                    Color.clear
                                        .frame(width: outerGeo.size.width, height: canvasHeight)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
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
                                        let dragOffset = activeDragOffsets[itemPath] ?? .zero
                                        
                                        DraggableCardContainer(
                                            itemPath: itemPath,
                                            getFilePaths: {
                                                if selectedPaths.contains(itemPath) && !selectedPaths.isEmpty {
                                                    return Array(selectedPaths)
                                                } else {
                                                    return [itemPath]
                                                }
                                            },
                                            onClick: {
                                                handleItemClick(itemPath)
                                            },
                                            onDoubleClick: {
                                                NSWorkspace.shared.open(itemURL)
                                            },
                                            onMoveDelta: { delta in
                                                let targets = selectedPaths.contains(itemPath) && !selectedPaths.isEmpty ? selectedPaths : [itemPath]
                                                for t in targets {
                                                    let current = activeDragOffsets[t] ?? .zero
                                                    activeDragOffsets[t] = CGSize(width: current.width + delta.width, height: current.height + delta.height)
                                                }
                                            },
                                            onEndMove: {
                                                let targets = selectedPaths.contains(itemPath) && !selectedPaths.isEmpty ? selectedPaths : [itemPath]
                                                for t in targets {
                                                    if let offset = activeDragOffsets[t] {
                                                        let origin = currentPosition(for: t, in: outerGeo.size)
                                                        itemPositions[t] = CGPoint(
                                                            x: max(38, min(outerGeo.size.width - 38, origin.x + offset.width)),
                                                            y: max(38, origin.y + offset.height)
                                                        )
                                                        activeDragOffsets.removeValue(forKey: t)
                                                    }
                                                }
                                            }
                                        ) {
                                            VStack(spacing: 6) {
                                                AsyncFileThumbnailView(path: itemPath, size: manager.heldItems.count == 1 ? 64 : 46)
                                                
                                                Text(itemURL.lastPathComponent)
                                                    .font(.system(size: 9.5, weight: .medium))
                                                    .foregroundColor(.white)
                                                    .multilineTextAlignment(.center)
                                                    .lineLimit(2)
                                                    .truncationMode(.middle)
                                                    .frame(width: 66, height: 26, alignment: .top)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1.5)
                                                    .background(
                                                        isSelected ?
                                                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor) :
                                                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.clear)
                                                    )
                                            }
                                            .padding(3)
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
                                        .position(x: pos.x + dragOffset.width, y: pos.y + dragOffset.height)
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
                                .frame(width: outerGeo.size.width, height: canvasHeight)
                                .coordinateSpace(name: "DropShelfCanvasSpace")
                                .onPreferenceChange(ItemFramePreference.self) { frames in
                                    self.itemFrames = frames
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onDrop(of: [.fileURL, .url, .image, .png, .jpeg, .tiff, .gif, .plainText, .utf8PlainText], isTargeted: $isTargeted) { providers in
                        var loadedPaths: [String] = []
                        let group = DispatchGroup()
                        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                            .appendingPathComponent("ShortKing/DropShelf", isDirectory: true)
                        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                        
                        for provider in providers {
                            group.enter()
                            
                            // 1. Check local file URL first
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
                            }
                            // 2. Check raw image data / Safari dragged image
                            else if provider.hasItemConformingToTypeIdentifier("public.png") ||
                                      provider.hasItemConformingToTypeIdentifier("public.jpeg") ||
                                      provider.hasItemConformingToTypeIdentifier("public.tiff") ||
                                      provider.hasItemConformingToTypeIdentifier("public.image") {
                                
                                let matchedType = provider.registeredTypeIdentifiers.first {
                                    $0 == "public.png" || $0 == "public.jpeg" || $0 == "public.tiff" || $0 == "public.image"
                                } ?? "public.image"
                                
                                _ = provider.loadDataRepresentation(forTypeIdentifier: matchedType) { data, _ in
                                    if let data = data, let nsImage = NSImage(data: data) {
                                        let formatter = DateFormatter()
                                        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
                                        let timestamp = formatter.string(from: Date())
                                        let isJpg = (matchedType == "public.jpeg")
                                        let ext = isJpg ? "jpg" : "png"
                                        let fileURL = cacheDir.appendingPathComponent("Safari_Image_\(timestamp).\(ext)")
                                        
                                        if let tiff = nsImage.tiffRepresentation,
                                           let bitmap = NSBitmapImageRep(data: tiff) {
                                            let outData = isJpg ?
                                                bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) :
                                                bitmap.representation(using: .png, properties: [:])
                                            try? (outData ?? data).write(to: fileURL)
                                            loadedPaths.append(fileURL.path)
                                        } else {
                                            try? data.write(to: fileURL)
                                            loadedPaths.append(fileURL.path)
                                        }
                                    } else if provider.canLoadObject(ofClass: NSImage.self) {
                                        _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                                            if let nsImg = obj as? NSImage,
                                               let tiff = nsImg.tiffRepresentation,
                                               let bitmap = NSBitmapImageRep(data: tiff),
                                               let pngData = bitmap.representation(using: .png, properties: [:]) {
                                                let formatter = DateFormatter()
                                                formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
                                                let timestamp = formatter.string(from: Date())
                                                let fileURL = cacheDir.appendingPathComponent("Safari_Image_\(timestamp).png")
                                                try? pngData.write(to: fileURL)
                                                loadedPaths.append(fileURL.path)
                                            }
                                        }
                                    }
                                    group.leave()
                                }
                            }
                            // 3. Check web URL / public.url (HTTP/HTTPS image from web)
                            else if provider.hasItemConformingToTypeIdentifier("public.url") {
                                _ = provider.loadItem(forTypeIdentifier: "public.url", options: nil) { (item, _) in
                                    if let url = item as? URL {
                                        if url.isFileURL {
                                            loadedPaths.append(url.path)
                                            group.leave()
                                        } else {
                                            DispatchQueue.global(qos: .userInitiated).async {
                                                if let data = try? Data(contentsOf: url), let _ = NSImage(data: data) {
                                                    let formatter = DateFormatter()
                                                    formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
                                                    let timestamp = formatter.string(from: Date())
                                                    let name = url.deletingPathExtension().lastPathComponent.isEmpty ? "Web_Image" : url.deletingPathExtension().lastPathComponent
                                                    let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
                                                    let fileURL = cacheDir.appendingPathComponent("\(name)_\(timestamp).\(ext)")
                                                    try? data.write(to: fileURL)
                                                    loadedPaths.append(fileURL.path)
                                                }
                                                group.leave()
                                            }
                                        }
                                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                        if url.isFileURL {
                                            loadedPaths.append(url.path)
                                        }
                                        group.leave()
                                    } else {
                                        group.leave()
                                    }
                                }
                            }
                            // 4. Plain text / file path string
                            else {
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
                    
                    // Bottom Status Info (Centered at bottom)
                    if !manager.heldItems.isEmpty {
                        HStack {
                            Spacer()
                            Text(selectedPaths.count == manager.heldItems.count ? "\(manager.heldItems.count) items (all selected)" : "\(selectedPaths.count) of \(manager.heldItems.count) selected")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.bottom, 8)
                                .padding(.top, 2)
                            Spacer()
                        }
                    } else {
                        Spacer()
                            .frame(height: 6)
                    }
                }
                
                // Save to Folder Modal Sheet Overlay
                if isShowingSaveSheet {
                    Color.black.opacity(0.5)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .onTapGesture {
                            if !isSaving {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    isShowingSaveSheet = false
                                }
                            }
                        }
                    
                    SaveToFolderModalView(
                        targetPaths: exportTargetPaths,
                        selectedFormat: $exportFormat,
                        selectedFolderURL: $exportFolderURL,
                        isSaving: $isSaving,
                        onCancel: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isShowingSaveSheet = false
                            }
                        },
                        onSave: {
                            executeSave()
                        }
                    )
                    .frame(width: min(290, outerGeo.size.width - 16))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 264, maxHeight: .infinity)
    }
    
    private func currentPosition(for path: String, in size: CGSize = CGSize(width: 200, height: 264)) -> CGPoint {
        if let pos = itemPositions[path] {
            return pos
        }
        guard let idx = manager.heldItems.firstIndex(of: path) else {
            return CGPoint(x: 56, y: 58)
        }
        
        let spacingX: CGFloat = 88
        let spacingY: CGFloat = 96
        let cols = max(2, Int((size.width - 16) / spacingX))
        let col = idx % cols
        let row = idx / cols
        let startX: CGFloat = 56
        let startY: CGFloat = 58
        return CGPoint(x: startX + CGFloat(col) * spacingX, y: startY + CGFloat(row) * spacingY)
    }
    
    private func realignToGrid(canvasWidth: CGFloat) {
        let spacingX: CGFloat = 88
        let spacingY: CGFloat = 96
        let cols = max(2, Int((canvasWidth - 16) / spacingX))
        for (idx, path) in manager.heldItems.enumerated() {
            let col = idx % cols
            let row = idx / cols
            let startX: CGFloat = 56
            let startY: CGFloat = 58
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
            manager.expandWindow(width: 376, height: 460)
        } else {
            manager.expandWindow(width: 200, height: 264)
        }
    }
    
    private func activeTargetPaths() -> [String] {
        if !selectedPaths.isEmpty {
            return Array(selectedPaths)
        }
        return manager.heldItems
    }
    
    private func openSaveDialog(for paths: [String]? = nil) {
        let targets = paths ?? activeTargetPaths()
        self.exportTargetPaths = targets.isEmpty ? manager.heldItems : targets
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            self.isShowingSaveSheet = true
        }
    }
    
    private func executeSave() {
        guard !isSaving else { return }
        isSaving = true
        let destination = exportFolderURL
        let format = exportFormat
        let paths = exportTargetPaths
        
        DispatchQueue.global(qos: .userInitiated).async {
            var savedURLs: [URL] = []
            for path in paths {
                let srcURL = URL(fileURLWithPath: path)
                if let saved = ImageExportManager.convertAndSave(
                    sourceURL: srcURL,
                    format: format,
                    destinationDirectory: destination
                ) {
                    savedURLs.append(saved)
                }
            }
            
            DispatchQueue.main.async {
                self.isSaving = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    self.isShowingSaveSheet = false
                }
                if !savedURLs.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(savedURLs)
                }
            }
        }
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
            openSaveDialog(for: paths)
        } label: {
            Label(paths.count > 1 ? "Save \(paths.count) Items to Folder..." : "Save to Folder As...", systemImage: "square.and.arrow.down")
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
// MARK: - Save To Folder Modal View
// ==========================================

struct SaveToFolderModalView: View {
    let targetPaths: [String]
    @Binding var selectedFormat: ImageExportFormat
    @Binding var selectedFolderURL: URL
    @Binding var isSaving: Bool
    var onCancel: () -> Void
    var onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13, weight: .bold))
                Text("Save to Folder")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(targetPaths.count) items")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 2)
            
            // Format Selector
            VStack(alignment: .leading, spacing: 5) {
                Text("SAVE AS FORMAT")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.5)
                
                HStack(spacing: 4) {
                    ForEach(ImageExportFormat.allCases) { fmt in
                        Button {
                            selectedFormat = fmt
                        } label: {
                            Text(fmt.rawValue)
                                .font(.system(size: 10, weight: selectedFormat == fmt ? .bold : .medium))
                                .foregroundColor(selectedFormat == fmt ? .white : .white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4.5)
                                .background(
                                    selectedFormat == fmt ?
                                    Color.accentColor :
                                    Color.white.opacity(0.08)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Destination Folder Selector
            VStack(alignment: .leading, spacing: 5) {
                Text("DESTINATION FOLDER")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.5)
                
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(Color(red: 0.3, green: 0.65, blue: 0.95))
                        .font(.system(size: 13))
                    
                    Text(selectedFolderURL.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button("Browse…") {
                        pickFolder()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
                .padding(7)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            // Buttons
            HStack(spacing: 8) {
                Button("Cancel") {
                    onCancel()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
                .disabled(isSaving)
                
                Button {
                    onSave()
                } label: {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        Text(isSaving ? "Saving..." : "Save")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .padding(.top, 2)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.15).opacity(0.97))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 14, x: 0, y: 7)
    }
    
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.directoryURL = selectedFolderURL
        if panel.runModal() == .OK, let selected = panel.url {
            selectedFolderURL = selected
        }
    }
}

// ==========================================
// MARK: - Native AppKit Dragging Source Container
// ==========================================

struct DraggableCardContainer<Content: View>: NSViewRepresentable {
    let itemPath: String
    let getFilePaths: () -> [String]
    var onClick: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var onMoveDelta: ((CGSize) -> Void)? = nil
    var onEndMove: (() -> Void)? = nil
    let content: Content
    
    init(
        itemPath: String,
        getFilePaths: @escaping () -> [String],
        onClick: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onMoveDelta: ((CGSize) -> Void)? = nil,
        onEndMove: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.itemPath = itemPath
        self.getFilePaths = getFilePaths
        self.onClick = onClick
        self.onDoubleClick = onDoubleClick
        self.onMoveDelta = onMoveDelta
        self.onEndMove = onEndMove
        self.content = content()
    }
    
    func makeNSView(context: Context) -> DraggableContainerNSView {
        let view = DraggableContainerNSView()
        view.itemPath = itemPath
        view.getFilePaths = getFilePaths
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onMoveDelta = onMoveDelta
        view.onEndMove = onEndMove
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
        nsView.itemPath = itemPath
        nsView.getFilePaths = getFilePaths
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onMoveDelta = onMoveDelta
        nsView.onEndMove = onEndMove
        if let hosting = nsView.hostingView as? NSHostingView<Content> {
            hosting.rootView = content
        }
    }
}

class DraggableContainerNSView: NSView, NSDraggingSource {
    var itemPath: String = ""
    var getFilePaths: (() -> [String])?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onMoveDelta: ((CGSize) -> Void)?
    var onEndMove: (() -> Void)?
    
    var hostingView: NSView?
    private var dragStartLocation: NSPoint?
    private var lastDragLocation: NSPoint?
    private var hasInitiatedSession = false
    private var isDraggingLocally = false
    private var wasAlreadySelected = false
    private var activeSessionPaths: [String] = []
    
    override var mouseDownCanMoveWindow: Bool {
        return false // Prevents the OS from dragging the window when clicking/dragging the card!
    }
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .move, .generic, .every]
    }
    
    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
        lastDragLocation = event.locationInWindow
        hasInitiatedSession = false
        isDraggingLocally = false
        wasAlreadySelected = false
        
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        
        let isShift = NSEvent.modifierFlags.contains(.shift)
        let isCmd = NSEvent.modifierFlags.contains(.command)
        let currentSelection = getFilePaths?() ?? []
        
        if isShift || isCmd {
            onClick?()
        } else if !currentSelection.contains(itemPath) || currentSelection.count <= 1 {
            onClick?()
        } else {
            // Already part of multi-selection: preserve all selected items during drag!
            wasAlreadySelected = true
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartLocation, !hasInitiatedSession else { return }
        let current = event.locationInWindow
        let totalDist = hypot(current.x - start.x, current.y - start.y)
        guard totalDist > 3 else { return }
        
        guard let window = self.window, let contentView = window.contentView else { return }
        let windowBounds = contentView.bounds
        
        // If mouse is dragged outside window bounds -> Start Finder drag session!
        let isOutside = !windowBounds.insetBy(dx: 4, dy: 4).contains(current)
        
        if isOutside {
            hasInitiatedSession = true
            dragStartLocation = nil
            isDraggingLocally = false
            onEndMove?()
            
            let targets = getFilePaths?() ?? [itemPath]
            guard !targets.isEmpty else { return }
            self.activeSessionPaths = targets
            
            let urls = targets.map { URL(fileURLWithPath: $0) }
            let draggingItems: [NSDraggingItem] = urls.enumerated().map { (index, url) in
                let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                
                let img = NSWorkspace.shared.icon(forFile: url.path)
                img.size = NSSize(width: 48, height: 48)
                let offset = CGFloat(min(index, 4) * 3)
                let dragRect = NSRect(
                    x: (self.bounds.width - 48)/2 + offset,
                    y: (self.bounds.height - 48)/2 - offset,
                    width: 48,
                    height: 48
                )
                draggingItem.setDraggingFrame(dragRect, contents: img)
                return draggingItem
            }
            
            beginDraggingSession(with: draggingItems, event: event, source: self)
        } else {
            // Inside window: move position locally on the canvas!
            isDraggingLocally = true
            let last = lastDragLocation ?? start
            let delta = CGSize(width: current.x - last.x, height: -(current.y - last.y))
            lastDragLocation = current
            onMoveDelta?(delta)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isDraggingLocally {
            onEndMove?()
        } else if wasAlreadySelected && !hasInitiatedSession {
            // Mouse up without drag on an already selected item collapses to single selection
            onClick?()
        }
        
        dragStartLocation = nil
        lastDragLocation = nil
        hasInitiatedSession = false
        isDraggingLocally = false
        wasAlreadySelected = false
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let isInsideWindow = (self.window?.frame.contains(screenPoint) ?? false) || (DropShelfManager.shared.shelfWindow?.frame.contains(screenPoint) ?? false)
        
        if isInsideWindow || operation == [] {
            // User aborted or dragged back into the shelf window -> Keep files in shelf!
            DispatchQueue.main.async {
                self.activeSessionPaths.removeAll()
            }
        } else {
            // Items were successfully dropped into an external Finder window / target outside
            DispatchQueue.main.async {
                for p in self.activeSessionPaths {
                    DropShelfManager.shared.heldItems.removeAll { $0 == p }
                }
                self.activeSessionPaths.removeAll()
                if DropShelfManager.shared.heldItems.isEmpty {
                    DropShelfManager.shared.closeShelf()
                }
            }
        }
    }
}
