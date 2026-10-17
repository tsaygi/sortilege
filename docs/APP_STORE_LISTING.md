# Sortilege — App Store listing copy

All texts below are ready to paste into App Store Connect. Field limits: name 30 chars, subtitle 30 chars, description 4000 chars, keywords 100 chars, "What's New" 4000 chars, promotional text 170 chars.

---

## App name (30 chars max)

```
Sortilege: File Organizer
```
(22 chars — room to spare if you prefer another variant)

## Subtitle (30 chars max)

```
Auto-sort your Downloads
```

## Promotional text (170 chars max, editable without review)

```
Sortilege watches your Downloads folder in real time and moves files into tidy category folders — so everything you download lands in a place your backups actually protect.
```

## Description (4000 chars max)

```
YOUR DOWNLOADS FOLDER ISN'T BACKED UP. SORTILEGE FIXES THAT.

Time Machine and device backups skip your Downloads folder entirely. Every installer, invoice, photo, and document you download lives unprotected — until you move it somewhere safe. Sortilege does that for you, automatically, the moment a file lands.

HOW IT WORKS

Sortilege lives quietly in your menu bar. It watches a folder you choose (usually Downloads) in real time and moves new files into clearly named category folders inside a destination you pick — for example, inside Documents, where backups reach them:

• Documents, Spreadsheets & Presentations
• Photos, Screenshots & Graphics
• Videos, Audio
• Installers & Archives
• Code
• And a folder for everything else

Nothing to configure on day one: pick your folders, review what the app is about to do, and press Start.

KNOW BEFORE ANYTHING MOVES

When you select a folder, Sortilege shows you a plain-English plan of exactly what will be sorted where — before a single file moves. Not convinced? Open a dry-run report in your browser, or turn on Dry Run mode to log planned moves without touching anything.

THREE WAYS TO DECIDE WHERE FILES GO

1. Your rules first — "put every .dmg in Installers" or "anything with 'invoice' in the name goes to Invoices."
2. Apple Intelligence (optional) — the on-device model reads the actual content of text files like PDFs, HTML and CSVs, sorting them by what they are: a document, a spreadsheet, a presentation, or code. On newer Macs it even looks at images to separate screenshots from photos and graphics.
3. Sensible built-in rules — file type and extension categories that always work, on every Mac.

Apple Intelligence sorting is entirely optional and runs on-device. No network access, no data collection — and the app is fully functional without it on any supported Mac.

FULL CONTROL

• Undo: every move is recorded. Move any file back with one click — and it will never be sorted again until you allow it.
• Pause: stop sorting whenever you like; the setting survives restarts.
• Filters: sort only (or never) files matching certain extensions, added dates, or hand-picked files and folders.
• Move whole folders or leave them untouched — your choice.
• Launch at login, runs quietly in the menu bar, no Dock icon.

PRIVATE BY DESIGN

Everything happens on your Mac. Files are classified locally, history stays in your settings, and the optional AI tier uses Apple's on-device Foundation Models. Sortilege never uploads a byte.

Sortilege — the backup-aware file organizer.
```

## Keywords (100 chars max, comma-separated)

```
organizer,downloads,sort,files,cleanup,tidy,automation,menubar,backup,documents,intelligence
```
(93 chars)

## What's New (version 1.0.0)

```
Initial release.
• Real-time Downloads sorting into category folders in a backup-safe location
• Review-before-move plan, dry-run HTML report and Dry Run mode
• Optional Apple Intelligence content-based sorting (on-device)
• One-click Undo with a permanent ignore list
• Custom rules, include/ignore filters, pause, launch at login
```

---

## App Review notes (paste into the Review Notes field)

```
Sortilege organizes downloaded files into categorized folders. It needs access to a user-selected folder, granted via NSOpenPanel and stored as a security-scoped bookmark (App Sandbox entitlement: user-selected read/write). A second, optional bookmark stores the destination folder.

No network access, no data collection. The optional Apple Intelligence classification runs entirely on-device via the Foundation Models framework, with an extension-based fallback; the app is fully functional with AI disabled or unavailable (there is a Settings toggle and an on/off badge in the menu bar).

Demo steps:
1. Launch — a menu bar icon appears (tray-only app, LSUIElement).
2. Click the icon → Set… → pick a folder to watch and a destination folder.
3. A plan review window appears listing what would be sorted where. Press Start Sorting to begin.
4. Drop a .dmg, a .jpg, a PDF and a .txt into the watched folder — they move into Installers/, Photos/, Documents/ and Code/ within seconds and are listed under Recent activity.
5. Undo… → Activity & Undo window → Move Back returns a file to its original location and adds it to the Ignored files list so it is not re-sorted.
6. Settings (⌘-style window via the dropdown) contains the Apple Intelligence toggle, dry run, pause, custom rules, filters, ignored files and folder pickers.
```

## Privacy policy URL

App Store Connect requires a publicly hosted privacy policy URL. The policy lives at:

```
https://github.com/tsaygi/sortilege/blob/main/docs/PRIVACY.md
```

(Or the raw URL: `https://raw.githubusercontent.com/tsaygi/sortilege/main/docs/PRIVACY.md` — either is accepted; the GitHub blob page is the friendlier link.)

## Privacy questionnaire answers (App Store Connect)

- **Data collected:** "Data not collected" — the app collects nothing, sends nothing, tracks nothing.
- Everything (rules, history, ignored list, bookmarks, toggles) is stored locally in UserDefaults; file classification happens on-device.
- **Privacy manifest (`PrivacyInfo.xcprivacy`, already in the repo `Config/`):** `NSPrivacyAccessedAPICategoryUserDefaults` with reason code `CA92.1` (app's own settings storage).

## Screenshots to take (App Store wants 1280×800 or 1440×900)

1. Menu bar dropdown open — folders, toggles, recent activity (primary shot).
2. Plan review window — showing the "review before anything moves" flow.
3. Activity & Undo window — showing one-click undo.
4. Settings window — rules/filters editing.
5. Finder window showing the sorted destination folders (labeled with the app icon).
