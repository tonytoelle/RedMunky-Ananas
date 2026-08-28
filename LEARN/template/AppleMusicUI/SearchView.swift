import SwiftUI

// ============================================
// MARK: - SearchView — TextField + Custom Segmented Toggle + Grid
// ============================================
struct SearchView: View {
    @State private var searchText = ""
    @State private var selectedTab = 0
    @FocusState private var isSearchFocused: Bool
    
    @Namespace private var animationNamespace
    
    let tabs = ["Library", "Apple Music", "iTunes Store"]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        Color.clear.frame(height: 70)
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "applelogo")
                                    .foregroundColor(.white)
                                    .font(.title2.bold())
                                Text("HStack")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                            }
                            
                            Divider()
                                .frame(height: 30)
                                .background(Color.white.opacity(0.3))
                            
                            VStack(alignment: .leading) {
                                Text("VStack Header Title")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("VStack Subtitle label content")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            Spacer()
                            
                            Button("Button(SearchPromoButtonStyle)") {}
                                .buttonStyle(SearchPromoButtonStyle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.8))
                        )
                        .padding(.horizontal, 20)
                        
                        Text("LazyVGrid (columns: repeating, count: 4)")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                            spacing: 12
                        ) {
                            ForEach(sampleCategories) { category in
                                CategoryCardView(category: category)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Color.clear.frame(height: 100)
                    }
                    .padding(.vertical, 20)
                }
            }
            .background(Color(white: 0.1)) // Mengembalikan warna latar belakang murni panel kanan
            
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
                                                    .matchedGeometryEffect(id: "activeTabBadge", in: animationNamespace)
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
    }
}

struct SearchPromoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.white.opacity(0.8) : Color.white)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
