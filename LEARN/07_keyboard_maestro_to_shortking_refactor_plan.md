# 07 - Blueprint Refactor ShortKing Berdasarkan Keyboard Maestro

## Temuan utama

Keyboard Maestro tidak menaruh semua pekerjaan di editor. Editor mengurus konfigurasi dan UI; Engine mengurus trigger global, state, dan eksekusi. Resource bawaan juga menunjukkan action template dan macro library diperlakukan sebagai data.

## Target arsitektur ShortKing

```text
AppDelegate
├── MenuBarController
├── WindowCoordinator
└── MacroRuntime
    ├── TriggerRegistry
    ├── MacroScheduler
    ├── ActionDispatcher
    ├── PermissionService
    └── RuntimeState

Editor layer
├── MacroStore
├── ShortKingParser
└── SwiftUI views

Executors
├── InputActionExecutor
├── ClipboardActionExecutor
├── ScreenshotActionExecutor
├── ShellActionExecutor
└── FlowActionExecutor
```

## Pemetaan dari kode sekarang

| Bagian sekarang | Tujuan refactor |
|---|---|
| `main.swift` | bootstrap dan dependency wiring saja |
| menu setup | `MenuBuilder` / `MenuBarController` |
| show editor/settings/inspector | `WindowCoordinator` |
| Carbon registration | tetap di `CarbonHotKeyManager`, expose registry kecil |
| action execution | executor per family, bukan handler menu langsung |
| file watching | `MacroStore`/`MacroFileWatcher` |
| screenshot annotation | service/coordinator terpisah dari AppDelegate |
| permissions | satu service dengan status publisher |

## Urutan migrasi yang paling aman

### Fase 1 — Pecah AppDelegate tanpa mengubah perilaku

1. Pindahkan menu builder.
2. Pindahkan window creation/reuse.
3. Pindahkan Drop Shelf dan screenshot coordinator.
4. Pertahankan method wrapper di `AppDelegate` selama masa transisi.

### Fase 2 — Stabilkan runtime

1. Buat `MacroRuntime` sebagai satu pintu eksekusi.
2. Tambahkan cancellation token dan emergency stop.
3. Pastikan held key/mouse selalu dilepas dalam `defer`.
4. Pisahkan event callback Carbon dari pekerjaan action yang lebih berat.

### Fase 3 — Model data dan test

1. Tambahkan schema version.
2. Unit-test parser untuk macro valid, field hilang, unknown action, dan nested flow.
3. Test trigger registration/unregistration.
4. Test permission unavailable dan target app berubah.

### Fase 4 — Pertimbangkan proses engine terpisah

Hanya lakukan jika app sering crash karena editor/UI, atau user membutuhkan macro tetap berjalan ketika editor ditutup. Proses terpisah memerlukan IPC, crash recovery, state synchronization, dan permission identity yang konsisten; jadi bukan langkah refactor pertama.

## Yang cocok disadur

- Pemisahan Editor vs Runtime secara tanggung jawab.
- Registry trigger dan factory per trigger type.
- Action sebagai data dengan discriminator stabil.
- Nested `Conditions`, `ElseActions`, dan control-flow tree.
- Macro library sebagai format deklaratif yang bisa dibaca manusia.
- AppleScript/URL/intents sebagai automation surface jangka panjang.
- Permission/status onboarding yang eksplisit.

## Yang tidak perlu disadur sekarang

- 170+ jenis action.
- UI nib/AppKit lama.
- Network server atau arbitrary web exceptions.
- Tesseract helper sebelum OCR memang menjadi requirement ShortKing.
- Nested helper binary atau asset proprietary.

## Definition of done refactor awal

- `main.swift` turun menjadi bootstrap yang mudah dibaca.
- Tidak ada perubahan pada format `.shortking`.
- Semua macro lama tetap parse dan run.
- Build `./DEVELOPING/build.sh` sukses.
- Hotkey global, file watcher, screenshot annotation, Drop Shelf, settings, dan emergency stop tetap berfungsi.
- Ada commit kecil per fase agar rollback mudah.

