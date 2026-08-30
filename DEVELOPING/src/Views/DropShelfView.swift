import SwiftUI
import UniformTypeIdentifiers

struct DropShelfView: View {
    @ObservedObject var manager: DropShelfManager
    @State private var isTargeted = false
    
    var body: some View {
        ZStack {
            // Native macOS Glass Background
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.85))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
            
            VStack(spacing: 0) {
                // Header Area
                HStack {
                    // Close Button (X)
                    Button {
                        manager.closeShelf()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Minimize/Dismiss Button (v) with Dropover actions menu
                    Menu {
                        if let firstPath = manager.heldItems.first {
                            let url = URL(fileURLWithPath: firstPath)
                            let fileName = url.lastPathComponent
                            
                            Menu("Open With") {
                                Button("Antigravity IDE") {
                                    NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/Applications/Antigravity.app"), configuration: NSWorkspace.OpenConfiguration())
                                }
                                Button("CotEditor") {
                                    NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/Applications/CotEditor.app"), configuration: NSWorkspace.OpenConfiguration())
                                }
                                Button("Notes") {
                                    NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Notes.app"), configuration: NSWorkspace.OpenConfiguration())
                                }
                                Button("Safari") {
                                    NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"), configuration: NSWorkspace.OpenConfiguration())
                                }
                                Button("TextEdit") {
                                    NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), configuration: NSWorkspace.OpenConfiguration())
                                }
                            }
                            
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            
                            Button("Quick Look") {
                                NSWorkspace.shared.open(url)
                            }
                            
                            Divider()
                            
                            Button("Copy \"\(fileName)\"") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.writeObjects([url as NSURL])
                            }
                            
                            Button("Copy to...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let targetDir = panel.url {
                                    let dest = targetDir.appendingPathComponent(fileName)
                                    try? FileManager.default.copyItem(at: url, to: dest)
                                }
                            }
                            
                            Button("Move to...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let targetDir = panel.url {
                                    let dest = targetDir.appendingPathComponent(fileName)
                                    try? FileManager.default.moveItem(at: url, to: dest)
                                    manager.closeShelf()
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button("Clear All") {
                            manager.heldItems.removeAll()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                
                Spacer()
                
                // Drop Content Area / File Preview
                Group {
                    if manager.heldItems.isEmpty {
                        // Empty State (Waiting for Drop)
                        VStack(spacing: 8) {
                            Image(systemName: "plus.rectangle.on.folder")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.5))
                                .scaleEffect(isTargeted ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
                            
                            Text(isTargeted ? "Release to Hold" : "Drop files to hold")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.6))
                        }
                    } else {
                        // Populated State (Authentic Finder Icon View)
                        if let firstItem = manager.heldItems.first {
                            let url = URL(fileURLWithPath: firstItem)
                            let fileName = url.lastPathComponent
                            
                            DraggableCardContainer(filePaths: manager.heldItems) {
                                VStack(spacing: 6) {
                                    ZStack(alignment: .topTrailing) {
                                        // Native macOS Finder File Icon
                                        Image(nsImage: fileIcon(for: firstItem))
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 64, height: 64)
                                        
                                        // Item Count Badge (if multiple items held)
                                        if manager.heldItems.count > 1 {
                                            Text("\(manager.heldItems.count)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor)
                                                .clipShape(Capsule())
                                                .offset(x: 10, y: -6)
                                        }
                                    }
                                    
                                    // Finder-style 2-line text label
                                    Text(manager.heldItems.count > 1 ? "\(fileName)\n+ \(manager.heldItems.count - 1) items" : fileName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: 140)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    NSWorkspace.shared.open(url)
                                }
                                .contextMenu {
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Label("Open", systemImage: "arrow.up.forward.app")
                                    }
                                    
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    } label: {
                                        Label("Show in Finder", systemImage: "folder")
                                    }
                                    
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Label("Quick Look", systemImage: "eye")
                                    }
                                    
                                    Divider()
                                    
                                    Button {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.writeObjects(manager.heldItems.map { URL(fileURLWithPath: $0) as NSURL })
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    
                                    Button(role: .destructive) {
                                        for path in manager.heldItems {
                                            let fileURL = URL(fileURLWithPath: path)
                                            try? FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                                        }
                                        manager.closeShelf()
                                    } label: {
                                        Label("Move to Trash", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isTargeted) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                            guard let str = string as? String else { return }
                            let paths = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                            // Filter local file paths
                            let filePaths = paths.map { path -> String in
                                if path.hasPrefix("file://"), let fileURL = URL(string: path) {
                                    return fileURL.path
                                }
                                return path
                            }
                            DispatchQueue.main.async {
                                manager.heldItems = filePaths
                            }
                        }
                    }
                    return true
                }
                
                Spacer()
                    .frame(height: 14)
            }
        }
        .frame(width: 180, height: 180)
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
