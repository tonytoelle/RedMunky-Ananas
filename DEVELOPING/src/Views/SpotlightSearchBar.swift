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
    
    static let allActions: [SearchableActionDef] = [
        .init(title: "Path", icon: "point.topleft.down.to.point.bottomright.curvepath.fill", color: Color(red: 0.65, green: 0.25, blue: 0.85), category: "Utility"),
        .init(title: "Left Click", icon: "cursorarrow.click", color: Color(red: 0.08, green: 0.45, blue: 0.82), category: "Mouse"),
        .init(title: "Right Click", icon: "cursorarrow.click", color: Color(red: 0.04, green: 0.52, blue: 0.54), category: "Mouse"),
        .init(title: "Drag", icon: "hand.draw", color: Color(red: 0.52, green: 0.22, blue: 0.75), category: "Mouse"),
        .init(title: "Move Cursor", icon: "cursorarrow.motionlines", color: Color(red: 0.28, green: 0.52, blue: 0.92), category: "Mouse"),
        .init(title: "Delay", icon: "timer", color: Color(red: 0.88, green: 0.42, blue: 0.04), category: "Utility"),
        .init(title: "Text", icon: "text.cursor", color: Color(red: 0.12, green: 0.58, blue: 0.24), category: "Keyboard"),
        .init(title: "Key", icon: "keyboard", color: Color(red: 0.32, green: 0.28, blue: 0.72), category: "Keyboard"),
        .init(title: "Do Again", icon: "arrow.counterclockwise", color: Color(red: 0.12, green: 0.58, blue: 0.65), category: "Utility"),
        .init(title: "Group", icon: "folder", color: Color.orange, category: "Utility"),
        .init(title: "Custom", icon: "terminal", color: Color.pink, category: "Utility"),
        .init(title: "Open File", icon: "arrow.up.forward.app", color: Color(red: 0.1, green: 0.65, blue: 0.6), category: "Utility"),
        .init(title: "Vol Up", icon: "speaker.wave.3.fill", color: Color.blue, category: "System"),
        .init(title: "Vol Down", icon: "speaker.wave.1.fill", color: Color.blue, category: "System"),
        .init(title: "Brit Up", icon: "sun.max.fill", color: Color.orange, category: "System"),
        .init(title: "Brit Down", icon: "sun.min.fill", color: Color.orange, category: "System"),
        .init(title: "Window Transform", icon: "macwindow", color: Color(red: 0.1, green: 0.58, blue: 0.8), category: "Utility"),
        .init(title: "Origin", icon: "scope", color: Color(red: 0.85, green: 0.15, blue: 0.45), category: "Mouse"),
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
        let itemWidth: CGFloat = 72
        let spacing: CGFloat = 10
        let cols = max(1, Int((availableWidth + spacing) / (itemWidth + spacing)))
        return cols
    }
    
    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: columnsCount)
    }
    
    var filteredItems: [(item: SearchableActionDef, score: Int)] {
        let matchingCategoryItems = items.filter { item in
            activeCategory == "All" || item.category == activeCategory
        }
        
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return matchingCategoryItems.map { ($0, 0) }
        }
        
        return matchingCategoryItems.compactMap { item in
            let result = fuzzyMatch(query, in: item.title)
            return result.matches ? (item, result.score) : nil
        }.sorted { $0.score < $1.score }
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
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(visibleItems, id: \.element.item.id) { idx, entry in
                                Button {
                                    onSelect(entry.item)
                                    query = ""
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(entry.item.color)
                                                .frame(width: 38, height: 38)
                                            Image(systemName: entry.item.icon)
                                                .foregroundColor(.white)
                                                .font(.system(size: 15, weight: .semibold))
                                        }
                                        
                                        Text(entry.item.title)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                        
                                        Text(entry.item.category)
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(6)
                                    .frame(width: 72, height: 76)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill((store.isGridFocused && idx == store.gridSelectedIndex) || idx == selectedIndex ? Color.white.opacity(0.12) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(store.isGridFocused && idx == store.gridSelectedIndex ? Color.accentColor : Color.clear, lineWidth: 1.5)
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
            let idx = min(selectedIndex, itemsCount - 1)
            onSelect(visibleItems[idx].element.item)
            query = ""
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
