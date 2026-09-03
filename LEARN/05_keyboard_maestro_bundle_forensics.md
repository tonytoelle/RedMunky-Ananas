# 05 - Keyboard Maestro App Bundle: Temuan Forensik Pasif

Dokumen ini dibuat dari inspeksi read-only terhadap:

`/Users/tonytoelle/Downloads/Keyboard Maestro.app/Contents`

Tujuannya memahami struktur dan petunjuk arsitektur yang terlihat dari bundle, bukan mengambil source code proprietary. Binary native hanya memberi metadata, simbol, strings, resource, dan dependency; source Swift/Objective-C asli tidak tersedia di bundle ini.

## Ringkasan temuan

| Area | Temuan |
|---|---|
| Versi | Keyboard Maestro 11.0.4 |
| Model proses | Editor GUI + nested `Keyboard Maestro Engine.app` |
| Arsitektur CPU | Universal: `arm64` dan `x86_64` |
| Format UI | AppKit/nib; `NSMainNibFile = MainApp` dan engine `MainEngine` |
| Library contoh | 76 file `.kmlibrary`, berupa XML property list |
| Template action | 171 file `A*.nib` pada localization English |
| Engine helper | `CompileAppleScript`, `Tesseract`, `UpgradeHelper` |
| Data/format | `.kmmacros`, `.kmlibrary`, `.kmsync`, `.kmtrigger`, `.kmaction` |
| Scripting | AppleScript definition (`Editor.sdef`, `Engine.sdef`) dan URL scheme `keyboardmaestro:` |

## Struktur bundle yang penting

```text
Keyboard Maestro.app/Contents/
├── Info.plist
├── MacOS/
│   ├── Keyboard Maestro                 # Editor GUI
│   ├── keyboardmaestro                  # helper/launcher
│   ├── CompileAppleScript
│   └── Keyboard Maestro Engine.app/
│       └── Contents/MacOS/
│           ├── Keyboard Maestro Engine  # runner background
│           ├── Tesseract                # OCR helper
│           └── CompileAppleScript
├── Resources/
│   ├── Keyboard Maestro Libraries/      # contoh macro reusable
│   ├── en.lproj/                        # nib action + strings
│   ├── Licenses/
│   └── Assets.car, icons, sounds
└── _CodeSignature/
```

## Dependency yang terlihat

Editor men-link framework sistem berikut: Cocoa/AppKit, Foundation, CoreGraphics, ApplicationServices, Carbon, CoreMIDI, AudioToolbox, CoreAudio, Quartz/QuartzCore, WebKit, ScriptingBridge, IOKit, CoreLocation, Contacts, CoreSpotlight, Security, SystemConfiguration, CoreWLAN, serta SQLite dan ICU.

Ini tidak membuktikan semua fitur aktif di setiap eksekusi, tetapi menunjukkan area kemampuan yang disiapkan: global input, accessibility/UI scripting, audio/MIDI, web/custom prompt, database, location/network, dan AppleScript.

## Petunjuk dari Info.plist

- `NSAppleScriptEnabled = true` dan `OSAScriptingDefinition` menunjukkan automation API menjadi bagian resmi, bukan sekadar shell command.
- `CFBundleDocumentTypes` mendaftarkan format macro, library, sync, plug-in action, dan actions file.
- Engine memakai `LSUIElement = true`, cocok dengan proses background/menu-bar tanpa Dock UI utama.
- Engine mendaftarkan intents seperti execute macro, get/set variable, search, process tokens, dan edit macro.
- Permission descriptions mencakup Accessibility/Apple Events dan capability lain yang dipakai action tertentu.
- Engine mempunyai `NSAppTransportSecurity` exception untuk domain vendor. Ini adalah petunjuk jaringan, bukan bukti bahwa setiap macro mengirim data.

## Kesimpulan arsitektur

Keyboard Maestro sengaja memisahkan editor yang boleh ditutup dari engine yang tetap hidup. ShortKing saat ini menggabungkan coordinator dan engine di app yang sama. Pola KM yang paling layak diadopsi adalah memisahkan *responsibility* terlebih dahulu; pemisahan proses dapat dilakukan nanti jika kebutuhan stabilitas menuntutnya.

## Batas inspeksi dan keamanan

Inspeksi ini tidak menjalankan binary, tidak membongkar kode, tidak mengekstrak credential, dan tidak memodifikasi bundle. Ada file `certificate.p12` di resource nested engine; jangan menyalin, membuka, atau memasukkannya ke repository. Binary proprietary juga tidak boleh disadur sebagai source.

