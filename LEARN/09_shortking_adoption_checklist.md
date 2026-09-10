# 09 - Checklist Penyaduran dan Roadmap ShortKing

Dokumen ini adalah daftar ide pengembangan ShortKing setelah membandingkan arsitektur saat ini dengan Keyboard Maestro dan beberapa aplikasi automation native macOS. Tujuannya bukan menyalin semua fitur, melainkan memilih fondasi yang membuat ShortKing lebih compact, cepat, stabil, dan mudah dikembangkan.

## Cara memakai checklist

- `[x]` sudah tersedia atau baru selesai diterapkan.
- `[ ]` belum dikerjakan.
- `P0` fondasi/stabilitas yang sebaiknya dikerjakan dahulu.
- `P1` peningkatan bernilai tinggi.
- `P2` fitur lanjutan setelah fondasi stabil.
- `HINDARI` tidak cocok dengan identitas compact ShortKing saat ini.

Untuk memilih pekerjaan berikutnya, utamakan urutan: stabilitas → kecepatan penggunaan → kemampuan macro → integrasi tambahan.

## Identitas produk yang harus dipertahankan

- [x] Macro disimpan sebagai file `.shortking` yang mudah dibaca manusia.
- [x] Native Swift, SwiftUI, dan AppKit tanpa Electron.
- [x] Build langsung melalui `swiftc`, tanpa kewajiban Xcode project.
- [x] Tidak memakai database hanya untuk menyimpan macro sederhana.
- [x] Global hotkey menggunakan Carbon yang ringan.
- [x] Input simulation menggunakan Quartz/CoreGraphics.
- [ ] P0 Tetapkan anggaran performa: waktu startup, idle memory, dan waktu respons hotkey.
- [ ] P0 Dokumentasikan prinsip: fitur baru harus opsional dan tidak menambah kerja ketika idle.
- [ ] P1 Tambahkan halaman “Why ShortKing” di dokumentasi agar arah produk tidak melebar tanpa kontrol.

## A. Runtime dan stabilitas

- [x] Satu pintu eksekusi melalui `MacroRuntime`.
- [x] Macro dijalankan pada dedicated serial queue agar tidak berebut mouse dan keyboard.
- [x] Emergency stop tersedia melalui `⌘⌃⇧X`.
- [x] Modifier dilepaskan saat emergency stop.
- [ ] P0 Ubah cancellation flag menjadi thread-safe, bukan mutable static Boolean biasa.
- [ ] P0 Pastikan left/right/middle mouse-up dikirim pada semua jalur cancel dan error.
- [ ] P0 Pastikan Cmd, Shift, Option, Control, dan Fn tidak tertinggal dalam posisi down.
- [ ] P0 Buat cancellable delay helper untuk menggantikan pengulangan `usleep` manual.
- [ ] P0 Berikan timeout pada shell/custom action.
- [ ] P0 Saat custom process dibatalkan, hentikan child process dengan benar.
- [ ] P0 Tentukan policy queue: macro baru menunggu, menggantikan macro lama, atau ditolak.
- [ ] P1 Tambahkan status runtime: idle, queued, running, cancelled, failed, completed.
- [ ] P1 Tampilkan nama macro dan nomor action yang sedang berjalan secara ringan.
- [ ] P1 Berikan `executionID` unik untuk setiap run agar log dapat ditelusuri.
- [ ] P1 Simpan durasi total dan action terakhir hanya jika diagnostics diaktifkan.
- [ ] P2 Izinkan maksimum macro paralel hanya untuk action non-input yang aman.

### Definition of done runtime

- [ ] Dua hotkey yang ditekan cepat tidak membuat cursor bergerak saling bertabrakan.
- [ ] Emergency stop merespons ketika macro sedang delay, drag, mengetik, atau menjalankan script.
- [ ] Tidak ada modifier atau mouse button yang tertahan setelah macro gagal.
- [ ] UI tidak freeze ketika macro berjalan.
- [ ] Macro berikutnya dapat berjalan normal setelah macro sebelumnya dibatalkan.

## B. Trigger system

