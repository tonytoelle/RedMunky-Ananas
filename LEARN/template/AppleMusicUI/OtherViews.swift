import SwiftUI

// ============================================
// MARK: - RadioView — TabView (paged carousel)
// ============================================
struct RadioView: View {
    @State private var selectedTab = 0
    
    let carouselItems = [
        ("TabView(.automatic)", "Page 0 Content", Color(red: 0.4, green: 0.2, blue: 0.1)),
        ("TabView Style Page", "Page 1 Content", Color(red: 0.1, green: 0.3, blue: 0.5)),
        ("Selection Binding", "Page 2 Content", Color(red: 0.1, green: 0.4, blue: 0.2)),
    ]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 24) {
                    
                    TabView(selection: $selectedTab) {
                        ForEach(carouselItems.indices, id: \.self) { index in
                            let item = carouselItems[index]
                            CarouselCardView(
                                title: item.0,
                                subtitle: item.1,
                                color: item.2
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.automatic)
                    .frame(height: 280)
                    
                    SectionHeaderView(title: "ScrollView(.horizontal) + LazyHStack", buttonLabel: "Button")
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(sampleAlbums) { album in
                                AlbumCardView(album: album)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Color.clear.frame(height: 100)
                }
                .padding(.bottom, 20)
            }
            
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background(Color(white: 0.1))
    }
}

// MARK: - CarouselCardView (ZStack + Text + overlay)
struct CarouselCardView: View {
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 0)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
            .padding(20)
            
            HStack {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "chevron.left").foregroundColor(.white).font(.system(size: 13, weight: .semibold)))
                    .padding(.leading, 12)
                
                Spacer()
                
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "chevron.right").foregroundColor(.white).font(.system(size: 13, weight: .semibold)))
                    .padding(.trailing, 12)
            }
        }
        .clipped()
    }
}

// ============================================
// MARK: - RecentlyAddedView — List dengan row
// ============================================
struct RecentlyAddedView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                List(sampleAlbums) { album in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(album.color)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white.opacity(0.7))
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("List Row (HStack)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text(album.title)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Row Item: ForEach")
                            .font(.system(size: 9))
                            .foregroundColor(.gray.opacity(0.5))
                            .italic()
                    }
                }
                .listStyle(.plain)
            }
            
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background(Color(white: 0.1))
        .navigationTitle("Recently Added")
    }
}

// ============================================
// MARK: - ArtistsView — LazyVGrid (2 kolom)
// ============================================
struct ArtistsView: View {
    let artists = [
        "GridItem(.adaptive)", "Min/Max bounds", "Flexible space", "Auto placement",
        "Circle shape", "Person icon", "Overlay image", "VStack spacing"
    ]
    let colors: [Color] = [.red, .blue, .purple, .green, .orange, .pink, .teal, .indigo]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120, maximum: 160))],
                    spacing: 20
                ) {
                    ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(colors[index % colors.count].opacity(0.7))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.largeTitle)
                                        .foregroundColor(.white.opacity(0.7))
                                )
                            
                            Text(artist)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(20)
                
                Color.clear.frame(height: 100)
            }
            
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background(Color(white: 0.1))
        .navigationTitle("Artists")
    }
}

// ============================================
// MARK: - AlbumsView — LazyVGrid (4 kolom)
// ============================================
struct AlbumsView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("LazyVGrid (columns: flexible, count: 4)")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                    
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                        spacing: 20
                    ) {
                        ForEach(sampleAlbums + sampleAlbums) { album in
                            AlbumCardView(album: album)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Color.clear.frame(height: 100)
                }
                .padding(.vertical, 20)
            }
            
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background(Color(white: 0.1))
        .navigationTitle("Albums")
    }
}

// ============================================
// MARK: - SongsView — Table / List dengan kolom
// ============================================
struct SongsView: View {
    let songs = [
        ("Column 1 (Title)", "Column 2 (Artist)", "Column 3 (Album)", "Col 4 (Time)"),
        ("Text components", "HStack alignment", "Divider line", "03:58"),
        ("Custom table", "List layout", "Column widths", "03:20"),
        ("Scroll indicators", "Padding settings", "Spacer alignment", "03:14"),
    ]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HStack {
                    Text("#").font(.caption).foregroundColor(.gray).frame(width: 30)
                    Text("Title (Text)").font(.caption).foregroundColor(.gray)
                    Spacer()
                    Text("Artist (Text)").font(.caption).foregroundColor(.gray).frame(width: 150)
                    Text("Album (Text)").font(.caption).foregroundColor(.gray).frame(width: 150)
                    Text("Time (Text)").font(.caption).foregroundColor(.gray).frame(width: 50)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(white: 0.15))
                
