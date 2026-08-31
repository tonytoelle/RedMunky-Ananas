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
        customFileName: String? = nil,
        quality: CGFloat = 0.92
    ) -> URL? {
        let fileManager = FileManager.default
        let baseName = customFileName ?? sourceURL.deletingPathExtension().lastPathComponent
        
        // 1. Directory / Folder Transit (Move folder structure)
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue {
            let folderName = customFileName ?? sourceURL.lastPathComponent
            var destFolderURL = destinationDirectory.appendingPathComponent(folderName, isDirectory: true)
            destFolderURL = uniqueURL(for: destFolderURL)
            
            // If original format, try direct folder move
            if format == .original && customFileName == nil {
                do {
                    try fileManager.moveItem(at: sourceURL, to: destFolderURL)
                    return destFolderURL
                } catch {
                    // Fallback to recursive copy & remove below
                }
            }
            
            do {
                try fileManager.createDirectory(at: destFolderURL, withIntermediateDirectories: true)
                if let childURLs = try? fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for child in childURLs {
                        _ = convertAndSave(
                            sourceURL: child,
                            format: format,
                            destinationDirectory: destFolderURL,
                            quality: quality
                        )
                    }
                }
                // Clean up original source directory after moving all contents
                try? fileManager.removeItem(at: sourceURL)
                return destFolderURL
            } catch {
                return nil
            }
        }
        
        // 2. Original format file move
        if format == .original {
            let originalName = (customFileName != nil && !sourceURL.pathExtension.isEmpty) ? "\(baseName).\(sourceURL.pathExtension)" : (customFileName ?? sourceURL.lastPathComponent)
            var destURL = destinationDirectory.appendingPathComponent(originalName)
            destURL = uniqueURL(for: destURL)
            
            if sourceURL == destURL { return destURL }
            do {
                try fileManager.moveItem(at: sourceURL, to: destURL)
                return destURL
            } catch {
                // Across volumes fallback: copy + remove original
                if (try? fileManager.copyItem(at: sourceURL, to: destURL)) != nil {
                    try? fileManager.removeItem(at: sourceURL)
                    return destURL
                }
                return nil
            }
        }
        
        // 3. Image conversion format export & remove source original
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            // Fallback via NSImage
            if let nsImage = NSImage(contentsOf: sourceURL),
               let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let cg = bitmap.cgImage {
                if let exported = exportCGImage(cg, format: format, destinationDirectory: destinationDirectory, baseName: baseName, quality: quality) {
                    if sourceURL.path != exported.path {
                        try? fileManager.removeItem(at: sourceURL)
                    }
                    return exported
                }
            }
            
            // Fallback for non-image files: move original file
            let originalName = (customFileName != nil && !sourceURL.pathExtension.isEmpty) ? "\(baseName).\(sourceURL.pathExtension)" : (customFileName ?? sourceURL.lastPathComponent)
            var destURL = destinationDirectory.appendingPathComponent(originalName)
            destURL = uniqueURL(for: destURL)
            if sourceURL == destURL { return destURL }
            do {
                try fileManager.moveItem(at: sourceURL, to: destURL)
                return destURL
            } catch {
                if (try? fileManager.copyItem(at: sourceURL, to: destURL)) != nil {
                    try? fileManager.removeItem(at: sourceURL)
                    return destURL
                }
                return nil
            }
        }
        
        if let exported = exportCGImage(cgImage, format: format, destinationDirectory: destinationDirectory, baseName: baseName, quality: quality) {
            if sourceURL.path != exported.path {
                try? fileManager.removeItem(at: sourceURL)
            }
            return exported
        }
        return nil
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
// MARK: - Native macOS Save & Open Dialog with Format Accessory
// ==========================================

class DropShelfNativeSaveDialog: NSObject {
    static let shared = DropShelfNativeSaveDialog()
    
    private var currentPanel: NSSavePanel?
    
    func showSaveDialog(for paths: [String]) {
        guard !paths.isEmpty else { return }
        
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            
            if paths.count == 1, let singlePath = paths.first {
                let sourceURL = URL(fileURLWithPath: singlePath)
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.showsTagField = true
                panel.prompt = "Save"
                panel.title = "Save Image"
                panel.level = .floating
                
                let baseName = sourceURL.deletingPathExtension().lastPathComponent
                panel.nameFieldStringValue = "\(baseName).jpg"
                
                // Native macOS Format Accessory View
                let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 36))
                