- [x] Global keyboard hotkey.
- [x] Trigger dapat dibatasi berdasarkan aplikasi/folder.
- [x] Dukungan hardware brightness key.
- [x] Key-switch primary/alternate action.
- [x] Built-in screenshot annotation hotkey.
- [ ] P0 Satukan built-in hotkey dan user hotkey dalam `TriggerRegistry`.
- [ ] P0 Buat collision report yang menjelaskan macro mana mengambil shortcut lebih dahulu.
- [ ] P0 Hindari register/unregister seluruh hotkey jika hanya satu macro berubah.
- [ ] P1 Trigger saat aplikasi tertentu menjadi aktif.
- [ ] P1 Trigger saat aplikasi tertentu berhenti atau kehilangan fokus.
- [ ] P1 Typed-string trigger dengan batas panjang dan timeout buffer.
- [ ] P1 Double-tap modifier trigger, misalnya tekan Control dua kali.
- [ ] P2 Folder/file-created trigger menggunakan file watcher yang sudah ada.
- [ ] P2 Periodic/time trigger sederhana tanpa cron parser kompleks.
- [ ] P2 Clipboard-changed trigger dengan debounce.
- [ ] P2 USB/MIDI trigger hanya sebagai modul opsional jika benar-benar dibutuhkan.

### Jangan langsung disadur

- [ ] HINDARI Puluhan trigger manager terpisah seperti Keyboard Maestro.
- [ ] HINDARI Web server publik untuk remote trigger.
- [ ] HINDARI Listener aktif terus-menerus untuk fitur yang belum dipakai pengguna.

## C. Action system

- [x] Click, current-position click, drag, path, dan move cursor.
- [x] Delay, type text, paste text, press key, dan press shortcut.
- [x] Open file dan custom shell action.
- [x] Volume, brightness, window transform, AX press, dan screenshot annotation.
- [x] Group dan repeat count.
- [ ] P0 Pisahkan implementasi action berdasarkan keluarga: pointer, keyboard, system, utility, dan flow.
- [ ] P0 Buat hasil action standar: success, cancelled, failed, timed-out.
- [ ] P0 Tambahkan validasi action sebelum macro dijalankan.
- [ ] P0 Unknown action harus tampil sebagai unsupported, bukan menghilang saat save.
- [ ] P1 Condition sederhana: app aktif, window title, file exists, variable equals/contains.
- [ ] P1 If/Else sebagai nested action yang dapat dilipat di editor.
- [ ] P1 Repeat-until dengan batas maksimum untuk mencegah infinite loop.
- [ ] P1 Wait-until image/pixel/window muncul dengan timeout wajib.
- [ ] P1 Activate application sebelum action tertentu.
- [ ] P1 Clipboard action: save, restore, transform, dan named clipboard ringan.
- [ ] P1 “Run another macro” dengan deteksi recursion.
- [ ] P2 Variable lokal per eksekusi.
- [ ] P2 Token ringan seperti tanggal, clipboard, app aktif, dan mouse position.
- [ ] P2 OCR sebagai helper opsional, bukan dependency core.
- [ ] P2 AppleScript/JXA executor dengan timeout dan permission feedback.

### Prinsip action compact

- [ ] Satu action baru harus punya parser, serializer, validator, executor, editor, dan test fixture.
- [ ] Action yang jarang digunakan tidak boleh menambah polling saat idle.
- [ ] Semua loop dan wait harus punya cancellation point.
- [ ] Semua action eksternal harus mengembalikan error yang bisa dibaca pengguna.

## D. Format `.shortking` dan persistence

- [x] Format plain text yang dapat diedit manual.
- [x] Folder config dan target application.
- [x] File watcher untuk reload macro.
- [ ] P0 Tambahkan `VERSION:` atau schema version yang opsional untuk kompatibilitas masa depan.
- [ ] P0 Gunakan atomic write: tulis temp file lalu replace.
- [ ] P0 Hindari penulisan ulang `.folder_config.json` jika nilai semantiknya tidak berubah.
- [ ] P0 Gunakan JSON output deterministic agar urutan key tidak terus berubah di Git.
- [ ] P0 Buat parser error dengan nomor baris dan alasan spesifik.
- [ ] P0 Tambahkan round-trip test: parse → serialize → parse menghasilkan macro yang sama.
- [ ] P1 Pertahankan komentar pengguna ketika macro disimpan dari editor.
- [ ] P1 Tampilkan preview perubahan sebelum import banyak macro.
- [ ] P1 Buat backup satu generasi sebelum overwrite.
- [ ] P1 Import harus melaporkan error per file, bukan menggagalkan semuanya.
- [ ] P2 Metadata optional: tags, favorite, usage count, dan modified date.
- [ ] HINDARI Migrasi ke SQLite selama folder/file masih memadai.
- [ ] HINDARI XML plist sebagai format utama macro.

