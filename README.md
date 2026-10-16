# Sortilege

**A macOS menu bar app that keeps your Downloads folder backed up.**

Finder/iTunes device backups skip `~/Downloads` entirely. Sortilege watches Downloads in realtime and moves files into categorized folders inside a location that *is* backed up (e.g. `~/Documents/Sorted`), so nothing downloaded is ever left unprotected.

## How it works

- **Tray-only** menu bar app (`MenuBarExtra`, no Dock icon) that watches a folder of your choice in realtime.
- **Realtime + periodic**: a filesystem watcher fires on every change (with a short debounce); a 60 s timer catches files that arrived while the Mac was asleep.
- **Three sorting tiers**, applied in order:
  1. **Custom rules** (yours): match by extension or filename keyword → any folder you choose.
  2. **Apple Intelligence** (optional, on-device): reads the content of text-bearing files (PDF, text, HTML, CSV) via the Foundation Models framework; on macOS 27+ it even looks at images to separate screenshots, photos and graphics.
  3. **Built-in rules**: extension/UTType-based categories — Documents, Spreadsheets, Presentations, Photos, Videos, Audio, Installers, Archives, Code, Other.
- **Dry run & Preview**: simulate a full sort and get an HTML report of where every file would go — nothing is moved.
- **Activity & Undo**: every move is recorded with source and destination; move any file back with one click. Restored files are left alone for the rest of the session.
- **Filters**: include/ignore files by extension list, added date, or selected files/folders.
- **App Store ready**: sandboxed, security-scoped bookmarks, launch-at-login via `SMAppService`, no network access, no data collection — Apple Intelligence runs entirely on-device.

## Requirements

- macOS 14.0+ (Apple Intelligence text classification requires macOS 26+ with Apple Intelligence enabled; multimodal image classification requires macOS 27+).
- Xcode 26 to build (for the `FoundationModels` framework). Below those versions the app automatically runs in rules-only mode.

## Getting started

The app is delivered as ready-to-use Swift sources — create a new Xcode project and drop them in:

1. Xcode → **File → New → Project → macOS → App** (Product Name: `Sortilege`, Interface: **SwiftUI**, Language: **Swift**).
2. Delete the generated `ContentView.swift` and `SortilegeApp.swift`, then add the files from [`Sortilege/`](Sortilege/).
3. Follow the full setup guide: **[docs/SETUP.md](docs/SETUP.md)** (Info.plist, sandbox entitlements, privacy manifest, deployment target).

## Documentation

- [docs/SETUP.md](docs/SETUP.md) — Xcode project setup, entitlements, Info.plist, privacy manifest, testing walkthrough.
- [docs/APP_STORE.md](docs/APP_STORE.md) — App Store submission checklist, review notes, description guidance.
- [docs/LIMITATIONS.md](docs/LIMITATIONS.md) — known prototype limitations and the post-1.0 roadmap.

## Project layout

```
Sortilege/
├── Sortilege/
│   ├── SortilegeApp.swift        # @main entry point + AppDelegate
│   ├── Models.swift              # Category, MoveRecord, CustomRule, SortFilter
│   ├── RuleClassifier.swift      # tier-3 extension/UTType rules
│   ├── TextExtractor.swift      # text extraction for Apple Intelligence
│   ├── AIClassifier.swift       # FoundationModels (macOS 26/27+) classifiers
│   ├── Settings.swift           # persisted, sandbox-safe settings
│   ├── SortEngine.swift          # watcher, scanner, undo, HTML preview report
│   ├── FolderPicker.swift       # NSOpenPanel helpers (permission grant)
│   └── Views/
│       ├── MenuBarPanel.swift    # menu bar dropdown UI
│       ├── ActivityWindow.swift  # Activity & Undo window
│       └── SettingsWindow.swift  # Settings (⌘,) incl. rules/filters editors
├── Config/
│   ├── Sortilege.entitlements
│   ├── Info.plist
│   └── PrivacyInfo.xcprivacy
└── docs/
```

## License

MIT — see [LICENSE](LICENSE).
