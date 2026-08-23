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
    
    static let allActions: [SearchableActionDef] = [
        .init(title: "Path", icon: "point.topleft.down.to.point.bottomright.curvepath.fill", color: Color(red: 0.65, green: 0.25, blue: 0.85)),
        .init(title: "Left Click", icon: "cursorarrow.click", color: Color(red: 0.08, green: 0.45, blue: 0.82)),
        .init(title: "Right Click", icon: "cursorarrow.click", color: Color(red: 0.04, green: 0.52, blue: 0.54)),
        .init(title: "Drag", icon: "hand.draw", color: Color(red: 0.52, green: 0.22, blue: 0.75)),
        .init(title: "Move Cursor", icon: "cursorarrow.motionlines", color: Color(red: 0.28, green: 0.52, blue: 0.92)),
        .init(title: "Delay", icon: "timer", color: Color(red: 0.88, green: 0.42, blue: 0.04)),
        .init(title: "Text", icon: "text.cursor", color: Color(red: 0.12, green: 0.58, blue: 0.24)),
        .init(title: "Key", icon: "keyboard", color: Color(red: 0.32, green: 0.28, blue: 0.72)),
        .init(title: "Do Again", icon: "arrow.counterclockwise", color: Color(red: 0.12, green: 0.58, blue: 0.65)),
        .init(title: "Group", icon: "folder", color: Color.orange),
        .init(title: "Custom", icon: "terminal", color: Color.pink),
        .init(title: "Open File", icon: "arrow.up.forward.app", color: Color(red: 0.1, green: 0.65, blue: 0.6)),
        .init(title: "Vol Up", icon: "speaker.wave.3.fill", color: Color.blue),
        .init(title: "Vol Down", icon: "speaker.wave.1.fill", color: Color.blue),
        .init(title: "Brit Up", icon: "sun.max.fill", color: Color.orange),
        .init(title: "Brit Down", icon: "sun.min.fill", color: Color.orange),
    ]
}

// ==========================================
// MARK: - Spotlight-Style Search Bar
// ==========================================
struct SpotlightSearchBar: View {
    let placeholder: String
    let items: [SearchableActionDef]
    let onSelect: (SearchableActionDef) -> Void
    
    @State private var query: String = ""
    @State private var isShowingDropdown: Bool = false
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool
    
    var filteredItems: [(item: SearchableActionDef, score: Int)] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return items.map { ($0, 0) }
        }
        return items.compactMap { item in
            let result = fuzzyMatch(query, in: item.title)
            return result.matches ? (item, result.score) : nil
        }.sorted { $0.score < $1.score }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFocused)
                    .onSubmit {
                        if !filteredItems.isEmpty {
                            let idx = min(selectedIndex, filteredItems.count - 1)
                            onSelect(filteredItems[idx].item)
                            query = ""
                            isShowingDropdown = false
                            isFocused = false
                        }
                    }
                    .onChange(of: query) { _ in
                        isShowingDropdown = !query.isEmpty
                        selectedIndex = 0
                    }
                if !query.isEmpty {
                    Button { query = ""; isShowingDropdown = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(white: 0.22))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            
            if isShowingDropdown && !filteredItems.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(filteredItems.prefix(8).enumerated()), id: \.element.item.id) { idx, entry in
                        Button {
                            onSelect(entry.item)
                            query = ""
                            isShowingDropdown = false
                            isFocused = false
                        } label: {
                            HStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(entry.item.color)
                                        .frame(width: 22, height: 22)
                                    Image(systemName: entry.item.icon)
                                        .foregroundColor(.white)
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                Text(entry.item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(idx == selectedIndex ? Color.white.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .background(Color(white: 0.20))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.top, 4)
            }
        }
    }
}

// ==========================================
// MARK: - Macro Inspector (Right Column - System Settings Canvas)
// ==========================================