## E. Editor yang cepat dan compact

- [x] Sidebar folder dan macro.
- [x] Action cards dan drag/drop.
- [x] Inline action editing.
- [x] Spotlight-style action search.
- [x] Multi-selection, copy/paste, delete, undo/redo dasar.
- [ ] P0 Pecah `MainEditorView.swift` menjadi sidebar, toolbar, canvas, inspector, dan empty state.
- [ ] P0 Pastikan seluruh action editor bisa digunakan dengan keyboard.
- [ ] P0 Berikan inline validation sebelum Run.
- [ ] P0 Disable menu command ketika tidak relevan.
- [ ] P1 Quick Run palette untuk mencari dan menjalankan macro tanpa membuka editor penuh.
- [ ] P1 Command palette menyatukan macro dan command aplikasi.
- [ ] P1 Collapse/expand semua group action.
- [ ] P1 Duplicate action dengan `⌘D`.
- [ ] P1 Space untuk preview macro/action jika sesuai konteks.
- [ ] P1 Search berdasarkan action type, trigger, folder, dan target app.
- [ ] P1 Mini runtime HUD yang hanya muncul selama macro berjalan.
- [ ] P2 Macro debugger dengan Step, Continue, Stop, dan current-action highlight.
- [ ] P2 Timeline hanya untuk macro hasil recording; jangan jadikan seluruh editor timeline.
- [ ] HINDARI Panel/modal baru untuk setiap setting kecil; prioritaskan inline editor dan popover.

## F. Native macOS integration

- [x] Standard application, File, Edit, Macro, Tools, Window, dan Help menus.
- [x] Menu-bar status item.
- [x] Dock menu dan optional Dock visibility.
- [x] Settings, editor, dan inspector window.
- [x] Window frame autosave untuk editor.
- [ ] P0 Audit menu validation dan dynamic titles.
- [ ] P0 Audit VoiceOver label untuk seluruh icon-only button.
- [ ] P0 Respect Reduce Motion, Reduce Transparency, Increase Contrast, dan Bold Text.
- [ ] P0 Pastikan Esc membatalkan capture, popover, dan modal flow.
- [ ] P1 Quick Look untuk file `.shortking`.
- [ ] P1 App Intent: Run Macro, Suspend, Resume, dan Find Macro.
- [ ] P1 URL scheme sederhana untuk menjalankan macro berdasarkan UUID/nama.
- [ ] P1 Services menu untuk menerima text/file dari aplikasi lain.
- [ ] P2 Spotlight indexing berdasarkan nama macro dan folder.
- [ ] P2 AppleScript dictionary setelah command API stabil.
- [ ] HINDARI Custom window chrome yang merusak traffic-light dan behavior native.

## G. Permission dan keamanan

- [x] Accessibility permission checker.
- [ ] P0 Tampilkan permission yang dibutuhkan per action, bukan meminta semuanya saat launch.
- [ ] P0 Bedakan status: not requested, denied, granted, dan needs relaunch.
- [ ] P0 Beri warning jelas sebelum menjalankan custom shell action dari macro impor.
- [ ] P0 Tambahkan trust status untuk macro yang berasal dari luar folder pengguna.
- [ ] P0 Jangan log isi clipboard, text rahasia, atau shell environment secara default.
- [ ] P1 Allowlist/confirmation opsional untuk script dan destructive file actions.
- [ ] P1 Sanitasi nama file saat import/duplicate.
- [ ] P1 Security bookmark jika nanti memakai sandbox atau akses folder eksternal persisten.
- [ ] P2 Tanda tangan/checksum library macro yang dibagikan.
- [ ] HINDARI Menyimpan credential, certificate, API key, atau password di `.shortking`.

