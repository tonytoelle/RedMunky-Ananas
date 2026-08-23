# ShortKing Project Rules

## Project Overview
ShortKing is a native macOS menu-bar app for creating and executing keyboard/mouse macro shortcuts using `.shortking` files. Built with pure Swift + SwiftUI + AppKit (no Xcode project, compiled directly via `swiftc`).

## Tech Stack
- Language: Swift (SwiftUI + AppKit + Carbon for global hotkeys)
- Build: `./DEVELOPING/build.sh` (concatenates all .swift files into temp_build.swift, compiles as single unit, then deletes temp file)
- No Xcode project, no SPM, no CocoaPods

## Source Architecture
All source code lives under `DEVELOPING/src/`:
```
src/
├── main.swift              (543 lines)  — AppDelegate, app entry point
├── Models/
│   ├── Trigger.swift       (466 lines)  — KeyMap, TriggerMode, Trigger, MacroAction, TargetApp, FolderConfig
│   ├── MacroItem.swift      (70 lines)  — MacroItem class
│   └── FileSystemNode.swift (52 lines)  — FileSystemNode enum for sidebar
├── Managers/
│   ├── MacroStore.swift    (751 lines)  — State management, file watching, macro CRUD
│   ├── ShortKingParser.swift(370 lines) — .shortking file parser
│   ├── InputSimulator.swift(401 lines)  — Mouse/keyboard event simulation
│   ├── CarbonHotKeyManager.swift(100 lines) — Global OS hotkey registration
│   ├── PermissionManager.swift(110 lines)   — Accessibility permission checks
│   └── LaunchAtLoginManager.swift(106 lines)— Launch at login toggle
├── Views/
│   ├── MainEditorView.swift    (1927 lines) — Main window, sidebar, inspector
│   ├── CaptureOverlayWindow.swift(1238 lines)— Overlay for recording coordinates
│   ├── SettingsView.swift       (847 lines) — Preferences window
│   ├── DraggableActionListView.swift(802 lines)— Action cards + drag-drop
│   ├── InlineActionEditViews.swift(417 lines)— Inline editors
│   ├── ActionEditViews.swift    (274 lines) — Detail edit forms
│   ├── ShortcutBadgeView.swift  (155 lines) — Badge + HotKeyRecorder
│   └── SpotlightSearchBar.swift (144 lines) — Spotlight-style action search
└── Utilities/
    ├── IconHelpers.swift    (218 lines) — Icon generation, nsColor helper
    └── String+Extensions.swift(76 lines)— Fuzzy match, levenshtein distance
```

## Key Conventions
- When editing code, only read the specific file(s) needed — do NOT read all files.
- All Swift files share the same module (internal access by default).
- Build compiles via single-file concatenation for speed (Unity Build pattern).

## Auto Compile & Relaunch App After Coding Changes
Every time swift code changes or modifications are completed:
1. Compile the app using `./DEVELOPING/build.sh` which automatically kills the active instance and opens the newly built `ShortKing.app`.
2. Follow up immediately with the Auto Git Sync.

## Auto Git Sync After Coding Changes
Every time code changes or modifications are completed, automatically perform a Git Sync:
1. Stage all changes: `git add .`
2. Commit with a very short, standard message (e.g. "update main.swift", "feat: auto scroll", "fix: bug") without long AI-generated summaries to save tokens.
3. Push to remote: `git push`
4. Show the commit ID and commit name to the user.

## Git Sync Shortcut
When the user says "sync", you must perform the following actions:
1. Stage all changes: `git add .`
2. Commit with a very short, standard message (e.g. "update main.swift", "feat: auto scroll", "fix: bug") without long AI-generated summaries to save tokens.
3. Push to remote: `git push`
4. Show the commit ID and commit name to the user.