                Divider()
                
                List {
                    ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.0)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text(song.1)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(song.1)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 140, alignment: .leading)
                            
                            Text(song.2)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 140, alignment: .leading)
                            
                            Text(song.3)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
            
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background(Color(white: 0.1))
        .navigationTitle("Songs")
    }
}

// ============================================
// MARK: - iTunesStoreView — ZStack + Menu
// ============================================
struct iTunesStoreView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CarouselCardView(
                        title: "Carousel banner",
                        subtitle: "ZStack container",
                        color: Color(red: 0.4, green: 0.2, blue: 0.1)
                    )
                    .frame(height: 240)
                    
                    HStack {
                        Text("ScrollView + LazyHStack")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button("See All ›") {}
                            .foregroundColor(.red)
                            .buttonStyle(.plain)
                        
                        Menu("Menu (All Genres) ▾") {
                            Button("Pop (Menu Item)") {}
                            Button("Rock (Menu Item)") {}
                            Button("Hip-Hop (Menu Item)") {}
                            Divider()
                            Button("Submenu item") {}
                        }
                        .menuStyle(.borderlessButton)
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(sampleAlbums) { album in
                                AlbumCardView(album: album)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MUSIC QUICK LINKS (GRID)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(["Redeem (Button)", "Account (Button)", "Send Gift (Button)", "Support (Button)", "Apple Music 1 (Button)"], id: \.self) { link in
                                Button(link) {}
                                    .buttonStyle(.plain)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    Color.clear.frame(height: 100)
                }
                .padding(.bottom, 20)
            }
            
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background(Color(white: 0.1))
        .navigationTitle("iTunes Store")
    }
}

// ============================================
// MARK: - All Playlists View — Menu + Popover
// ============================================
struct AllPlaylistsView: View {
    @State private var showMenu = false
    @State private var selectedFilter = "Menu (All Playlists)"
    @State private var localSearchText = ""
    @FocusState private var isFilterFocused: Bool
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Top bar dengan Filter Search Field & Tombol Bulat Glass (Menu)
                HStack(spacing: 12) {
                    Spacer()
                    
                    // 1. Tombol Bulat Glass (Filter & Sort Menu) - diameter 28pt s.d. 32pt
                    Menu {
                        Button {
                            selectedFilter = "Menu (All Playlists)"
                        } label: {
                            if selectedFilter == "Menu (All Playlists)" {
                                Label("Menu (All Playlists)", systemImage: "checkmark")
                            } else {
                                Text("Menu (All Playlists)")
                            }
                        }
                        
                        Button("Only Favorites (Menu Item)") {
                            selectedFilter = "Only Favorites"
                        }
                        
                        Divider()
                        
                        Menu("Sort Options (Submenu) ›") {
                            Button("A to Z") {}
                            Button("Recently Added") {}
                            Button("Date Created") {}
                        }
                    } label: {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    
                    // 2. Search Bar Kanan Atas ("Find in All Playlists") - Filter Search Field / Capsule
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(isFilterFocused ? .red : .secondary)
                            .font(.system(size: 12))
                        
                        TextField("Find in All Playlists", text: $localSearchText)
                            .focused($isFilterFocused)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .tint(.red)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isFilterFocused ? Color.red : Color.clear, lineWidth: 1.2)
                    )
                    .frame(width: 200)
                    
                    // 3. Tombol Kapsul Tiga Titik + Chevron (More Actions Dropdown) dengan Efek Frosted Glass
                    Menu {
                        Button("Action Item 1") {}
                        Button("Action Item 2") {}
                        Divider()
                        Button("Cancel") {}
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(white: 0.12))
                
                Divider()
                
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("VStack Container")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    Text("Text components inside VStack\nEmpty state placeholder")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            }
            
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background(Color(white: 0.1))
        .navigationTitle("All Playlists")
    }
}

// ============================================
// MARK: - Reusable UI Components
// ============================================
struct SectionHeaderView: View {
    let title: String
    let buttonLabel: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(.white)
            Spacer()
            Button(buttonLabel) {}
                .foregroundColor(.red)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }
}