## H. Diagnostics dan testing

- [ ] P0 Buat smoke-test checklist yang dijalankan sebelum setiap push.
- [ ] P0 Parser fixtures untuk setiap action type.
- [ ] P0 Test malformed macro, unknown action, dan missing parameter.
- [ ] P0 Test hotkey collision dan app-specific priority.
- [ ] P0 Test multi-monitor dan negative screen coordinates.
- [ ] P0 Test Retina/non-Retina coordinate conversion.
- [ ] P0 Test emergency stop pada setiap action yang menunggu.
- [ ] P1 Diagnostics panel yang menampilkan permission, registered trigger, dan runtime state.
- [ ] P1 Export diagnostics yang menyensor path dan data sensitif.
- [ ] P1 Ukur waktu dari hotkey event sampai action pertama.
- [ ] P1 Ukur idle CPU dan memory setelah 10 menit.
- [ ] P2 UI test untuk create, edit, reorder, save, dan reload macro.

## I. Packaging dan repository hygiene

- [ ] P0 Tambahkan build output dan `.o`/`.swiftdeps` ke `.gitignore` jika tidak diperlukan distribusi.
- [ ] P0 Pastikan build selalu menghasilkan bundle identifier dan signing identity yang stabil.
- [ ] P0 Pisahkan dev watcher dari release build.
- [ ] P0 Tambahkan version/build number dari Git commit atau tag.
- [ ] P1 Build release universal bila distribusi Intel masih dibutuhkan.
- [ ] P1 Buat packaging script DMG/ZIP terpisah dari fast development build.
- [ ] P1 Tambahkan release notes berdasarkan commit sejak tag terakhir.
- [ ] P2 Notarization hanya ketika ShortKing siap dibagikan publik.

## Prioritas yang direkomendasikan sekarang

### Sprint 1 — Reliability

- [ ] Thread-safe cancellation.
- [ ] Input cleanup lengkap.
- [ ] Timeout dan cancel untuk custom shell action.
- [ ] Deterministic folder-config serialization.
- [ ] Parser round-trip fixtures.

### Sprint 2 — Editor compact

- [ ] Pecah `MainEditorView`.
- [ ] Inline validation.
- [ ] Dynamic menu validation.
- [ ] Keyboard navigation audit.
- [ ] Quick Run macro palette.

### Sprint 3 — Macro intelligence

- [ ] Variables dan token dasar.
- [ ] If/Else.
- [ ] Wait-until dengan timeout.
- [ ] Run another macro dengan recursion guard.
- [ ] Runtime HUD/debug highlight.

### Sprint 4 — macOS integration

- [ ] App Intents.
- [ ] URL scheme.
- [ ] Quick Look `.shortking`.
- [ ] Services menu.
- [ ] Spotlight indexing.

## Filter keputusan untuk setiap ide baru

Sebelum mengembangkan fitur, jawab pertanyaan berikut:

- [ ] Apakah fitur ini menyelesaikan masalah nyata yang sering terjadi?
- [ ] Apakah fitur dapat tidak aktif tanpa memakai CPU saat idle?
- [ ] Apakah pengguna tetap bisa memahami macro dari file `.shortking`?
- [ ] Apakah fitur bisa dibatalkan dan menghasilkan error yang jelas?
- [ ] Apakah fitur menambah permission baru? Jika ya, apakah benar-benar sepadan?
- [ ] Apakah dapat dibuat memakai framework macOS bawaan?
- [ ] Apakah implementasinya dapat diuji tanpa menggerakkan input pengguna?
- [ ] Apakah fitur membuat ShortKing lebih cepat digunakan, bukan hanya lebih besar?

Jika sebagian besar jawabannya “tidak”, fitur tersebut sebaiknya ditunda.

## Arah produk yang disarankan

ShortKing sebaiknya berkembang sebagai **macro automation yang file-first, keyboard-first, dan compact**. Keyboard Maestro menjadi referensi untuk reliability dan extensibility; ShortKing tidak perlu mengejar seluruh luas fiturnya. Keunggulan ShortKing harus tetap berada pada startup cepat, macro yang transparan, editor ringkas, dan eksekusi yang dapat diprediksi.
