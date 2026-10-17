# Sortilege Privacy Policy

*Last updated: October 2026*

## Introduction

Sortilege ("the App") is a macOS menu bar application developed by the developer of the Sortilege repository ("we", "us"). This policy explains how the App handles information when you use it.

**The short version: Sortilege collects nothing, sends nothing, and tracks nothing. Everything happens on your Mac.**

## Data we collect

**None.** Sortilege does not collect, transmit, sell, or share any personal data. The App has no network access and contains no analytics, advertising, or tracking code of any kind.

## Information stored on your device

The App stores the following on your Mac, in your own user settings storage (`UserDefaults`), accessible only to the App and never leaving your device:

- **Folder selections** — security-scoped bookmarks to the folder you choose to watch and your chosen destination folder, so the App can remember them across launches.
- **Your preferences** — toggle states (Apple Intelligence sorting, dry run, pause, move-folders, launch-at-login).
- **Custom rules and filters** — the sorting rules and include/ignore filters you create.
- **Ignored files list** — paths of files you have moved back via Undo.
- **Activity history** — file names, folder names, and paths of files the App has sorted, shown in the Activity & Undo window. You can clear this at any time with the "Clear History" button.

This data never leaves your Mac and is not included in any backup, sync, or telemetry by the App. Deleting the App or using "Clear History" removes it.

## File access

Sortilege only accesses:

1. The folder you explicitly select for it to watch (e.g. your Downloads folder), and
2. The destination folder you explicitly select for sorted files.

Access is granted by you through the standard macOS open panel and remembered via security-scoped bookmarks, as required by macOS App Sandbox. The App cannot access any other locations on your Mac.

## Apple Intelligence (on-device classification)

If you enable optional Apple Intelligence sorting, the App uses Apple's Foundation Models framework to classify files by their content. **This processing runs entirely on your Mac.** File contents are never uploaded, transmitted, or shared with anyone — including us. You can disable Apple Intelligence sorting at any time in Settings, and the App is fully functional without it.

## Third parties

The App contains no third-party analytics, advertising, or SDK integrations. It does not use third-party services and does not connect to the internet.

## Permissions

The App requests only the permissions required for its function:

- **Folder access** (via your explicit selection in an open panel) — to watch and sort files.
- **Login item** (optional) — only if you enable "Launch at Login".

## Children's privacy

The App does not collect any data from anyone, including children, and is safe for all ages.

## Changes to this policy

If this policy changes, the updated version will be published with a new "Last updated" date at this location.

## Contact

If you have questions about this privacy policy or the App, please open an issue at the Sortilege GitHub repository: https://github.com/tsaygi/sortilege
