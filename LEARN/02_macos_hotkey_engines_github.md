# 02 - Bedah Jeroan Engine Open-Source Populer di GitHub

Berdasarkan penelusuran kode sumber (*source code*) pada proyek-proyek automasi dan window manager open-source paling populer di macOS (seperti **soffes/HotKey**, **Hammerspoon**, **Maccy**, **Amethyst**, dan **Clipy**), berikut adalah temuan mendalam mengenai cara mereka mengimplementasikan HotKey dan Automasi:

---

## 1. Library `soffes/HotKey` (Standar Industri Swift untuk HotKey)

Repository GitHub: `soffes/HotKey`
Digunakan oleh ratusan aplikasi macOS modern untuk menangkap global hotkey.

### Bagaimana Kode di Dalamnya Bekerja?
`soffes/HotKey` membungkus C-API Carbon ke dalam struktur Swift yang elegan:

```swift
import Carbon
import Cocoa

// 1. C-Callback Handler yang dipanggil oleh macOS saat HotKey ditekan
private func hotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }
    
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    
    if status == noErr {
        // Panggil closure Swift yang sesuai dengan ID hotkey
        HotKeyCenter.shared.dispatch(hotKeyID: hotKeyID.id)
        return noErr
    }
    
    return OSStatus(eventNotHandledErr)
}
```

### Cara Mendaftarkan HotKey:
```swift
// Pasang EventHandler satu kali ke Application Event Target
var eventType = EventTypeSpec(
    eventClass: OSType(kEventClassKeyboard),
    eventKind: UInt32(kEventHotKeyPressed)
)
InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, nil)

// Daftarkan hotkey spesifik (misal: Cmd + Shift + K)
var hotKeyRef: EventHotKeyRef?
let hotKeyID = EventHotKeyID(signature: OSType(0x534B494E), id: 1) // "SKIN"
let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
let keyCode: UInt32 = 40 // Tombol K

RegisterEventHotKey(
    keyCode,
    modifiers,
    hotKeyID,
    GetApplicationEventTarget(),
    0,
    &hotKeyRef
)
```

---

## 2. Hammerspoon (`hs.hotkey` & `hs.eventtap`)

Hammerspoon adalah tool automasi paling fleksibel di macOS. Dalam basis kodenya di GitHub (`Hammerspoon/hammerspoon`):

* **`hs.hotkey`**: Menggunakan **Carbon `RegisterEventHotKey`** untuk semua shortcut statis (`cmd+shift+k`). Keuntungannya instan, tidak lag, dan tidak butuh izin aksesibilitas untuk deteksi.
* **`hs.eventtap`**: Menggunakan **`CGEventTapCreate`** HANYA jika pengguna butuh membuat:
  1. *Modal Keybinding* (misal mode Vim: menekan `j`, `k` berpindah baris).
  2. *Text Expansion / Snippet* (mendeteksi ketika user mengetik string tertentu seperti `:email:` lalu menggantinya).

---

## 3. Perbandingan 3 Pendekatan di macOS

| Metode | Kelebihan | Kelemahan | Kapan Digunakan? |
| :--- | :--- | :--- | :--- |
| **1. Carbon `RegisterEventHotKey`** | • 100% Reliabel<br>• Tidak butuh izin Accessibility<br>• Otomatis override & blok event<br>• Zero-latency | • Tidak bisa mendeteksi tombol biasa tanpa modifier (harus ada kombinasi) | **Pilihan Utama untuk ShortKing / Mini KM** |
| **2. CoreGraphics `CGEventTap`** | • Bisa mendeteksi semua ketikan keyboard & klik mouse mentah<br>• Bisa deteksi urutan teks | • Wajib izin Accessibility + Input Monitoring<br>• Bisa timeout / di-kill oleh OS<br>• Kompleks | Digunakan untuk Text Snippet / Keylogger |
| **3. `NSEvent.addGlobalMonitor`** | • Kode Swift murni Cocoa | • **TIDAK BISA** meng-override (event tetap tembus ke aplikasi lain)<br>• Pasif | Digunakan untuk analytics / telemetry saja |

---

## 4. Kesimpulan untuk Swift Macro Engine
Kita akan menerapkan implementasi **Carbon Event Handler** murni di dalam Swift tanpa dependensi eksternal, sehingga binary tetap mandiri (*standalone*), super cepat, dan hotkey langsung menyala seketika!
