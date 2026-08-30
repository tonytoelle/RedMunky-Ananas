import SwiftUI
import UniformTypeIdentifiers

struct DropShelfView: View {
    @ObservedObject var manager: DropShelfManager
    @State private var isTargeted = false
    @State private var selectedPaths: Set<String> = []
    
    var body: some View {
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
                // Header Area
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
                        Text(selectedPaths.isEmpty ? "\(manager.heldItems.count) items" : "\(selectedPaths.count) of \(manager.heldItems.count) selected")
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
                            Button("Select All") {
                                selectedPaths = Set(manager.heldItems)
                            }
                            
                            if !selectedPaths.isEmpty {
                                Button("Deselect All") {
                                    selectedPaths.removeAll()
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
                                
                                Button("Quick Look") {
                                    NSWorkspace.shared.open(url)
                                }
                                
                                Divider()
                                
                                Button("Copy to Clipboard") {
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
                .padding(.top, 10)
                
                Spacer()
                
                // Drop Content Area / File Preview
                Group {
                    if manager.heldItems.isEmpty {
                        // Empty State (Waiting for Drop)
                        VStack(spacing: 8) {
                            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "plus.rectangle.on.folder")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.5))
                                .scaleEffect(isTargeted ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
                            
                            Text(isTargeted ? "Drop Files to Hold" : "Drop files to hold")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if manager.heldItems.count == 1, let firstItem = manager.heldItems.first {
                        // Single Item Display (Classic Large Finder Icon)
                        let url = URL(fileURLWithPath: firstItem)
                        let fileName = url.lastPathComponent
                        let isSelected = selectedPaths.contains(firstItem)
                        
                        DraggableCardContainer(filePaths: [firstItem]) {
                            VStack(spacing: 6) {
                                Image(nsImage: fileIcon(for: firstItem))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 64, height: 64)
                                
                                Text(fileName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 140)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                NSWorkspace.shared.open(url)
                            }
                            .onTapGesture(count: 1) {
                                if selectedPaths.contains(firstItem) {
                                    selectedPaths.remove(firstItem)
                                } else {
                                    selectedPaths = [firstItem]
                                }
                            }
                            .contextMenu {
                                fileContextMenu(for: [firstItem])
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Multiple Items Display (Finder Grid View with Selection)
                        VStack(spacing: 6) {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 80), spacing: 8)], spacing: 10) {
                                    ForEach(manager.heldItems, id: \.self) { itemPath in
                                        let itemURL = URL(fileURLWithPath: itemPath)
                                        let isSelected = selectedPaths.contains(itemPath)
                                        let dragPayload = selectedPaths.contains(itemPath) && selectedPaths.count > 1 ? Array(selectedPaths) : [itemPath]
                                        
                                        DraggableCardContainer(filePaths: dragPayload) {
                                            VStack(spacing: 4) {
                                                Image(nsImage: fileIcon(for: itemPath))
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 44, height: 44)
                                                
                                                Text(itemURL.lastPathComponent)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.white)
                                                    .multilineTextAlignment(.center)
                                                    .lineLimit(2)
                                                    .truncationMode(.middle)
                                                    .frame(maxWidth: 72)
                                            }
                                            .padding(6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture(count: 2) {
                                                NSWorkspace.shared.open(itemURL)
                                            }
                                            .onTapGesture(count: 1) {
                                                if NSEvent.modifierFlags.contains(.command) {
                                                    if selectedPaths.contains(itemPath) {
                                                        selectedPaths.remove(itemPath)
                                                    } else {
                                                        selectedPaths.insert(itemPath)
                                                    }
                                                } else {
                                                    if selectedPaths.contains(itemPath) && selectedPaths.count == 1 {
                                                        selectedPaths.removeAll()
                                                    } else {
                                                        selectedPaths = [itemPath]
                                                    }
                                                }
                                            }
                                            .contextMenu {
                                                fileContextMenu(for: selectedPaths.contains(itemPath) ? Array(selectedPaths) : [itemPath])
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 4)
                            }
                            
                            // Bottom Action: Drag All or Drag Selected
                            let dragTargets = selectedPaths.isEmpty ? manager.heldItems : Array(selectedPaths)
                            DraggableCardContainer(filePaths: dragTargets) {
                                HStack(spacing: 5) {
                                    Image(systemName: "hand.draw.fill")
                                        .font(.system(size: 10))
                                    Text(selectedPaths.isEmpty ? "Drag All (\(manager.heldItems.count))" : "Drag Selected (\(selectedPaths.count))")
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(selectedPaths.isEmpty ? Color.white.opacity(0.12) : Color.accentColor.opacity(0.8))
                                .clipShape(Capsule())
                            }
                            .padding(.bottom, 6)
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            manager.heldItems = current
                        }
                    }
                    return true
                }
                
                Spacer()
                    .frame(height: 8)
            }
        }
        .frame(minWidth: 140, maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
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
    
    private func fileIcon(for path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 128, height: 128)
        return icon
    }
}

// ==========================================
// MARK: - Native AppKit Dragging Source Container
// ==========================================

struct DraggableCardContainer<Content: View>: NSViewRepresentable {
    let filePaths: [String]
    let content: Content
    
    init(filePaths: [String], @ViewBuilder content: () -> Content) {
        self.filePaths = filePaths
        self.content = content()
    }
    
    func makeNSView(context: Context) -> DraggableContainerNSView {
        let view = DraggableContainerNSView()
        view.filePaths = filePaths
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
        if let hosting = nsView.hostingView as? NSHostingView<Content> {
            hosting.rootView = content
        }
    }
}

class DraggableContainerNSView: NSView, NSDraggingSource {
    var filePaths: [String] = []
    var hostingView: NSView?
    private var dragStartLocation: NSPoint?
    
    override var mouseDownCanMoveWindow: Bool {
        return false // Prevents the OS from dragging the window when clicking/dragging the card!
    }
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .move, .generic]
    }
    
    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartLocation else { return }
        let current = event.locationInWindow
        let dist = hypot(current.x - start.x, current.y - start.y)
        guard dist > 3 else { return }
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
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // If the item was successfully dropped and accepted (not cancelled)
        if operation != [] {
            DispatchQueue.main.async {
                DropShelfManager.shared.closeShelf()
            }
        }
    }
}
