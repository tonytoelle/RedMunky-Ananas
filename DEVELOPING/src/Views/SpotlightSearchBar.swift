import Foundation
import Cocoa
import ApplicationServices
import SwiftUI
import Carbon
import CoreImage
import CoreImage.CIFilterBuiltins
import ServiceManagement

// MARK: - Searchable Action Item Definition
// ==========================================
struct SearchableActionDef: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let category: String
    let keywords: [String]
    
    static let allActions: [SearchableActionDef] = [
        .init(title: "Path", icon: "point.topleft.down.to.point.bottomright.curvepath.fill", color: Color(red: 0.65, green: 0.25, blue: 0.85), category: "Utility",
              keywords: ["path", "sequence", "multi click", "points", "multi", "route", "multiclick", "alur"]),
        .init(title: "Current Position", icon: "cursorarrow.click.2", color: Color(red: 0.08, green: 0.45, blue: 0.82), category: "Mouse",
              keywords: ["current position", "current pos", "current", "here", "click here", "pos", "cursor position", "posisi kursor", "posisi saat ini"]),
        .init(title: "Left Click", icon: "cursorarrow.click", color: Color(red: 0.08, green: 0.45, blue: 0.82), category: "Mouse",
              keywords: ["click", "left click", "left", "lclick", "tap", "mouse click", "klik", "klik kiri"]),
        .init(title: "Right Click", icon: "cursorarrow.click", color: Color(red: 0.04, green: 0.52, blue: 0.54), category: "Mouse",
              keywords: ["right click", "rclick", "context menu", "secondary click", "right", "menu klik", "klik kanan"]),
        .init(title: "Drag", icon: "hand.draw", color: Color(red: 0.52, green: 0.22, blue: 0.75), category: "Mouse",
              keywords: ["drag", "drop", "drag and drop", "swipe", "move drag", "tarik", "geser"]),
        .init(title: "Move Cursor", icon: "cursorarrow.motionlines", color: Color(red: 0.28, green: 0.52, blue: 0.92), category: "Mouse",
              keywords: ["move cursor", "move", "cursor", "hover", "pointer", "pindah kursor", "geser"]),
        .init(title: "Delay", icon: "timer", color: Color(red: 0.88, green: 0.42, blue: 0.04), category: "Utility",
              keywords: ["delay", "wait", "sleep", "pause", "time", "timeout", "jeda", "tunggu", "waktu"]),
        .init(title: "Text", icon: "text.cursor", color: Color(red: 0.12, green: 0.58, blue: 0.24), category: "Keyboard",
              keywords: ["type", "typing", "tyepe", "type text", "write", "input", "string", "text", "teks", "ketik", "tulisan"]),
        .init(title: "Key", icon: "keyboard", color: Color(red: 0.32, green: 0.28, blue: 0.72), category: "Keyboard",
              keywords: ["key", "press key", "press", "hotkey", "shortcut", "keyboard", "button", "tombol", "pencet", "tekan"]),
        .init(title: "Do Again", icon: "arrow.counterclockwise", color: Color(red: 0.12, green: 0.58, blue: 0.65), category: "Utility",
              keywords: ["do again", "again", "repeat", "loop", "restart", "back to origin", "ulang", "kembali", "ulangi"]),
        .init(title: "Group", icon: "folder", color: Color.orange, category: "Utility",
              keywords: ["group", "folder", "section", "block", "container", "grup", "kelompok"]),
        .init(title: "Custom", icon: "terminal", color: Color.pink, category: "Utility",
              keywords: ["custom", "custom action", "script", "terminal", "zsh", "bash", "shell", "command", "osascript", "applescript", "code", "perintah"]),
        .init(title: "Open File", icon: "arrow.up.forward.app", color: Color(red: 0.1, green: 0.65, blue: 0.6), category: "Utility",
              keywords: ["open file", "open", "file", "launch", "app", "application", "buka", "berkas", "aplikasi"]),
        .init(title: "Vol Up", icon: "speaker.wave.3.fill", color: Color.blue, category: "System",
              keywords: ["vol up", "volume up", "volume", "sound", "louder", "audio", "suara", "tambah suara"]),
        .init(title: "Vol Down", icon: "speaker.wave.1.fill", color: Color.blue, category: "System",
              keywords: ["vol down", "volume down", "volume", "sound", "quieter", "audio", "suara", "kecilkan suara"]),
        .init(title: "Brit Up", icon: "sun.max.fill", color: Color.orange, category: "System",
              keywords: ["brit up", "brightness up", "brightness", "light", "screen", "display", "terang", "kecerahan"]),
        .init(title: "Brit Down", icon: "sun.min.fill", color: Color.orange, category: "System",
              keywords: ["brit down", "brightness down", "brightness", "dark", "dim", "screen", "display", "gelap", "redup"]),
        .init(title: "Window Transform", icon: "macwindow", color: Color(red: 0.1, green: 0.58, blue: 0.8), category: "Utility",
              keywords: ["window transform", "window", "transform", "resize", "screen area", "move window", "fit window", "jendela", "layar"]),
        .init(title: "Origin", icon: "scope", color: Color(red: 0.85, green: 0.15, blue: 0.45), category: "Mouse",
              keywords: ["origin", "origin position", "record position", "save pos", "titik awal", "posisi awal"]),
        .init(title: "AX Press", icon: "hand.tap", color: Color.purple, category: "Utility",
              keywords: ["ax press", "ax", "accessibility", "press", "ui element", "menu item", "button", "click ax", "element", "axpress", "axclick", "otomasi ui"]),
    ]
}

