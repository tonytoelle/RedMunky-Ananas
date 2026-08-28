import SwiftUI

// ============================================
// MARK: - Model (Enum untuk navigasi sidebar)
// ============================================
enum SidebarItem: String, CaseIterable, Identifiable {
    case search = "TextField + Picker"
    case home = "ScrollView + Grid"
    case radio = "TabView (Carousel)"
    case recentlyAdded = "List (.plain)"
    case artists = "LazyVGrid (.adaptive)"
    case albums = "LazyVGrid (.flexible)"
    case songs = "List (Table Layout)"
    case itunesStore = "Menu dropdown"
    case allPlaylists = "Submenu & Popover"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .home: return "house.fill"
        case .radio: return "antenna.radiowaves.left.and.right"
        case .recentlyAdded: return "clock"
        case .artists: return "music.mic"
        case .albums: return "square.stack"
        case .songs: return "music.note"
        case .itunesStore: return "bag"
        case .allPlaylists: return "square.grid.3x3.fill"
        }
    }
}

// ============================================
// MARK: - ContentView — Murni NavigationSplitView + Sidebar List Style
// ============================================
struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .home
    
    var body: some View {
        // NavigationSplitView: Bawaan native SwiftUI macOS
        NavigationSplitView {
            // ---- KOLOM KIRI: Sidebar ----
            List(selection: $selectedItem) {
                ForEach([SidebarItem.search, .home, .radio]) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
                
                Section("Library (Section)") {
                    ForEach([SidebarItem.recentlyAdded, .artists, .albums, .songs]) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
                
                Section("Store (Section)") {
                    Label(SidebarItem.itunesStore.rawValue, systemImage: SidebarItem.itunesStore.icon)
                        .tag(SidebarItem.itunesStore)
                }
                
                Section("Playlists (Section)") {
                    Label(SidebarItem.allPlaylists.rawValue, systemImage: SidebarItem.allPlaylists.icon)
                        .tag(SidebarItem.allPlaylists)
                }
            }
            .listStyle(.sidebar) // ← Rounded selection highlight, padding inset murni dari sistem operasi
            .safeAreaInset(edge: .bottom) {
                UserBadgeView()
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            .background(.ultraThinMaterial) // ← Efek kaca/blur vibrancy murni macOS
        } detail: {
            // ---- KOLOM KANAN: Detail / Main Content ----
            DetailView(selectedItem: selectedItem)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// ============================================
// MARK: - UserBadgeView — HStack + Circle
// ============================================
struct UserBadgeView: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 32, height: 32)
                
                Text("Z")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("HStack Container")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                Text("ZStack + Circle + Text")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// ============================================
// MARK: - DetailView — switch berdasarkan state
// ============================================
struct DetailView: View {
    let selectedItem: SidebarItem?
    
    var body: some View {
        ZStack {
            switch selectedItem {
            case .home, .none:
                HomeView()
            case .search:
                SearchView()
            case .radio:
                RadioView()
            case .recentlyAdded:
                RecentlyAddedView()
            case .artists:
                ArtistsView()
            case .albums:
                AlbumsView()
            case .songs:
                SongsView()
            case .itunesStore:
                iTunesStoreView()
            case .allPlaylists:
                AllPlaylistsView()
            }
        }
    }
}
