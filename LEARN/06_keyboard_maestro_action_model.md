# 06 - Model Action, Trigger, dan Library Keyboard Maestro

## 1. Library bukan binary

File `.kmlibrary` bawaan Keyboard Maestro dapat dibaca sebagai XML property list. Contoh `Calculate.kmlibrary` berisi metadata library, group, macro, lalu array `Actions`. Beberapa field yang terlihat:

```text
Author
Category1 / Category2
Description
Items
  Activate
  IsActive
  Macros
    Actions
      MacroActionType
      IsActive
      IsDisclosed
      Conditions / ElseActions
```

Artinya library adalah paket konfigurasi/deklaratif yang dapat diimpor dan diedit, bukan executable plugin biasa.

## 2. Action sebagai data

Action memakai discriminator `MacroActionType`, kemudian property khusus action. Contoh yang ditemukan dari library:

- `PromptForUserInput`
- `SetVariableToText`
- `FilterVariable`
- condition variable dengan operator `Contains`
- tombol prompt seperti `Type`, `Copy/C`, `Cancel/.`

Pola ini cocok dengan desain ShortKing: parser membaca action generik, lalu dispatcher memilih executor berdasarkan type. Jangan membuat parser bergantung pada urutan key XML/JSON; gunakan nama field dan default yang eksplisit.

## 3. Keluarga trigger yang terindikasi

Strings simbol dari engine menampilkan manager terpisah untuk banyak trigger:

- hot key
- typed string
- gesture
- mouse/dragged file
- application dan focused window
- folder/group status menu
- clipboard
- time/periodic/cron/idle/login/wake/unlock/power
- MIDI, HID, USB, volume/audio output, display, appearance, space
- remote/web trigger dan engine launch

Petunjuk pentingnya bukan jumlah trigger, melainkan pola desain: setiap trigger mempunyai lifecycle/manager sendiri dan factory untuk menghasilkan object trigger. Ini lebih mudah dirawat daripada satu callback besar yang mengetahui semua jenis event.

## 4. Action families yang terlihat

Strings action menunjukkan area berikut:

- execute macro, subroutine, shortcut, workflow, AppleScript, JavaScript, shell/script
- clipboard copy/filter/search/replace/named clipboard/past clipboard
- prompt, custom HTML, display image/text/progress
- application/window/finder actions
- OCR dan image-related actions
- variables, calculate, mark macro, enable/disable macro
- control flow: group/if/for/sleep
- audio, MIDI, HID, USB, network/location

ShortKing tidak perlu mengejar semua fitur ini. Ambil fondasinya: action type yang stabil, context runtime, cancellation, timeout, dan error policy.

## 5. Rekomendasi model ShortKing

```swift
enum MacroActionType: String, Codable {
    case click, drag, typeText, keyPress, delay
    case screenshot, shell, conditional, repeatActions
}

struct ActionContext {
    let macroID: UUID
    let variables: [String: String]
    let targetApplication: TargetApp?
    let cancellation: CancellationToken
}

protocol ActionExecutor {
    var supportedType: MacroActionType { get }
    func execute(_ action: MacroAction, context: ActionContext) async throws
}
```

Ini menjaga UI/editor tidak perlu mengetahui detail `CGEvent`, shell, screenshot, atau permission.

## 6. Prinsip kompatibilitas

- Simpan `schemaVersion` pada format macro.
- Unknown action harus menghasilkan warning yang jelas, bukan membuat seluruh macro gagal dibaca.
- Action yang sedang inactive tetap dipertahankan saat save.
- Conditions dan nested actions perlu struktur tree, bukan array flat saja.
- Setiap action sebaiknya punya timeout/cancellation policy.

