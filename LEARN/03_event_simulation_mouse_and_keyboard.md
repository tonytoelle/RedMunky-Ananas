# 03 - Simulasi Event Mouse & Keyboard Tingkat Lanjut

Dokumen ini menjelaskan teknik simulasi input mouse (klik & drag) dan keyboard di macOS agar tidak gagal saat dieksekusi ke aplikasi lain.

---

## 1. Sistem Koordinat Layar di macOS (Quartz vs. Cocoa)

Salah satu penyebab umum klik atau drag salah sasaran di macOS adalah perbedaan sistem koordinat:

```
┌────────────────────────────────────────────────────────┐ (0, 0) Quartz Top-Left
│  QUARTZ COORDINATES (CGEvent)                          │
│  • (0,0) berada di POJOK KIRI ATAS Layar Utama         │
│  • Nilai Y membesar ke ARAH BAWAH                      │
│  • SAMA persis dengan screenshot Cmd+Shift+4           │
├────────────────────────────────────────────────────────┤
│  COCOA COORDINATES (NSView / AppKit)                   │
│  • (0,0) berada di POJOK KIRI BAWAH Layar Utama        │
│  • Nilai Y membesar ke ARAH ATAS                       │
└────────────────────────────────────────────────────────┘
```

> **Aturan Emas:**
> Saat menggunakan `CGEvent(mouseEventSource: ...)` untuk automasi, gunakan **Sistem Koordinat Quartz (Pojok Kiri Atas = 0,0)**. Angka koordinat yang didapatkan dari screenshot bawaan macOS (`Cmd + Shift + 4`) adalah koordinat Quartz yang valid dan siap pakai langsung!

---

## 2. Teknik Simulasi Klik Mouse yang Benar

Aplikasi modern (seperti Chrome, Photoshop, Finder) membutuhkan jeda waktu fisik (*hardware latency simulation*) agar mendeteksi klik dengan benar. Jika event `mouseDown` dan `mouseUp` dikirimkan secara instan tanpa jeda, sistem operasi seringkali mengabaikannya.

```swift
func simulateClick(at point: CGPoint, button: CGMouseButton = .left) {
    let source = CGEventSource(stateID: .hidSystemState)
    let downType: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
    let upType: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp

    // 1. Kirim Mouse Down
    guard let downEvent = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
          let upEvent = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button) else { return }

    downEvent.post(tap: .cghidEventTap)
    
    // 2. Beri jeda 20ms agar aplikasi mendeteksi penekanan
    usleep(20000) 
    
    // 3. Kirim Mouse Up
    upEvent.post(tap: .cghidEventTap)
    
    // 4. Jeda penutup
    usleep(20000)
}
```

---

## 3. Teknik Simulasi Drag Mouse yang Halus (Smooth Interpolation)

Banyak aplikasi (seperti Finder saat memindahkan file, atau Canvas UI) **TIDAK AKAN** mendeteksi drag jika kursor langsung melompat dari titik A ke titik B dalam satu frame.

Kita harus melakukan **interpolasi koordinat (multistep drag)**:

```swift
func simulateDrag(from startPoint: CGPoint, to endPoint: CGPoint, steps: Int = 15) {
    let source = CGEventSource(stateID: .hidSystemState)

    // 1. Mouse Down di titik awal
    let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: startPoint, mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    usleep(40000)

    // 2. Gerakkan kursor bertahap (interpolasi linear)
    for step in 1...steps {
        let fraction = CGFloat(step) / CGFloat(steps)
        let currentX = startPoint.x + (endPoint.x - startPoint.x) * fraction
        let currentY = startPoint.y + (endPoint.y - startPoint.y) * fraction
        let currentPoint = CGPoint(x: currentX, y: currentY)

        let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: currentPoint, mouseButton: .left)
        drag?.post(tap: .cghidEventTap)
        usleep(10000) // 10ms per langkah
    }

    usleep(30000)

    // 3. Mouse Up di titik akhir
    let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: endPoint, mouseButton: .left)
    up?.post(tap: .cghidEventTap)
    usleep(30000)
}
```

---

## 4. Pengetikan Teks Cepat Menggunakan Unicode String

Dibandingkan menekan virtual keycode per huruf (yang rentan terhadap layout keyboard qwerty/dvorak/colemak), cara terbaik untuk mengetik teks otomatis adalah menyuntikkan karakter Unicode secara langsung:

```swift
func simulateTypeText(_ text: String) {
    let source = CGEventSource(stateID: .hidSystemState)
    
    for character in text.utf16 {
        var char = character
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)

        down?.post(tap: .cghidEventTap)
        usleep(4000)
        up?.post(tap: .cghidEventTap)
        usleep(4000)
    }
}
```
