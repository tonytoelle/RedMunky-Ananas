# 04 - Arsitektur Swift Macro Engine (Mini KM Compact)

Dokumen ini adalah cetak biru teknis lengkap yang menyadur seluruh temuan dari Keyboard Maestro dan open-source engine ke dalam **Swift Macro Engine (SME)**.

---

## 1. Diagram Alur Kerja (End-to-End Architecture)

```
                       [ INPUT FOLDER ]
                /INPUT/ShortKing Documents/
                     ├── example.shortking
                     └── custom.shortking
                              │
                              ▼ (FSEvent / DispatchSource Watcher)
┌────────────────────────────────────────────────────────────────────────┐
│                     SWIFT MACRO ENGINE RUNNER                          │
│                                                                        │
│  1. ShortKingParser                                                    │
│     - Parsing TRIGGER: cmd+shift+k                                     │
│     - Parsing ACTION: click / drag / delay / type / press              │
│                                                                        │
│  2. Carbon HotKey Registry (Zero-Latency, No-Permission Required)      │
│     - InstallEventHandler(GetApplicationEventTarget())                 │
│     - RegisterEventHotKey(keyCode, modifiers, hotKeyID, ...)           │
│     - Menghapus & mendaftarkan ulang saat file berubah (Dynamic)       │
│                                                                        │
│  3. Action Dispatcher (Background Thread)                              │
│     - Saat hotkey ditekan -> Callback C dipanggil                      │
│     - Thread UI tidak freeze                                           │
│     - InputSimulator mengeksekusi mouse/keyboard secara berurutan      │
└────────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ (Live Sync & Test Run)
┌────────────────────────────────────────────────────────────────────────┐
│                   KEYBOARD MAESTRO 3-COLUMN GUI                        │
│  [Groups Column]    │   [Macros List Column]   │ [Visual Flow Editor]  │
│  • ShortKing Docs   │   • example.shortking    │ • HotKey Badge        │
│  • Global Macros    │   • new_macro.shortking  │ • Action Cards        │
│                     │                          │ • Test Run & Save     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Poin Perubahan Kunci (Upgrade dari Versi Lama)

| Komponen | Versi Lama (Bermasalah) | Versi Baru (Mini KM) |
| :--- | :--- | :--- |
| **Pencegat Shortcut** | `CGEventTap` (gagal jika izin belum penuh atau timeout) | **Carbon `RegisterEventHotKey`** (100% instan, zero-delay, override sempurna) |
| **Pemutakhiran File** | Statis / Polling lambat | **FSEvent Watcher + Dynamic Re-registering HotKeys** |
| **Eksekusi Aksi** | Sinkron di main thread | **Asinkron di `DispatchQueue.global()`** |
| **Simulasi Mouse** | Gerakan instan 1 step | **Interpolasi 15-step Smooth Dragging** |
| **GUI Editor** | Menu Bar dasar | **3-Kolom Keyboard Maestro Klasik** |

---

## 3. Format File `.shortking` yang Didukung

```text
# Trigger kombinasi tombol
TRIGGER: cmd+shift+k

# 1. Klik Kiri di koordinat (X=400, Y=300)
ACTION: click 400 300

# 2. Jeda waktu 300ms
ACTION: delay 300

# 3. Drag halus dari titik awal ke titik tujuan
ACTION: drag 400 300 to 700 300

# 4. Ketik teks otomatis dengan Unicode
ACTION: type "ShortKing Ready!"

# 5. Tekan tombol khusus keyboard (enter, tab, esc, space, a-z)
ACTION: press enter

# 6. Teruskan/Remap ke shortcut lain
ACTION: press_shortcut ctrl+opt+cmd+p
```