                let label = NSTextField(labelWithString: "Format:")
                label.frame = NSRect(x: 10, y: 8, width: 60, height: 20)
                label.alignment = .right
                label.font = NSFont.systemFont(ofSize: 13)
                
                let popUp = NSPopUpButton(frame: NSRect(x: 75, y: 5, width: 140, height: 26), pullsDown: false)
                popUp.addItems(withTitles: ["JPEG", "PNG", "WebP", "Original"])
                popUp.selectItem(withTitle: "JPEG")
                
                popUp.target = self
                popUp.action = #selector(self.singleFormatChanged(_:))
                
                accessoryView.addSubview(label)
                accessoryView.addSubview(popUp)
                panel.accessoryView = accessoryView
                
                self.currentPanel = panel
                
                let response = panel.runModal()
                
                if response == .OK, let targetURL = panel.url {
                    let selectedTitle = popUp.titleOfSelectedItem ?? "JPEG"
                    let fmt: ImageExportFormat
                    switch selectedTitle {
                    case "PNG": fmt = .png
                    case "WebP": fmt = .webp
                    case "Original": fmt = .original
                    default: fmt = .jpg
                    }
                    
                    let destDir = targetURL.deletingLastPathComponent()
                    let customName = targetURL.deletingPathExtension().lastPathComponent
                    DispatchQueue.global(qos: .userInitiated).async {
                        if let saved = ImageExportManager.convertAndSave(
                            sourceURL: sourceURL,
                            format: fmt,
                            destinationDirectory: destDir,
                            customFileName: customName
                        ) {
                            // Clean up temporary cache file if applicable
                            if sourceURL.path.contains("ShortKing/DropShelf") && sourceURL.path != saved.path {
                                try? FileManager.default.removeItem(at: sourceURL)
                            }
                            DispatchQueue.main.async {
                                DropShelfManager.shared.heldItems.removeAll { $0 == sourceURL.path }
                                if DropShelfManager.shared.heldItems.isEmpty {
                                    DropShelfManager.shared.closeShelf()
                                }
                                NSWorkspace.shared.activateFileViewerSelecting([saved])
                            }
                        }
                    }
                }
            } else {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = true
                panel.prompt = "Save"
                panel.title = "Save \(paths.count) Items"
                panel.message = "Choose destination folder to save \(paths.count) items"
                panel.level = .floating
                
                let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 36))
                let label = NSTextField(labelWithString: "Format:")
                label.frame = NSRect(x: 10, y: 8, width: 60, height: 20)
                label.alignment = .right
                label.font = NSFont.systemFont(ofSize: 13)
                
                let popUp = NSPopUpButton(frame: NSRect(x: 75, y: 5, width: 150, height: 26), pullsDown: false)
                popUp.addItems(withTitles: ["JPEG", "PNG", "WebP", "Original"])
                popUp.selectItem(withTitle: "JPEG")
                
                accessoryView.addSubview(label)
                accessoryView.addSubview(popUp)
                panel.accessoryView = accessoryView
                
                let response = panel.runModal()
                
                if response == .OK, let destDir = panel.url {
                    let selectedTitle = popUp.titleOfSelectedItem ?? "JPEG"
                    let fmt: ImageExportFormat
                    switch selectedTitle {
                    case "PNG": fmt = .png
                    case "WebP": fmt = .webp
                    case "Original": fmt = .original
                    default: fmt = .jpg
                    }
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        var savedURLs: [URL] = []
                        for p in paths {
                            let srcURL = URL(fileURLWithPath: p)
                            if let saved = ImageExportManager.convertAndSave(
                                sourceURL: srcURL,
                                format: fmt,
                                destinationDirectory: destDir
                            ) {
                                savedURLs.append(saved)
                                // Clean up temporary cache file if applicable
                                if srcURL.path.contains("ShortKing/DropShelf") && srcURL.path != saved.path {
                                    try? FileManager.default.removeItem(at: srcURL)
                                }
                            }
                        }
                        if !savedURLs.isEmpty {
                            DispatchQueue.main.async {
                                for p in paths {
                                    DropShelfManager.shared.heldItems.removeAll { $0 == p }
                                }
                                if DropShelfManager.shared.heldItems.isEmpty {
                                    DropShelfManager.shared.closeShelf()
                                }
                                NSWorkspace.shared.activateFileViewerSelecting(savedURLs)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @objc private func singleFormatChanged(_ sender: NSPopUpButton) {
        guard let panel = currentPanel else { return }
        let title = sender.titleOfSelectedItem ?? "JPEG"
        let ext: String
        switch title {
        case "PNG": ext = "png"
        case "WebP": ext = "webp"
        case "Original": ext = ""
        default: ext = "jpg"
        }
        
        let currentName = panel.nameFieldStringValue
        let baseName = URL(fileURLWithPath: currentName).deletingPathExtension().lastPathComponent
        if ext.isEmpty {
            panel.nameFieldStringValue = baseName
        } else {
            panel.nameFieldStringValue = "\(baseName).\(ext)"
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
    
    // Directory / Folder Navigation inside DropShelf
    @State private var currentDirectory: URL? = nil
    @State private var folderHistory: [URL] = []
    
    // Inline Renaming State
    @State private var renamingPath: String? = nil
    @State private var renamingText: String = ""
    
    // Live Drag-over Folder Target State
    @State private var hoveredFolder: String? = nil
    @State private var directoryChangeToken = UUID()
    
    // Freeform desktop canvas positions & live drag offsets
    @State private var itemPositions: [String: CGPoint] = [:]
    @State private var activeDragOffsets: [String: CGSize] = [:]
    
    // Marquee Selection State
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var marqueeStart: CGPoint? = nil
    @State private var marqueeCurrent: CGPoint? = nil
    @State private var initialSelectionBeforeMarquee: Set<String> = []
    
    // Keyboard Event Monitor
    @State private var keyMonitor: Any? = nil
    
    private var displayedItems: [String] {
        _ = directoryChangeToken
        if let dir = currentDirectory {
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            return items.map { $0.path }
        }
        return manager.heldItems
    }
    
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
                                if currentDirectory != nil {
                                    navigateUp()
                                } else {
                                    manager.closeShelf()
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(width: 26, height: 26)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(currentDirectory != nil ? "Close Folder / Shelf" : "Close Shelf")
                            
                            // Up Arrow Button (Back to Parent Folder) - same style & color as X
                            if currentDirectory != nil {
                                Button {
                                    navigateUp()
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                        .frame(width: 26, height: 26)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Back to Parent Folder")
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            // Current Folder Title (no icon, no capsule background)
                            if let dir = currentDirectory {
                                Text(dir.lastPathComponent)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.leading, 2)
                            }
                            
                            Spacer()
                                .allowsHitTesting(false)
                            
                            // Expand / Compact Toggle Icon Button
                            if !displayedItems.isEmpty {
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
                                Button {
                                    createNewFolder()
                                } label: {
                                    Label("New Folder", systemImage: "folder.badge.plus")
                                }
                                
                                Divider()
                                
                                if !displayedItems.isEmpty {
                                    Button("Select All (⌘A)") {
                                        selectedPaths = Set(displayedItems)
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
                                    
                                    if let first = selectedPaths.first ?? displayedItems.first {
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
                                    
                                    Button(role: .destructive) {
                                        if currentDirectory != nil {
                                            navigateUp()
                                        } else {
                                            manager.closeShelf()
                                        }
                                    } label: {
                                        Text(currentDirectory != nil ? "Back to Parent Folder" : "Clear Shelf")
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
                        if displayedItems.isEmpty {
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
                                        Image(systemName: isTargeted ? "arrow.down.circle.fill" : (currentDirectory != nil ? "folder.badge.plus" : "plus.rectangle.on.folder"))
                                            .font(.system(size: 30, weight: .light))
                                            .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.6))
                                            .scaleEffect(isTargeted ? 1.2 : 1.0)
                                        
                                        Text(isTargeted ? "Drop to Hold" : (currentDirectory != nil ? "Folder is empty" : "Drop files here"))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.6))
                                    }
                                }
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .contextMenu {
                                canvasContextMenu
                            }
                        } else {
                            // Freeform Desktop Canvas with Native macOS ProMotion Scrolling
                            ScrollView(.vertical, showsIndicators: false) {
                                let itemsMaxY = displayedItems.map { (itemPositions[$0]?.y ?? currentPosition(for: $0, in: CGSize(width: 200, height: outerGeo.size.height)).y) }.max() ?? 0
                                let canvasHeight = max(outerGeo.size.height - 40, itemsMaxY + 55)
                                
                                ZStack(alignment: .topLeading) {
                                    // Background Canvas Area for Marquee Drag & Tap Deselect & Right Click Menu
                                    Color.clear
                                        .frame(width: outerGeo.size.width, height: canvasHeight)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedPaths.removeAll()
                                            lastClickedPath = nil
                                        }
                                        .contextMenu {
                                            canvasContextMenu
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
                                    ForEach(displayedItems, id: \.self) { itemPath in
                                        let itemURL = URL(fileURLWithPath: itemPath)
                                        let isSelected = selectedPaths.contains(itemPath)
                                        let pos = currentPosition(for: itemPath, in: outerGeo.size)
                                        let dragOffset = activeDragOffsets[itemPath] ?? .zero
                                        
                                        var isDir: ObjCBool = false
                                        let isDirectory = FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDir) && isDir.boolValue
                                        
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
                                                if isDirectory {
                                                    if let cur = currentDirectory {
                                                        folderHistory.append(cur)
                                                    }
                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                        currentDirectory = itemURL
                                                        selectedPaths.removeAll()
                                                        lastClickedPath = nil
                                                    }
                                                } else {
                                                    NSWorkspace.shared.open(itemURL)
                                                }
                                            },
                                            onMoveDelta: { delta in
                                                let targets = selectedPaths.contains(itemPath) && !selectedPaths.isEmpty ? Array(selectedPaths) : [itemPath]
                                                for t in targets {
                                                    let current = activeDragOffsets[t] ?? .zero
                                                    activeDragOffsets[t] = CGSize(width: current.width + delta.width, height: current.height + delta.height)
                                                }
                                                
                                                // Live calculate if hovering over any folder
                                                let myOrigin = currentPosition(for: itemPath, in: outerGeo.size)
                                                let curOffset = activeDragOffsets[itemPath] ?? .zero
                                                let curPos = CGPoint(x: myOrigin.x + curOffset.width, y: myOrigin.y + curOffset.height)
                                                
                                                var foundHover: String? = nil
                                                for other in displayedItems {
                                                    guard !targets.contains(other) else { continue }
                                                    var isDir: ObjCBool = false
                                                    if FileManager.default.fileExists(atPath: other, isDirectory: &isDir), isDir.boolValue {
                                                        let fPos = currentPosition(for: other, in: outerGeo.size)
                                                        let dist = hypot(curPos.x - fPos.x, curPos.y - fPos.y)
                                                        if dist < 65 {
                                                            foundHover = other
                                                            break
                                                        }
                                                    }
                                                }
                                                if hoveredFolder != foundHover {
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        hoveredFolder = foundHover
                                                    }
                                                }
                                            },
                                            onEndMove: {
                                                let targets = selectedPaths.contains(itemPath) && !selectedPaths.isEmpty ? Array(selectedPaths) : [itemPath]
                                                let destFolder = hoveredFolder
                                                hoveredFolder = nil
                                                
                                                if let folder = destFolder {
                                                    moveItems(targets, intoFolder: folder)
                                                } else {
                                                    // Fallback check distance in case onMoveDelta wasn't triggered at the last frame
                                                    var fallbackFolder: String? = nil
                                                    if let myOffset = activeDragOffsets[itemPath] {
                                                        let myOrigin = currentPosition(for: itemPath, in: outerGeo.size)
                                                        let myFinalPos = CGPoint(
                                                            x: max(38, min(outerGeo.size.width - 38, myOrigin.x + myOffset.width)),
                                                            y: max(38, myOrigin.y + myOffset.height)
                                                        )
                                                        
                                                        for other in displayedItems {
                                                            guard !targets.contains(other) else { continue }
                                                            var isDir: ObjCBool = false
                                                            if FileManager.default.fileExists(atPath: other, isDirectory: &isDir), isDir.boolValue {
                                                                let fPos = currentPosition(for: other, in: outerGeo.size)
                                                                let dist = hypot(myFinalPos.x - fPos.x, myFinalPos.y - fPos.y)
                                                                if dist < 70 {
                                                                    fallbackFolder = other
                                                                    break
                                                                }
                                                            }
                                                        }
                                                    }
                                                    
                                                    if let fb = fallbackFolder {
                                                        moveItems(targets, intoFolder: fb)
                                                    } else {
                                                        for t in targets {
                                                            if let offset = activeDragOffsets[t] {
                                                                let origin = currentPosition(for: t, in: outerGeo.size)
                                                                itemPositions[t] = CGPoint(
                                                                    x: max(38, min(outerGeo.size.width - 38, origin.x + offset.width)),
                                                                    y: max(38, origin.y + offset.height)
                                                                )
                                                            }
                                                        }
                                                    }
                                                }
                                                
                                                for t in targets {
                                                    activeDragOffsets.removeValue(forKey: t)
                                                }
                                            }
                                        ) {
                                            VStack(spacing: 6) {
                                                AsyncFileThumbnailView(path: itemPath, size: displayedItems.count == 1 ? 64 : 46)
                                                    .overlay(
                                                        Group {
                                                            if isDirectory && hoveredFolder == itemPath {
                                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                                    .stroke(Color.accentColor, lineWidth: 3)
                                                                    .shadow(color: Color.accentColor.opacity(0.9), radius: 6)
                                                            }
                                                        }
                                                    )
                                                
                                                if renamingPath == itemPath {
                                                    TextField("Name", text: $renamingText, onCommit: {
                                                        commitRename()
                                                    })
                                                    .textFieldStyle(.plain)
                                                    .font(.system(size: 9.5, weight: .medium))
                                                    .foregroundColor(.white)
                                                    .multilineTextAlignment(.center)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                            .fill(Color.black.opacity(0.75))
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                                    .stroke(Color.accentColor, lineWidth: 1)
                                                            )
                                                    )
                                                    .frame(width: 72)
                                                } else {
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
                                            }
                                            .padding(3)
                                            .scaleEffect((isDirectory && hoveredFolder == itemPath) ? 1.15 : 1.0)
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
                        let cacheDir = currentDirectory ?? defaultDropShelfCacheDir()
                        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                        
                        for provider in providers {
                            group.enter()
                            
                            // 1. Check local file URL first
                            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                                _ = provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, _) in
                                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                        if let dir = currentDirectory {
                                            // Copy into current folder
                                            let destURL = dir.appendingPathComponent(url.lastPathComponent)
                                            try? FileManager.default.copyItem(at: url, to: destURL)
                                            loadedPaths.append(destURL.path)
                                        } else {
                                            loadedPaths.append(url.path)
                                        }
                                    } else if let url = item as? URL {
                                        if let dir = currentDirectory {
                                            let destURL = dir.appendingPathComponent(url.lastPathComponent)
                                            try? FileManager.default.copyItem(at: url, to: destURL)
                                            loadedPaths.append(destURL.path)
                                        } else {
                                            loadedPaths.append(url.path)
                                        }
                                    } else if let str = item as? String, let url = URL(string: str) {
                                        if let dir = currentDirectory {
                                            let destURL = dir.appendingPathComponent(url.lastPathComponent)
                                            try? FileManager.default.copyItem(at: url, to: destURL)
                                            loadedPaths.append(destURL.path)
                                        } else {
                                            loadedPaths.append(url.path)
                                        }
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
                                            if let dir = currentDirectory {
                                                let destURL = dir.appendingPathComponent(url.lastPathComponent)
                                                try? FileManager.default.copyItem(at: url, to: destURL)
                                                loadedPaths.append(destURL.path)
                                            } else {
                                                loadedPaths.append(url.path)
                                            }
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
                                            if let dir = currentDirectory {
                                                let destURL = dir.appendingPathComponent(url.lastPathComponent)
                                                try? FileManager.default.copyItem(at: url, to: destURL)
                                                loadedPaths.append(destURL.path)
                                            } else {
                                                loadedPaths.append(url.path)
                                            }
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
                                                if let dir = currentDirectory {
                                                    let destURL = dir.appendingPathComponent(u.lastPathComponent)
                                                    try? FileManager.default.copyItem(at: u, to: destURL)
                                                    loadedPaths.append(destURL.path)
                                                } else {
                                                    loadedPaths.append(u.path)
                                                }
                                            } else if FileManager.default.fileExists(atPath: line) {
                                                let u = URL(fileURLWithPath: line)
                                                if let dir = currentDirectory {
                                                    let destURL = dir.appendingPathComponent(u.lastPathComponent)
                                                    try? FileManager.default.copyItem(at: u, to: destURL)
                                                    loadedPaths.append(destURL.path)
                                                } else {
                                                    loadedPaths.append(line)
                                                }
                                            }
                                        }
                                    }
                                    group.leave()
                                }
                            }
                        }
                        
                        group.notify(queue: .main) {
                            guard !loadedPaths.isEmpty else { return }
                            if currentDirectory == nil {
                                var current = manager.heldItems
                                for p in loadedPaths {
                                    if !current.contains(p) {
                                        current.append(p)
                                    }
                                }
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.58, blendDuration: 0.2)) {
                                    manager.heldItems = current
                                    selectedPaths = Set(current) // Default: Select All so user can immediately drag to Finder!
                                    plungePulse = true
                                }
                                if current.count > 4 && !isExpanded {
                                    toggleExpand()
                                }
                            } else {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.58, blendDuration: 0.2)) {
                                    selectedPaths = Set(loadedPaths)
                                    plungePulse = true
                                }
                            }
                        }
                        return true
                    }
                    
                    // Bottom Status Info (Centered at bottom)
                    if !displayedItems.isEmpty {
                        HStack {
                            Spacer()
                            Text(selectedPaths.count == displayedItems.count ? "\(displayedItems.count) items (all selected)" : "\(selectedPaths.count) of \(displayedItems.count) selected")
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
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 264, maxHeight: .infinity)
        .onAppear {
            setupKeyMonitor()
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                manager.shelfWindow?.makeKeyAndOrderFront(nil)
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }
    
    private func currentPosition(for path: String, in size: CGSize = CGSize(width: 200, height: 264)) -> CGPoint {
        if let pos = itemPositions[path] {
            return pos
        }
        let items = displayedItems
        guard let idx = items.firstIndex(of: path) else {
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
        for (idx, path) in displayedItems.enumerated() {
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
        let items = displayedItems
        
        if isShift, let last = lastClickedPath, let lastIdx = items.firstIndex(of: last), let currentIdx = items.firstIndex(of: itemPath) {
            let lower = min(lastIdx, currentIdx)
            let upper = max(lastIdx, currentIdx)
            let rangeItems = items[lower...upper]
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
        return displayedItems
    }
    
    // MARK: - Folder & Directory Navigation
    
    private func defaultDropShelfCacheDir() -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ShortKing/DropShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }
    
    private func createNewFolder() {
        let targetDir: URL = currentDirectory ?? defaultDropShelfCacheDir()
        var folderName = "New Folder"
        var targetURL = targetDir.appendingPathComponent(folderName, isDirectory: true)
        var counter = 1
        while FileManager.default.fileExists(atPath: targetURL.path) {
            folderName = "New Folder \(counter)"
            targetURL = targetDir.appendingPathComponent(folderName, isDirectory: true)
            counter += 1
        }
        
        try? FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        
        if currentDirectory == nil {
            if !manager.heldItems.contains(targetURL.path) {
                manager.heldItems.append(targetURL.path)
            }
        }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            selectedPaths = [targetURL.path]
            lastClickedPath = targetURL.path
        }
    }
    
    private func navigateUp() {
        if !folderHistory.isEmpty {
            currentDirectory = folderHistory.removeLast()
        } else {
            currentDirectory = nil
        }
        selectedPaths.removeAll()
        lastClickedPath = nil
    }
    
    // MARK: - Renaming & Moving Items
    
    private func startRenaming(_ path: String) {
        let url = URL(fileURLWithPath: path)
        renamingText = url.lastPathComponent
        renamingPath = path
    }
    
    private func commitRename() {
        guard let oldPath = renamingPath else { return }
        let cleanName = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            renamingPath = nil
            return
        }
        
        let oldURL = URL(fileURLWithPath: oldPath)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(cleanName)
        
        if oldURL.path != newURL.path {
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                if let idx = manager.heldItems.firstIndex(of: oldPath) {
                    manager.heldItems[idx] = newURL.path
                }
                if selectedPaths.contains(oldPath) {
                    selectedPaths.remove(oldPath)
                    selectedPaths.insert(newURL.path)
                }
                if let pos = itemPositions[oldPath] {
                    itemPositions.removeValue(forKey: oldPath)
                    itemPositions[newURL.path] = pos
                }
                directoryChangeToken = UUID()
            } catch {
                // Ignore rename failure
            }
        }
        renamingPath = nil
    }
    
    private func moveItems(_ sourcePaths: [String], intoFolder folderPath: String) {
        let folderURL = URL(fileURLWithPath: folderPath)
        var movedAny = false
        for src in sourcePaths {
            guard src != folderPath else { continue }
            let srcURL = URL(fileURLWithPath: src)
            var destURL = folderURL.appendingPathComponent(srcURL.lastPathComponent)
            
            // Generate unique filename if already exists in destination
            var counter = 1
            let base = srcURL.deletingPathExtension().lastPathComponent
            let ext = srcURL.pathExtension
            while FileManager.default.fileExists(atPath: destURL.path) {
                let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                destURL = folderURL.appendingPathComponent(name)
                counter += 1
            }
            
            do {
                try FileManager.default.moveItem(at: srcURL, to: destURL)
                movedAny = true
                manager.heldItems.removeAll { $0 == src }
                itemPositions.removeValue(forKey: src)
            } catch {
                if (try? FileManager.default.copyItem(at: srcURL, to: destURL)) != nil {
                    try? FileManager.default.removeItem(at: srcURL)
                    movedAny = true
                    manager.heldItems.removeAll { $0 == src }
                    itemPositions.removeValue(forKey: src)
                }
            }
        }
        if movedAny {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                directoryChangeToken = UUID()
                selectedPaths.removeAll()
                lastClickedPath = nil
            }
        }
    }
    
    // MARK: - Keyboard Event Monitoring & Actions
    
    private func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let win = manager.shelfWindow, win.isKeyWindow || NSApp.keyWindow == win else {
                return event
            }
            
            let keyCode = event.keyCode
            let isShift = event.modifierFlags.contains(.shift)
            let isCmd = event.modifierFlags.contains(.command)
            
            // 1. Delete / Backspace (51) or Forward Delete (117)
            if keyCode == 51 || keyCode == 117 {
                deleteSelectedItems()
                return nil
            }
            
            // 2. Cmd + A (Select All)
            if isCmd && (event.charactersIgnoringModifiers?.lowercased() == "a" || keyCode == 0) {
                selectedPaths = Set(displayedItems)
                return nil
            }
            
            // 3. Escape (53)
            if keyCode == 53 {
                if !selectedPaths.isEmpty {
                    selectedPaths.removeAll()
                    lastClickedPath = nil
                } else if currentDirectory != nil {
                    navigateUp()
                } else {
                    manager.closeShelf()
                }
                return nil
            }
            
            // 4. Spacebar (49) -> Quick Look / Open Preview
            if keyCode == 49 {
                if let first = selectedPaths.first ?? displayedItems.first {
                    NSWorkspace.shared.open(URL(fileURLWithPath: first))
                }
                return nil
            }
            
            // 5. Arrow Keys (Left: 123, Right: 124, Down: 125, Up: 126)
            if [123, 124, 125, 126].contains(keyCode) {
                handleArrowKey(keyCode: keyCode, isShift: isShift)
                return nil
            }
            
            return event
        }
    }
    
    private func removeKeyMonitor() {
        if let mon = keyMonitor {
            NSEvent.removeMonitor(mon)
            keyMonitor = nil
        }
    }
    
    private func deleteSelectedItems() {
        let items = displayedItems
        let targets = selectedPaths.isEmpty ? (items.isEmpty ? [] : [items.last!]) : Array(selectedPaths)
        guard !targets.isEmpty else { return }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            for p in targets {
                if currentDirectory != nil {
                    try? FileManager.default.removeItem(atPath: p)
                } else {
                    manager.heldItems.removeAll { $0 == p }
                }
                itemPositions.removeValue(forKey: p)
            }
            selectedPaths.removeAll()
            lastClickedPath = nil
        }
        
        let remaining = displayedItems
        if remaining.isEmpty {
            if currentDirectory == nil {
                manager.closeShelf()
            }
        } else {
            if let nextItem = remaining.last {
                selectedPaths = [nextItem]
                lastClickedPath = nextItem
            }
        }
    }
    
    private func handleArrowKey(keyCode: UInt16, isShift: Bool) {
        let items = displayedItems
        guard !items.isEmpty else { return }
        
        let currentIdx: Int
        if let last = lastClickedPath, let idx = items.firstIndex(of: last) {
            currentIdx = idx
        } else if let firstSelected = selectedPaths.first, let idx = items.firstIndex(of: firstSelected) {
            currentIdx = idx
        } else {
            currentIdx = 0
        }
        
        let width = manager.shelfWindow?.frame.width ?? 200
        let cols = max(2, Int((width - 16) / 88))
        var newIdx = currentIdx
        
        switch keyCode {
        case 123: // Left Arrow
            newIdx = max(0, currentIdx - 1)
        case 124: // Right Arrow
            newIdx = min(items.count - 1, currentIdx + 1)
        case 126: // Up Arrow
            newIdx = max(0, currentIdx - cols)
        case 125: // Down Arrow
            newIdx = min(items.count - 1, currentIdx + cols)
        default:
            break
        }
        
        guard newIdx >= 0 && newIdx < items.count else { return }
        let targetPath = items[newIdx]
        
        if isShift {
            let lower = min(currentIdx, newIdx)
            let upper = max(currentIdx, newIdx)
            for i in lower...upper {
                selectedPaths.insert(items[i])
            }
            lastClickedPath = targetPath
        } else {
            selectedPaths = [targetPath]
            lastClickedPath = targetPath
        }
    }
    
    private func openSaveDialog(for paths: [String]? = nil) {
        let targets = paths ?? activeTargetPaths()
        let finalTargets = targets.isEmpty ? displayedItems : targets
        guard !finalTargets.isEmpty else { return }
        DropShelfNativeSaveDialog.shared.showSaveDialog(for: finalTargets)
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
    
    // MARK: - Canvas & File Context Menus
    
    @ViewBuilder
    private var canvasContextMenu: some View {
        Button {
            createNewFolder()
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        
        Divider()
        
        if !displayedItems.isEmpty {
            Button {
                selectedPaths = Set(displayedItems)
            } label: {
                Label("Select All (⌘A)", systemImage: "checkmark.circle")
            }
            
            if !selectedPaths.isEmpty {
                Button {
                    selectedPaths.removeAll()
                    lastClickedPath = nil
                } label: {
                    Label("Deselect All", systemImage: "xmark.circle")
                }
            }
            
            Divider()
            
            Button {
                openSaveDialog()
            } label: {
                Label("Save All to Folder...", systemImage: "square.and.arrow.down")
            }
            
            if !selectedPaths.isEmpty {
                Button {
                    openSaveDialog(for: Array(selectedPaths))
                } label: {
                    Label("Save Selected (\(selectedPaths.count)) to Folder...", systemImage: "square.and.arrow.down.fill")
                }
            }
            
            Divider()
            
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    realignToGrid(canvasWidth: 200)
                }
            } label: {
                Label("Clean Up / Align to Grid", systemImage: "square.grid.2x2")
            }
            
            Button {
                toggleExpand()
            } label: {
                Label(isExpanded ? "Compact View" : "Expand View", systemImage: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            
            Divider()
            
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects(activeTargetPaths().map { URL(fileURLWithPath: $0) as NSURL })
            } label: {
                Label("Copy to Clipboard (⌘C)", systemImage: "doc.on.doc")
            }
            
            Button {
                shareSelectedOrAll()
            } label: {
                Label("AirDrop / Share...", systemImage: "square.and.arrow.up")
            }
            
            Divider()
            
            Button(role: .destructive) {
                if currentDirectory != nil {
                    navigateUp()
                } else {
                    manager.closeShelf()
                }
            } label: {
                Label(currentDirectory != nil ? "Back to Parent Folder" : "Clear Shelf", systemImage: currentDirectory != nil ? "arrow.up" : "trash")
            }
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(for paths: [String]) -> some View {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        
        if paths.count == 1, let single = paths.first {
            var isDir: ObjCBool = false
            let isDirectory = FileManager.default.fileExists(atPath: single, isDirectory: &isDir) && isDir.boolValue
            if isDirectory {
                Button {
                    if let cur = currentDirectory {
                        folderHistory.append(cur)
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        currentDirectory = URL(fileURLWithPath: single)
                        selectedPaths.removeAll()
                        lastClickedPath = nil
                    }
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
            }
            
            Button {
                startRenaming(single)
            } label: {
                Label("Rename...", systemImage: "pencil")
            }
        }
        
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
                if currentDirectory != nil {
                    try? FileManager.default.removeItem(at: fileURL)
                } else {
                    manager.heldItems.removeAll { $0 == p }
                }
            }
            selectedPaths.removeAll()
            if displayedItems.isEmpty && currentDirectory == nil {
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
        let shelfWindowFrame = DropShelfManager.shared.shelfWindow?.frame ?? .zero
        let myWindowFrame = self.window?.frame ?? .zero
        let isInside = shelfWindowFrame.contains(screenPoint) || myWindowFrame.contains(screenPoint)
        
        if isInside {
            // User aborted or dragged back into the shelf window -> Keep files in shelf & untouched on disk!
            DispatchQueue.main.async {
                self.activeSessionPaths.removeAll()
            }
            return
        }
        
        // Items were successfully dropped into an external Finder window / target outside
        let pathsToRemove = self.activeSessionPaths
        self.activeSessionPaths.removeAll()
        
        DispatchQueue.main.async {
            for p in pathsToRemove {
                DropShelfManager.shared.heldItems.removeAll { $0 == p }
            }
            if DropShelfManager.shared.heldItems.isEmpty {
                DropShelfManager.shared.closeShelf()
            }
        }
        
        // Complete the Move operation by removing original source files from disk
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35) {
            for p in pathsToRemove {
                let url = URL(fileURLWithPath: p)
                if FileManager.default.fileExists(atPath: p) {
                    if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) == nil {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }
    }
}
