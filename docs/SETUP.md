# Sortilege — Xcode setup & App Store submission guide

This guide walks you through turning the Swift sources in this repository into a working, App Store-ready macOS app.

## 1. Create the Xcode project

### Option A — generate it with XcodeGen (recommended)

The repository includes a `project.yml` spec. With [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed:

```bash
xcodegen
open Sortilege.xcodeproj
```

This produces a ready-to-run project with all of steps 2–5 below already configured. Set your team under **Signing & Capabilities** and build with Xcode 26.

### Option B — create it manually

1. Xcode → **File → New → Project → macOS → App**
2. Options:
   - Product Name: `Sortilege`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Testing System: any (or uncheck "Include Tests")
   - Storage: **None**
3. **Delete** the generated `ContentView.swift` and `SortilegeApp.swift`, then add all files from the [`Sortilege/`](../Sortilege/) directory of this repository, plus `Config/Info.plist`, `Config/Sortilege.entitlements`, and `Config/PrivacyInfo.xcprivacy` from the [`Config/`](../Config/) directory. They contain everything: models, engine, UI, and the `@main` entry point.

## 2. Info.plist (make it a tray-only app)

In **Target → Info**, add:

| Key | Value |
| --- | --- |
| Application is agent (UIElement) — `LSUIElement` | `YES` |

This hides the app from the Dock so it lives purely in the menu bar. (The code also calls `setActivationPolicy(.accessory)` as a belt-and-braces measure.)

## 3. Signing & Capabilities

In **Target → Signing & Capabilities**:

1. **App Sandbox** — turn ON. Required for App Store distribution.
2. Under App Sandbox, add **User Selected File → Read/Write**
   (`com.apple.security.files.user-selected.read-write`).

That's all the app needs: folder access is granted by the user through `NSOpenPanel` and remembered via security-scoped bookmarks. No network entitlement is needed — Apple Intelligence runs on-device.

**Optional convenience:** to pre-grant the Downloads folder without asking, add this key to `Sortilege.entitlements` manually:

```xml
<key>com.apple.security.files.downloads.read-write</key>
<true/>
```

App Review accepts this documented entitlement, but the NSOpenPanel flow alone is enough — use it only if you want a smoother first run.

## 4. Deployment target

- Set **Minimum Deployments → macOS 14.0**. The menu bar UI works from macOS 13/14.
- Apple Intelligence **text** classification activates only on **macOS 26+** with Apple Intelligence enabled; **multimodal image** classification (screenshots vs photos vs graphics) additionally needs **macOS 27+** (WWDC26 multimodal prompts). Below those versions the app automatically runs in rules-only mode (the badge in the dropdown shows "Rules" vs "AI on").
- Build with **Xcode 26** so the `FoundationModels` import compiles.

## 5. Privacy manifest (required for App Store submission)

Create `PrivacyInfo.xcprivacy` in the app target (Xcode: File → New → File → Privacy Report / App Privacy) and declare:

- **NSPrivacyAccessedAPICategoryUserDefaults** → reason code `CA92.1` (app's own settings/history storage in `UserDefaults`).
- No tracking, no collected data: everything stays on device (rules + on-device Apple Intelligence). In App Store Connect, answer the privacy questionnaire with "Data not collected".

## 6. Test it

1. Run from Xcode. The menu bar icon appears (tray with arrow).
2. Click it → **Choose Folder…** → pick `~/Downloads`.
3. Optionally **Set…** destination → pick a folder inside `~/Documents` (this is the backup-safe location).
4. Drop a mix of files into Downloads: a `.dmg`, a `.jpg`, a PDF invoice, a `.txt` of code.
5. Watch the "Recent activity" list: within seconds each file is moved into `Installers/`, `Photos/`, `Documents/`, `Code/`.
6. Open **Settings** (the "Settings…" button in the dropdown, or Sortilege menu → Settings, ⌘,). There you can:
   - toggle **"Sort using Apple Intelligence"** on/off — the dropdown badge instantly switches between "AI on" and "Rules";
   - toggle **Dry run** to preview moves without touching files;
   - toggle **Launch at Login** — uses `SMAppService` (App Store compliant, no deprecated APIs);
   - change watched/destination folders;
   - add **custom rules** — e.g. extension `dmg` → `Installers`, or name contains `invoice` → `Invoices`;
7. Click **Undo…** in the dropdown → the Activity & Undo window lists every move with its source → destination. Press **Move Back** on a row (or **Undo All**): the file returns to the watch folder and is left untouched for the rest of the session so it isn't instantly re-sorted. Verify a moved file reappears where it started.
8. Add a custom rule in Settings (e.g. name contains `invoice` → `Invoices`), drop a matching file into Downloads, and watch it skip the built-in categories entirely (the activity entry shows `custom` as the deciding tier).
9. In Settings → **Filters**, add "Ignore files matching · Extension · `iso`" and drop an `.iso` into Downloads — it stays untouched. Then try "Only sort files matching" with an extension list (allowlist), the **Date added** kind (after/before a chosen date), and the **File / Folder** kind (select exact files or folders via the open panel).
10. On macOS 27+, take a screenshot (⇧⌘3) into the watch folder and add a camera photo: the screenshot lands in `Screenshots/`, the photo in `Photos/` — both activity entries tagged `AI`.
11. Click **Preview…** in the dropdown: Sortilege simulates the entire sort (custom rules, Apple Intelligence and filters all applied — nothing moves) and automatically opens a **dry-run HTML report** in the default browser. It lists every file with its destination, the deciding tier (custom/AI/rules), per-folder counts at the top, and files skipped by filters — plus a clear "nothing has been moved" banner. This is also a great demo asset for your App Store page.
