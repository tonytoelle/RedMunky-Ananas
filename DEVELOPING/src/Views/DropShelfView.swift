import SwiftUI
import UniformTypeIdentifiers

struct DropShelfView: View {
    @ObservedObject var manager: DropShelfManager
    @State private var isTargeted = false
    
    var body: some View {
        ZStack {
            // Background WindowDragView to make it draggable by window background
            WindowDragView()
            
            // Visual Effect Background (HUD window style translucent black card)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(white: 0.08).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 8)
                .allowsHitTesting(false)
            
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
                        
                        Button("Clear Shelf") {
                            manager.closeShelf()
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                
                // Content Canvas
                VStack(spacing: 12) {
                    if manager.heldItems.isEmpty {
                        // Empty drop target
                        VStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.down.on.square.fill")
                                .font(.system(size: 32))
                                .foregroundColor(isTargeted ? .accentColor : .white.opacity(0.4))
                            
                            Text("Wiggle & Drop\nHere to Hold")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isTargeted ? Color.accentColor : Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .bevel, miterLimit: 10, dash: [4, 4], dashPhase: 0))
                                .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                                .cornerRadius(16)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else {
                        // Populated Item View
                        VStack(spacing: 10) {
                            let firstPath = manager.heldItems.first ?? ""
                            let url = URL(fileURLWithPath: firstPath)
                            let fileName = url.lastPathComponent
                            let ext = url.pathExtension.uppercased()
                            
                            // Visual Document Card
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                                    .frame(width: 60, height: 75)
                                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Color.gray.opacity(0.3).frame(height: 5)
                                    Color.gray.opacity(0.3).frame(height: 3)
                                    Color.gray.opacity(0.3).frame(height: 3)
                                    Color.gray.opacity(0.3).frame(height: 3)
                                    Spacer()
                                }
                                .padding(10)
                                .frame(width: 60, height: 75)
                                
                                // File Badge Icon Overlay if not generic
                                if ext == "SHORTKING" {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.orange)
                                        .shadow(radius: 1)
                                }
                            }
                            .onDrag {
                                let stringData = manager.heldItems.joined(separator: "\n") as NSString
                                return NSItemProvider(object: stringData)
                            }
                            
                            // Filename Label
                            Text(manager.heldItems.count > 1 ? "\(manager.heldItems.count) items selected" : fileName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .allowsHitTesting(false)
                            
                            // Item Type Tag capsule
                            Text(manager.heldItems.count > 1 ? "MULTIPLE" : (ext.isEmpty ? "FILE" : ext))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                                .allowsHitTesting(false)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
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
        .ignoresSafeArea()
    }
}
