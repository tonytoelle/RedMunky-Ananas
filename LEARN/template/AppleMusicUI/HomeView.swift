import SwiftUI

// ============================================
// MARK: - HomeView — ScrollView + VStack + Grid
// ============================================
struct HomeView: View {
    @State private var searchText = ""
    @State private var selectedTab = 0
    @FocusState private var isSearchFocused: Bool
    
    @Namespace private var animationNamespace
    
    let tabs = ["Library", "Apple Music", "iTunes Store"]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    Color.clear.frame(height: 70)
                    
                    PromoBannerView()
                    
                    HStack {
                        Text("ScrollView + LazyHStack")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button("Button (See All ›)") {
                            // action kosong
                        }
                        .foregroundColor(.red)
                        .buttonStyle(.plain)
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
                    
                    Text("LazyVGrid (columns: 4)")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                    
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ],
                        spacing: 12
                    ) {
                        ForEach(sampleCategories) { category in
                            CategoryCardView(category: category)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Color.clear.frame(height: 100)
                }
                .padding(.vertical, 24)
            }
            
            // ---- Efek Header Blur Fade ----
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(isSearchFocused ? .red : .gray)
                            .font(.system(size: 13, weight: .semibold))
                        
                        TextField("TextField (@FocusState)", text: $searchText)
                            .focused($isSearchFocused)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .tint(.red)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSearchFocused ? Color.red : Color.clear, lineWidth: 1.5)
                    )
                    .frame(maxWidth: .infinity)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<tabs.count, id: \.self) { index in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedTab = index
                                }
                            } label: {
                                Text(tabs[index])
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(selectedTab == index ? .white : .secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 5)
                                    .background(
                                        ZStack {
                                            if selectedTab == index {
                                                Capsule()
                                                    .fill(Color.white.opacity(0.22))
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(
                                                                LinearGradient(
                                                                    colors: [
                                                                        Color.white.opacity(0.45),
                                                                        Color.white.opacity(0.05)
                                                                    ],
                                                                    startPoint: .top,
                                                                    endPoint: .bottom
                                                                ),
                                                                lineWidth: 0.8
                                                            )
                                                    )
                                                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                                                    .matchedGeometryEffect(id: "homeTabBadge", in: animationNamespace)
                                            }
                                        }
                                    )
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .frame(width: 320)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black, location: 0.7),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
            .ignoresSafeArea(.container, edges: .top)
            
            PlayerBarView()
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background(Color(white: 0.1))
    }
}

// MARK: - Promo Banner
struct PromoBannerView: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.8, green: 0.1, blue: 0.1), Color(red: 0.6, green: 0.05, blue: 0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 200)
            
            VStack(alignment: .center, spacing: 8) {
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                    Text("LinearGradient")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("ZStack (tumpukan view di atas gradient)")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
                
                Text("RoundedRectangle(cornerRadius: 12)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - AlbumCardView
struct AlbumCardView: View {
    let album: SampleAlbum
    @State private var isHovered = false
    
    var body: some View {
        Button {
            // action kosong
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(album.color)
                    .frame(width: 140, height: 140)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.5))
                    )
                    .scaleEffect(isHovered ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                
                Text(album.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(album.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - CategoryCardView
struct CategoryCardView: View {
    let category: SampleCategory
    @State private var isPressed = false
    
    var body: some View {
        Button {
            // action
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(category.color)
                    .frame(height: 110)
                
                Text(category.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Sample Data Models
struct SampleAlbum: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let color: Color
}

struct SampleCategory: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
}

// MARK: - Sample Data
let sampleAlbums: [SampleAlbum] = [
    SampleAlbum(title: "AsyncImage / Rec", artist: "HStack item", color: Color(red: 0.7, green: 0.3, blue: 0.3)),
    SampleAlbum(title: "Button (Plain)", artist: "VStack item", color: Color(red: 0.8, green: 0.6, blue: 0.1)),
    SampleAlbum(title: "Text Row", artist: "VStack item", color: Color(red: 0.3, green: 0.3, blue: 0.3)),
    SampleAlbum(title: "ScaleEffect", artist: "OnHover state", color: Color(red: 0.1, green: 0.6, blue: 0.5)),
    SampleAlbum(title: "Frame (Width/Height)", artist: "Image item", color: Color(red: 0.4, green: 0.1, blue: 0.7)),
]

let sampleCategories: [SampleCategory] = [
    SampleCategory(name: "GridItem [0]", color: Color(red: 0.7, green: 0.2, blue: 0.2)),
    SampleCategory(name: "GridItem [1]", color: Color(red: 0.2, green: 0.3, blue: 0.7)),
    SampleCategory(name: "GridItem [2]", color: Color(red: 0.7, green: 0.5, blue: 0.6)),
    SampleCategory(name: "GridItem [3]", color: Color(red: 0.7, green: 0.4, blue: 0.5)),
    SampleCategory(name: "RoundedRectangle", color: Color(red: 0.5, green: 0.5, blue: 0.1)),
    SampleCategory(name: "ScaleEffect", color: Color(red: 0.7, green: 0.4, blue: 0.1)),
    SampleCategory(name: "DragGesture", color: Color(red: 0.4, green: 0.2, blue: 0.6)),
    SampleCategory(name: "Button(Plain)", color: Color(red: 0.3, green: 0.4, blue: 0.7)),
    SampleCategory(name: "ZStack container", color: Color(red: 0.1, green: 0.6, blue: 0.4)),
    SampleCategory(name: "GridSpacing: 12", color: Color(red: 0.4, green: 0.4, blue: 0.1)),
    SampleCategory(name: "SimultaneousGesture", color: Color(red: 0.7, green: 0.2, blue: 0.3)),
    SampleCategory(name: "Color.red fill", color: Color(red: 0.7, green: 0.1, blue: 0.1)),
]
