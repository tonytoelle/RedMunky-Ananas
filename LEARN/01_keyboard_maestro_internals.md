# 01 - Bedah Arsitektur Keyboard Maestro (KM Deep Dive)

Dokumen ini membedah arsitektur internal ("jeroan") dari **Keyboard Maestro (KM)** di macOS berdasarkan riset teknis, dokumentasi resmi, dan pola implementasi sistem automasi macOS.

---

## 1. Arsitektur Dua Proses (Engine vs. Editor)

Salah satu prinsip desain paling penting dari Keyboard Maestro adalah **pemisahan proses** menjadi dua aplikasi independen:

```
┌────────────────────────────────────────────────────────┐
│               macOS WindowServer                       │
└───────────────────▲────────────────────────────────────┘
                    │ (Carbon HotKeys & Event Posting)
┌───────────────────┴────────────────────────────────────┐
│      1. Keyboard Maestro Engine (Background Daemon)    │
│  - Berjalan terus menerus di Menu Bar / Latar Belakang │
│  - Mencegat HotKey (Carbon API: RegisterEventHotKey)   │
│  - Mengeksekusi Action Runner (Mouse Click, Drag, dll) │
│  - Sangat ringan, stabil, & hemat memori               │
└───────────────────▲────────────────────────────────────┘
                    │ (IPC / File System Sync)
┌───────────────────┴────────────────────────────────────┐
│         2. Keyboard Maestro Editor (GUI App)           │
│  - Layout 3-Kolom (Groups -> Macros -> Inspector)      │
│  - Tempat user menyusun makro & mengatur aksi visual   │
│  - Bisa ditutup kapan saja tanpa mematikan Engine      │
└────────────────────────────────────────────────────────┘
```

### Mengapa Dipisah?
* Jika GUI Editor ditutup atau mengalami *crash*, automasi user tidak akan terputus karena Engine tetap hidup di latar belakang.
* Engine tidak membebani kartu grafis atau CPU dengan rendering antarmuka saat user sedang bekerja.

---

## 2. Cara Keyboard Maestro Menangkap Shortcut (Trigger Engine)

Di macOS, ada dua cara utama menangkap tombol keyboard secara global:

| Fitur / Parameter | Carbon `RegisterEventHotKey` | Quartz `CGEventTap` |
| :--- | :--- | :--- |
| **Level API** | WindowServer Level (Lebih Tinggi) | CoreGraphics HID Level (Sangat Rendah) |
| **Izin Aksesibilitas** | **TIDAK BUTUH** izin khusus untuk mendengarkan hotkey | **WAJIB** Izin Aksesibilitas + Input Monitoring |
| **Perilaku Override** | **Otomatis di-block/dikonsumsi** (aplikasi lain tidak akan menerima tombol) | Harus me-return `nil` di callback C |
| **Stabilitas & Timeout**| Sangat stabil, tidak pernah di-disable oleh macOS | Bisa dinonaktifkan otomatis oleh OS jika callback lambat |
| **Penggunaan di KM** | **Digunakan untuk seluruh Shortcut / HotKey Utama** | Digunakan untuk Text Expansion & Pemantauan Mouse |

> **Temuan Kritis:**
> Alasan mengapa penekanan shortcut gagal pada versi awal kita adalah karena kita hanya mengandalkan `CGEventTap`. Jika `CGEventTap` belum mendapatkan izin ganda (*Accessibility + Input Monitoring*) atau terjadi *timeout* di thread macOS, maka seluruh tombol menjadi bisu / tidak merespons.
>
> **Solusi Standar Keyboard Maestro:** Gunakan **Carbon `RegisterEventHotKey`** sebagai tulang punggung penangkap shortcut global!

---

## 3. Cara Keyboard Maestro Menyimulasikan Mouse & Keyboard (Action Runner)

Ketika sebuah makro dipicu, Keyboard Maestro mengeksekusi urutan aksi dengan API berikut:

1. **Mouse Click & Drag:**
   * Menggunakan Quartz Event Services: `CGEvent(mouseEventSource: ...)` lalu mem-posting event menggunakan `CGEvent.post(tap: .cghidEventTap)`.
   * Memerlukan urutan state: `leftMouseDown` -> delay singkat -> `leftMouseDragged` (interpolasi koordinat bertahap) -> delay -> `leftMouseUp`.
2. **Keystroke & Text Typing:**
   * Untuk teks cepat: `CGEvent.keyboardSetUnicodeString` untuk memasukkan string Unicode utuh tanpa harus menekan tombol satu per satu.
   * Untuk tombol khusus (Enter, Tab, Esc): Mengirimkan `keyDown` + `keyUp` virtual keycode.
3. **AppleScript & Shell Script Execution:**
   * Menggunakan `NSAppleScript` atau `Process` (CLI executor) untuk mengontrol aplikasi pihak ketiga yang mendukung Apple Events (misalnya Safari, Finder, Chrome).

---

## 4. Pelajaran untuk Swift Macro Engine (Mini KM)

Untuk membuat **Swift Macro Engine (SME) / Mini KM** yang tangguh, kita harus mengadopsi pola ini:
1. Ganti penangkap hotkey menjadi **Carbon `RegisterEventHotKey`**.
2. Tetap jalankan simulasi mouse/keyboard dengan **`CGEvent.post`**.
3. Gunakan arsitektur sinkronisasi file real-time (`.shortking` files) sehingga file teks langsung diterjemahkan menjadi pendaftaran Carbon HotKey aktif secara dinamis.