// ==========================================
// MARK: - Raycast/Spotlight Search View (Grid Results)
// ==========================================
struct SpotlightSearchBar: View {
    let placeholder: String
    let items: [SearchableActionDef]
    let width: CGFloat // Width passed directly from parent container to prevent layout loops
    let onSelect: (SearchableActionDef) -> Void
    
    @ObservedObject private var store = MacroStore.shared
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var activeCategory: String = "All"
    @State private var showAllResults: Bool = false
    @FocusState private var isFocused: Bool
    
    @State private var keyMonitor: Any? = nil
    
    let categories = ["All", "Mouse", "Keyboard", "System", "Utility"]
    
    // Statically compute the correct columns count to prevent layout feedback loops
    var columnsCount: Int {
        let availableWidth = max(100, width - 60)
        let itemWidth: CGFloat = 78
        let spacing: CGFloat = 12
        let cols = max(1, Int((availableWidth + spacing) / (itemWidth + spacing)))
        return cols
    }
    
    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columnsCount)
    }
    
    var filteredItems: [(item: SearchableActionDef, score: Int)] {
        let matchingCategoryItems = items.filter { item in
            activeCategory == "All" || item.category == activeCategory
        }
        
        let trimmedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else {
            return matchingCategoryItems.map { ($0, 100) }
        }
        
        return matchingCategoryItems.compactMap { item -> (SearchableActionDef, Int)? in
            let score = computeActionScore(query: trimmedQuery, item: item)
            guard score < 9999 else { return nil }
            return (item, score)
        }.sorted { a, b in
            if a.score != b.score {
                return a.score < b.score
            }
            return a.item.title < b.item.title
        }
    }
    
    private func computeActionScore(query: String, item: SearchableActionDef) -> Int {
        let t = item.title.lowercased()
        
        // 1. Exact title match
        if t == query { return 0 }
        
        // 2. Exact keyword match
        for kw in item.keywords where kw.lowercased() == query {
            return 1
        }
        
        // 3. Title prefix match
        if t.hasPrefix(query) { return 5 }
        
        // 4. Keyword prefix match
        for kw in item.keywords where kw.lowercased().hasPrefix(query) {
            return 10
        }
        
        // 5. Title contains query
        if t.contains(query) { return 20 }
        
        // 6. Keyword contains query
        for kw in item.keywords where kw.lowercased().contains(query) {
            return 25
        }
        
        // 7. Fuzzy match on title
        let titleFuzzy = fuzzyMatch(query, in: item.title, tolerance: 3)
        var minFuzzyScore = titleFuzzy.matches ? (50 + titleFuzzy.score * 5) : 9999
        
        // 8. Fuzzy match on keywords (catches typos like 'tyepe' -> 'type'/'text')
        for kw in item.keywords {
            let kwFuzzy = fuzzyMatch(query, in: kw, tolerance: 3)
            if kwFuzzy.matches {
                let s = 60 + kwFuzzy.score * 5
                if s < minFuzzyScore {
                    minFuzzyScore = s
                }
            }
        }
        
        return minFuzzyScore
    }
    
    // Limits the items displayed so the grid row is never incomplete/ompong
    var visibleItems: [(offset: Int, element: (item: SearchableActionDef, score: Int))] {
        let allFiltered = Array(filteredItems.enumerated())
        if showAllResults {
            return allFiltered
        } else {
            // Find a target multiple of columnsCount closest to 10
            let targetRows = max(1, Int(ceil(10.0 / Double(columnsCount))))
            let limit = targetRows * columnsCount
            return Array(allFiltered.prefix(limit))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            // Top Search Area: Borderless and integrated directly with container
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 15, weight: .medium))
                
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
                    .focused($isFocused)
                    .onSubmit {
                        executeSelection()
                    }
                
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.bottom, 12)
            
            // Category Chips Scroll Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            activeCategory = cat
                            selectedIndex = 0
                            showAllResults = false
                        } label: {
                            Text(cat)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(activeCategory == cat ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(activeCategory == cat ? Color.white.opacity(0.15) : Color.white.opacity(0.04))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(activeCategory == cat ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.bottom, 12)
            
            // Results Grid Area
            ScrollView(showsIndicators: true) {
                VStack(spacing: 12) {
                    if filteredItems.isEmpty {
                        Text("No matching actions found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(visibleItems, id: \.element.item.id) { idx, entry in
                                Button {
                                    onSelect(entry.item)
                                    query = ""
                                } label: {
                                    VStack(spacing: 5) {
                                        ZStack(alignment: .topTrailing) {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(entry.item.color)
                                                .frame(width: 42, height: 42)
                                            Image(systemName: entry.item.icon)
                                                .foregroundColor(.white)
                                                .font(.system(size: 17, weight: .semibold))
                                                .frame(width: 42, height: 42)
                                            
                                            if !query.trimmingCharacters(in: .whitespaces).isEmpty && idx == 0 {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.yellow)
                                                    .padding(3)
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                                    .offset(x: 4, y: -4)
                                            }
                                        }
                                        
                                        Text(entry.item.title)
                                            .font(.system(size: 11, weight: idx == selectedIndex ? .bold : .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                        
                                        if !query.trimmingCharacters(in: .whitespaces).isEmpty && idx == 0 {
                                            Text("Top Match")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.yellow)
                                                .lineLimit(1)
                                        } else {
                                            Text(entry.item.category)
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill((store.isGridFocused && idx == store.gridSelectedIndex) || idx == selectedIndex ? Color.white.opacity(0.16) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke((store.isGridFocused && idx == store.gridSelectedIndex) || idx == selectedIndex ? Color.accentColor : (!query.trimmingCharacters(in: .whitespaces).isEmpty && idx == 0 ? Color.yellow.opacity(0.4) : Color.clear), lineWidth: 1.5)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { isHovered in
                                    if isHovered {
                                        selectedIndex = idx
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                        
                        // "See More" Button
                        if !showAllResults && filteredItems.count > visibleItems.count {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAllResults = true
                                }
                            } label: {
                                Text("See More (\(filteredItems.count - visibleItems.count) more)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                        } else if showAllResults && filteredItems.count > 10 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAllResults = false
                                }
                            } label: {
                                Text("Show Less")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onAppear {
            // Do NOT auto-focus on appear to prevent hijacking arrow keys
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            store.gridSelectedIndex = 0
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                setupKeyMonitor()
            } else {
                removeKeyMonitor()
            }
        }
    }
    
    private func executeSelection() {
        let itemsCount = visibleItems.count
        if itemsCount > 0 {
            let idx = max(0, min(selectedIndex, itemsCount - 1))
            onSelect(visibleItems[idx].element.item)
            query = ""
            selectedIndex = 0
            store.gridSelectedIndex = 0
        }
    }
    
    private func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let itemsCount = visibleItems.count
            guard itemsCount > 0 else { return event }
            
            switch event.keyCode {
            case 123: // Left arrow
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    return nil
                }
            case 124: // Right arrow
                if selectedIndex < itemsCount - 1 {
                    selectedIndex += 1
                    return nil
                }
            case 125: // Down arrow
                let newIndex = selectedIndex + columnsCount
                if newIndex < itemsCount {
                    selectedIndex = newIndex
                    return nil
                }
            case 126: // Up arrow
                let newIndex = selectedIndex - columnsCount
                if newIndex >= 0 {
                    selectedIndex = newIndex
                    return nil
                }
            case 36: // Enter
                executeSelection()
                return nil
            default:
                break
            }
            return event
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
