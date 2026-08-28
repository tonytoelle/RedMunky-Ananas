import SwiftUI

// ============================================
// MARK: - PlayerBarView — Floating Glass Player Bar
// ============================================
struct PlayerBarView: View {
    @State private var isPlaying = false
    @State private var progress: Double = 0.3
    @State private var volume: Double = 0.7
    @State private var isShuffle = false
    @State private var isRepeat = false
    
    var body: some View {
        HStack(spacing: 0) {
            
            // ---- KIRI: Kontrol Playback (HStack) ----
            HStack(spacing: 20) {
                PlayerButton(icon: "shuffle", label: "Button") {
                    isShuffle.toggle()
                }
                .foregroundColor(isShuffle ? .red : .gray)
                
                PlayerButton(icon: "backward.fill", label: "Button") {}
                    .foregroundColor(.white)
                
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                
                PlayerButton(icon: "forward.fill", label: "Button") {}
                    .foregroundColor(.white)
                
                PlayerButton(icon: "repeat", label: "Button") {
                    isRepeat.toggle()
                }
                .foregroundColor(isRepeat ? .red : .gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
            
            // ---- TENGAH: Apple Logo / Title Text ----
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "applelogo")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                
                Text("Floating Glass Player Bar (.ultraThinMaterial)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer()
            
            // ---- KANAN: Kontrol Volume + Ikon ----
            HStack(spacing: 16) {
                PlayerButton(icon: "quote.bubble", label: "Button") {}
                    .foregroundColor(.gray)
                
                PlayerButton(icon: "list.bullet", label: "Button") {}
                    .foregroundColor(.gray)
                
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    
                    Slider(value: $volume, in: 0...1)
                        .frame(width: 80)
                        .tint(.red)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 24)
        }
        .frame(height: 64)
        // Efek Floating & Glass (ultraThinMaterial + ClipShape + Shadow)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
    }
}

// MARK: - PlayerButton
struct PlayerButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
        }
        .buttonStyle(.plain)
    }
}
