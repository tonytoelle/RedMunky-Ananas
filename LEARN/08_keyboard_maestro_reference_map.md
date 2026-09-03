# 08 - Peta Referensi Keyboard Maestro untuk ShortKing

## Cara membaca hasil inspeksi

| Artefak bundle | Clue yang diberikan | Relevansi ShortKing |
|---|---|---|
| `Keyboard Maestro Engine.app` | runtime background terpisah | kandidat arsitektur masa depan |
| `en.lproj/A*.nib` | template UI/action per tipe | inspirasi pemisahan editor per action |
| `.kmlibrary` XML plist | library macro yang deklaratif | inspirasi export/import dan schema |
| `Editor.sdef`, `Engine.sdef` | automation API formal | API command/automation masa depan |
| `Tesseract` | OCR helper native terpisah | service optional, jangan masuk core |
| `CompileAppleScript` | compile/execute boundary AppleScript | executor dengan timeout/error handling |
| `Info.plist` document types | file association dan interchange | metadata format ShortKing |
| `Assets.car`, `.icns`, `.wav` | UI feedback dan branding | hanya inspirasi, jangan menyalin aset |

## Hipotesis alur kerja KM

```text
User / OS event
      ↓
Trigger manager memilih macro aktif
      ↓
Runtime membuat execution context
      ↓
Action runner menjalankan action berurutan
      ↓
Variable/token/condition diproses
      ↓
UI feedback, log, clipboard, atau result
```

Ini adalah inferensi dari pemisahan executable, Info.plist, strings manager/factory, dan contoh library; bukan klaim source-level tentang implementasi internal proprietary.

## Checklist fitur untuk ShortKing

### Runtime

- [ ] Satu `MacroRuntime` untuk seluruh jalur run.
- [ ] Max simultaneous macro yang eksplisit.
- [ ] Cancellation dan emergency stop terpusat.
- [ ] Cleanup input state pada semua exit path.

### Trigger

- [ ] `TriggerRegistry` dengan register/unregister atomik.
- [ ] Debounce/cooldown untuk trigger yang bisa burst.
- [ ] Target app/focused-window context yang snapshot saat start.

### Editor

- [ ] Action editor per type.
- [ ] Nested flow editor untuk condition/repeat.
- [ ] Validasi sebelum save/run.
- [ ] Unknown action tetap tampil sebagai unsupported card.

### Persistence

- [ ] Schema version.
- [ ] Atomic write dan recovery file.
- [ ] Log migrasi format.
- [ ] Import/export dengan error per macro, bukan all-or-nothing.

### Observability

- [ ] Execution ID per run.
- [ ] Log action start/end/error.
- [ ] Durasi action.
- [ ] Reason macro berhenti: completed, cancelled, timeout, permission, target missing.

## Kesimpulan praktis

Pelajaran terbesar dari bundle ini bukan meniru jumlah fiturnya. Yang paling bernilai adalah boundary yang jelas: trigger → runtime context → action executor → feedback. Boundary tersebut akan membuat ShortKing dapat berkembang tanpa mengembalikan semua logic ke `main.swift`.

