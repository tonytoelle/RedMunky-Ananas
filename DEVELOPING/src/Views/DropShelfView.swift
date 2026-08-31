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
        
        // 0. Virtual Folder Transit (Pure In-Memory hierarchy export)
        if DropShelfManager.shared.isVirtualFolder(sourceURL.path) {
            let folderName = customFileName ?? DropShelfManager.shared.displayName(for: sourceURL.path)
            var destFolderURL = destinationDirectory.appendingPathComponent(folderName, isDirectory: true)
            destFolderURL = uniqueURL(for: destFolderURL)
            
            try? fileManager.createDirectory(at: destFolderURL, withIntermediateDirectories: true)
            
            let children = DropShelfManager.shared.virtualFolderChildren[sourceURL.path] ?? []
            for child in children {
                let childURL = URL(fileURLWithPath: child)
                _ = convertAndSave(
                    sourceURL: childURL,
                    format: format,
                    destinationDirectory: destFolderURL,
                    quality: quality
                )
            }
            return destFolderURL
        }
        
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
        Group {
            if DropShelfManager.shared.isVirtualFolder(path) {
                Image(nsImage: NSWorkspace.shared.icon(forFileType: "public.folder"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size > 50 ? 9 : 6, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1.5)
        .onAppear {
            if !DropShelfManager.shared.isVirtualFolder(path) {
                loadImage()
            }
        }
        .onChange(of: path) { _, _ in
            if !DropShelfManager.shared.isVirtualFolder(path) {
                loadImage()
            }
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
    
    // Virtual Folder Navigation inside DropShelf (Pure Transit, Zero premature disk writes)
    @State private var currentVirtualFolderId: String? = nil
    @State private var folderHistory: [String] = []
    
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
        if let folderId = currentVirtualFolderId {
            return manager.virtualFolderChildren[folderId] ?? []
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
                // Pure Native macOS Window Surface (macOS Native Shadow & Clean Rounded Corner)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        Group {
                            if isTargeted {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.accentColor, lineWidth: 2)
                            }
                        }
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
                                if currentVirtualFolderId != nil {
                                    navigateUp()
                                } else {
                                    manager.closeShelf()
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 26, height: 26)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(currentVirtualFolderId != nil ? "Close Folder / Shelf" : "Close Shelf")
                            
                            // Up Arrow Button (Back to Parent Folder)
                            if currentVirtualFolderId != nil {
                                Button {
                                    navigateUp()
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white.opacity(0.85))
                                        .frame(width: 26, height: 26)
                                        .background(Color.white.opacity(0.12))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Back to Parent Folder")
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            // Current Folder Title
                            if let curFolder = currentVirtualFolderId {
                                Text(manager.displayName(for: curFolder))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
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
                                        .background(Color.white.opacity(0.12))
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
                                        if currentVirtualFolderId != nil {
                                            navigateUp()
                                        } else {
                                            manager.closeShelf()
                                        }
                                    } label: {
                                        Text(currentVirtualFolderId != nil ? "Back to Parent Folder" : "Clear Shelf")
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
                            // Ultra-clean Minimalist Empty State (No Box, No Icon)
                            VStack {
                                Text(isTargeted ? "Drop to Hold" : (currentVirtualFolderId != nil ? "Folder is empty" : "Drop files here"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.45))
                                    .scaleEffect(isTargeted ? 1.08 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
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
                                        let isSelected = selectedPaths.contains(itemPath)
                                        let pos = currentPosition(for: itemPath, in: outerGeo.size)
                                        let dragOffset = activeDragOffsets[itemPath] ?? .zero
                                        let isVirtual = manager.isVirtualFolder(itemPath)
                                        
                                        var isDir: ObjCBool = false
                                        let isDirectory = isVirtual || (FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDir) && isDir.boolValue)
                                        let itemDisplayName = manager.displayName(for: itemPath)
                                        
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
                                                if isVirtual {
                                                    if let cur = currentVirtualFolderId {
                                                        folderHistory.append(cur)
                                                    }
                                                    itemPositions.removeAll()
                                                    activeDragOffsets.removeAll()
                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                        currentVirtualFolderId = itemPath
                                                        selectedPaths.removeAll()
                                                        lastClickedPath = nil
                                                        directoryChangeToken = UUID()
                                                    }
                                                } else {
                                                    NSWorkspace.shared.open(URL(fileURLWithPath: itemPath))
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
                                                    guard other != itemPath else { continue }
                                                    var isDir: ObjCBool = false
                                                    let isOtherDir = manager.isVirtualFolder(other) || (FileManager.default.fileExists(atPath: other, isDirectory: &isDir) && isDir.boolValue)
                                                    if isOtherDir {
                                                        let fPos = currentPosition(for: other, in: outerGeo.size)
                                                        let dist = hypot(curPos.x - fPos.x, curPos.y - fPos.y)
                                                        if dist < 75 {
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
                                                let rawTargets = selectedPaths.contains(itemPath) && !selectedPaths.isEmpty ? Array(selectedPaths) : [itemPath]
                                                let destFolder = hoveredFolder
                                                hoveredFolder = nil
                                                
                                                if let folder = destFolder {
                                                    let actualTargets = rawTargets.filter { $0 != folder }
                                                    if !actualTargets.isEmpty {
                                                        moveItems(actualTargets, intoFolder: folder)
                                                    }
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
                                                            guard other != itemPath else { continue }
                                                            var isDir: ObjCBool = false
                                                            let isOtherDir = manager.isVirtualFolder(other) || (FileManager.default.fileExists(atPath: other, isDirectory: &isDir) && isDir.boolValue)
                                                            if isOtherDir {
                                                                let fPos = currentPosition(for: other, in: outerGeo.size)
                                                                let dist = hypot(myFinalPos.x - fPos.x, myFinalPos.y - fPos.y)
                                                                if dist < 85 {
                                                                    fallbackFolder = other
                                                                    break
                                                                }
                                                            }
                                                        }
                                                    }
                                                    
                                                    if let fb = fallbackFolder {
                                                        let actualTargets = rawTargets.filter { $0 != fb }
                                                        if !actualTargets.isEmpty {
                                                            moveItems(actualTargets, intoFolder: fb)
                                                        }
                                                    } else {
                                                        for t in rawTargets {
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
                                                
                                                for t in rawTargets {
                                                    activeDragOffsets.removeValue(forKey: t)
                                                }
                                            },
                                            onExternalDrop: { paths in
                                                // True Move: file was dragged from DropShelf to Finder
                                                for p in paths {
                                                    manager.heldItems.removeAll { $0 == p }
                                                }
                                            }
                                        ) {
                                            VStack(spacing: 6) {
                                                AsyncFileThumbnailView(path: itemPath, size: displayedItems.count == 1 ? 64 : 46)
                                                    .scaleEffect(isDirectory && hoveredFolder == itemPath ? 1.15 : 1.0)
                                                    .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hoveredFolder == itemPath)
                                                
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
                                                    Text(itemDisplayName)
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
                        // 1. Direct synchronous pasteboard extraction (Instant & 100% exact path from Finder)
                        var directPaths: [String] = []
                        let pasteboards = [NSPasteboard(name: .drag), NSPasteboard.general]
                        for pb in pasteboards {
                            if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                                for url in urls where url.isFileURL && FileManager.default.fileExists(atPath: url.path) {
                                    if !directPaths.contains(url.path) {
                                        directPaths.append(url.path)
                                    }
                                }
                            }
                            if !directPaths.isEmpty { break }
                        }
                        
                        if !directPaths.isEmpty {
                            processIngestedPaths(directPaths)
                            return true
                        }
                        
                        // 2. Asynchronous NSItemProvider extraction
                        var loadedPaths: [String] = []
                        let group = DispatchGroup()
                        
                        for provider in providers {
                            group.enter()
                            
                            // Check file-url type identifier first
                            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                                _ = provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, _) in
                                    if let path = self.extractFilePath(from: item) {
                                        loadedPaths.append(path)
                                    }
                                    group.leave()
                                }
                            }
                            // Check NSURL object reading
                            else if provider.canLoadObject(ofClass: NSURL.self) {
                                _ = provider.loadObject(ofClass: NSURL.self) { (obj, _) in
                                    if let nsURL = obj as? NSURL, let url = nsURL as URL?, url.isFileURL {
                                        loadedPaths.append(url.path)
                                    }
                                    group.leave()
                                }
                            }
                            // Check string / text path
                            else if provider.canLoadObject(ofClass: NSString.self) {
                                _ = provider.loadObject(ofClass: NSString.self) { (string, _) in
                                    if let str = string as? String {
                                        let lines = str.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                                        for line in lines {
                                            if let path = self.extractFilePath(from: line) {
                                                loadedPaths.append(path)
                                            }
                                        }
                                    }
                                    group.leave()
                                }
                            } else {
                                group.leave()
                            }
                        }
                        
                        group.notify(queue: .main) {
                            self.processIngestedPaths(loadedPaths)
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
    
    private func extractFilePath(from item: Any?) -> String? {
        if let url = item as? URL, url.isFileURL {
            return url.path
        }
        if let nsURL = item as? NSURL, let url = nsURL as URL?, url.isFileURL {
            return url.path
        }
        if let str = item as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("file://"), let u = URL(string: trimmed), u.isFileURL {
                return u.path
            }
            if FileManager.default.fileExists(atPath: trimmed) {
                return trimmed
            }
        }
        if let data = item as? Data {
            if let str = String(data: data, encoding: .utf8) {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("file://"), let u = URL(string: trimmed), u.isFileURL {
                    return u.path
                }
                if FileManager.default.fileExists(atPath: trimmed) {
                    return trimmed
                }
            }
            if let u = URL(dataRepresentation: data, relativeTo: nil), u.isFileURL {
                return u.path
            }
        }
        return nil
    }
    
    private func processIngestedPaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        if let cur = currentVirtualFolderId {
            var current = manager.virtualFolderChildren[cur] ?? []
            for p in paths {
                if !current.contains(p) {
                    current.append(p)
                }
            }
            manager.virtualFolderChildren[cur] = current
            withAnimation(.spring(response: 0.45, dampingFraction: 0.58, blendDuration: 0.2)) {
                selectedPaths = Set(paths)
                plungePulse = true
                directoryChangeToken = UUID()
            }
        } else {
            // PURE TRANSIT: Memorize exact source paths directly without copying or renaming
            var current = manager.heldItems
            for p in paths {
                if !current.contains(p) {
                    current.append(p)
                }
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.58, blendDuration: 0.2)) {
                manager.heldItems = current
                selectedPaths = Set(current) // Select All so user can immediately drag to Finder
                plungePulse = true
                directoryChangeToken = UUID()
            }
            if current.count > 4 && !isExpanded {
                toggleExpand()
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
    
    // MARK: - Virtual Folder Navigation & Creation (Pure In-Memory)
    
    private func createNewFolder() {
        let newFolderId = manager.createVirtualFolder(name: "New Folder", inside: currentVirtualFolderId)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            selectedPaths = [newFolderId]
            lastClickedPath = newFolderId
            directoryChangeToken = UUID()
        }
    }
    
    private func navigateUp() {
        itemPositions.removeAll()
        activeDragOffsets.removeAll()
        if !folderHistory.isEmpty {
            currentVirtualFolderId = folderHistory.removeLast()
        } else {
            currentVirtualFolderId = nil
        }
        selectedPaths.removeAll()
        lastClickedPath = nil
        directoryChangeToken = UUID()
    }
    
    // MARK: - Renaming & Moving Items
    
    private func startRenaming(_ path: String) {
        renamingText = manager.displayName(for: path)
        renamingPath = path
    }
    
    private func commitRename() {
        guard let oldPath = renamingPath else { return }
        let cleanName = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            renamingPath = nil
            return
        }
        
        if manager.isVirtualFolder(oldPath) {
            manager.virtualFolderNames[oldPath] = cleanName
            directoryChangeToken = UUID()
        } else {
            let oldURL = URL(fileURLWithPath: oldPath)
            let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(cleanName)
            
            if oldURL.path != newURL.path {
                do {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                    if let idx = manager.heldItems.firstIndex(of: oldPath) {
                        manager.heldItems[idx] = newURL.path
                    }
                    if let cur = currentVirtualFolderId, let idx = manager.virtualFolderChildren[cur]?.firstIndex(of: oldPath) {
                        manager.virtualFolderChildren[cur]?[idx] = newURL.path
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
        }
        renamingPath = nil
    }
    
    private func moveItems(_ sourcePaths: [String], intoFolder folderPath: String) {
        if manager.isVirtualFolder(folderPath) {
            manager.moveItems(sourcePaths, into: folderPath, currentFolderId: currentVirtualFolderId)
            for src in sourcePaths {
                itemPositions.removeValue(forKey: src)
                activeDragOffsets.removeValue(forKey: src)
            }
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
                } else if currentVirtualFolderId != nil {
                    navigateUp()
                } else {
                    manager.closeShelf()
                }
                return nil
            }
            
            // 4. Spacebar (49) -> Quick Look / Open Preview
            if keyCode == 49 {
                if let first = selectedPaths.first ?? displayedItems.first, !manager.isVirtualFolder(first) {
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
            manager.removeItems(targets, currentFolderId: currentVirtualFolderId)
            for p in targets {
                itemPositions.removeValue(forKey: p)
            }
            selectedPaths.removeAll()
            lastClickedPath = nil
            directoryChangeToken = UUID()
        }
        
        let remaining = displayedItems
        if remaining.isEmpty {
            if currentVirtualFolderId == nil {
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
                if currentVirtualFolderId != nil {
                    navigateUp()
                } else {
                    manager.closeShelf()
                }
            } label: {
                Label(currentVirtualFolderId != nil ? "Back to Parent Folder" : "Clear Shelf", systemImage: currentVirtualFolderId != nil ? "arrow.up" : "trash")
            }
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(for paths: [String]) -> some View {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        
        if paths.count == 1, let single = paths.first {
            let isVirtual = manager.isVirtualFolder(single)
            if isVirtual {
                Button {
                    if let cur = currentVirtualFolderId {
                        folderHistory.append(cur)
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        currentVirtualFolderId = single
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
        
        if let first = urls.first, !manager.isVirtualFolder(first.path) {
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                manager.removeItems(paths, currentFolderId: currentVirtualFolderId)
                for p in paths {
                    itemPositions.removeValue(forKey: p)
                }
                selectedPaths.removeAll()
                lastClickedPath = nil
                directoryChangeToken = UUID()
            }
            if displayedItems.isEmpty && currentVirtualFolderId == nil {
                manager.closeShelf()
            }
        } label: {
            Label(paths.count > 1 ? "Remove \(paths.count) from Shelf" : "Remove from Shelf", systemImage: "trash")
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
    var onExternalDrop: (([String]) -> Void)? = nil
    let content: Content
    
    init(
        itemPath: String,
        getFilePaths: @escaping () -> [String],
        onClick: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onMoveDelta: ((CGSize) -> Void)? = nil,
        onEndMove: (() -> Void)? = nil,
        onExternalDrop: (([String]) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.itemPath = itemPath
        self.getFilePaths = getFilePaths
        self.onClick = onClick
        self.onDoubleClick = onDoubleClick
        self.onMoveDelta = onMoveDelta
        self.onEndMove = onEndMove
        self.onExternalDrop = onExternalDrop
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
        view.onExternalDrop = onExternalDrop
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
        nsView.onExternalDrop = onExternalDrop
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
    var onExternalDrop: (([String]) -> Void)?
    
    var hostingView: NSView?
    private var dragStartLocation: NSPoint?
    private var lastDragLocation: NSPoint?
    private var hasInitiatedSession = false
    private var isDraggingLocally = false
    private var wasAlreadySelected = false
    
    private var activeSessionTargets: [String] = []
    private var activeSessionOriginalFiles: [String] = []
    private var activeSessionStagingDirs: [URL] = []
    
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
        let currentInWindow = event.locationInWindow
        let currentScreen = NSEvent.mouseLocation
        
        let windowFrame = self.window?.frame ?? .zero
        let isInsideWindow = windowFrame.contains(currentScreen)
        
        let totalDist = hypot(currentInWindow.x - start.x, currentInWindow.y - start.y)
        guard totalDist > 3 else { return }
        
        if !isInsideWindow {
            // Dragged outside window -> Start native Finder Dragging Session!
            hasInitiatedSession = true
            isDraggingLocally = false
            dragStartLocation = nil
            onEndMove?()
            
            let targets = getFilePaths?() ?? [itemPath]
            guard !targets.isEmpty else { return }
            
            self.activeSessionTargets = targets
            self.activeSessionOriginalFiles.removeAll()
            self.activeSessionStagingDirs.removeAll()
            
            var draggingItems: [NSDraggingItem] = []
            
            for (index, target) in targets.enumerated() {
                let url: URL
                let img: NSImage
                
                if DropShelfManager.shared.isVirtualFolder(target) {
                    let (stagingURL, originalFiles) = DropShelfManager.shared.stageVirtualFolderForDrag(virtualFolderId: target)
                    url = stagingURL
                    activeSessionOriginalFiles.append(contentsOf: originalFiles)
                    activeSessionStagingDirs.append(stagingURL.deletingLastPathComponent())
                    img = NSWorkspace.shared.icon(forFile: stagingURL.path)
                } else {
                    url = URL(fileURLWithPath: target)
                    activeSessionOriginalFiles.append(target)
                    img = NSWorkspace.shared.icon(forFile: target)
                }
                
                img.size = NSSize(width: 48, height: 48)
                let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
                let offset = CGFloat(min(index, 4) * 3)
                let dragRect = NSRect(
                    x: (self.bounds.width - 48)/2 + offset,
                    y: (self.bounds.height - 48)/2 - offset,
                    width: 48,
                    height: 48
                )
                draggingItem.setDraggingFrame(dragRect, contents: img)
                draggingItems.append(draggingItem)
            }
            
            beginDraggingSession(with: draggingItems, event: event, source: self)
        } else {
            // Inside window -> Smooth local drag to move card or plunge into folder
            let prev = lastDragLocation ?? start
            let delta = CGSize(
                width: currentInWindow.x - prev.x,
                height: -(currentInWindow.y - prev.y)
            )
            lastDragLocation = currentInWindow
            isDraggingLocally = true
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
        let isInside = shelfWindowFrame.contains(screenPoint)
        
        let targetsToRemove = self.activeSessionTargets
        let originalFilesToDelete = self.activeSessionOriginalFiles
        let stagingDirs = self.activeSessionStagingDirs
        
        self.activeSessionTargets.removeAll()
        self.activeSessionOriginalFiles.removeAll()
        self.activeSessionStagingDirs.removeAll()
        
        // If dropped back onto the shelf window itself OR operation was cancelled / rejected:
        // DO NOT delete original files, DO NOT remove items from shelf!
        if isInside || operation == [] || targetsToRemove.isEmpty {
            for dir in stagingDirs {
                try? FileManager.default.removeItem(at: dir)
            }
            return
        }
        
        // Dropped outside onto Finder / other target -> Pure Move
        let externalDrop = self.onExternalDrop
        DispatchQueue.main.async {
            externalDrop?(targetsToRemove)
            for t in targetsToRemove {
                DropShelfManager.shared.heldItems.removeAll { $0 == t }
                for (k, _) in DropShelfManager.shared.virtualFolderChildren {
                    DropShelfManager.shared.virtualFolderChildren[k]?.removeAll { $0 == t }
                }
                if DropShelfManager.shared.isVirtualFolder(t) {
                    DropShelfManager.shared.virtualFolderNames.removeValue(forKey: t)
                    DropShelfManager.shared.virtualFolderChildren.removeValue(forKey: t)
                }
            }
            if DropShelfManager.shared.heldItems.isEmpty {
                DropShelfManager.shared.closeShelf()
            }
        }
        
        // Clean temporary staging directories
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            for dir in stagingDirs {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }
}
