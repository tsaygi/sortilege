# Sortilege — Known prototype limitations & roadmap

## Known prototype limitations (be transparent on the product page)

- Only top-level files in the watch folder are sorted (subfolders are left alone — intentional, so app bundles and existing organization aren't shredded).
- Text classification (PDF, text, HTML, CSV) requires macOS 26+; multimodal image classification (screenshots vs photos vs graphics) requires macOS 27+. On older systems — and for videos/installers, always — files are classified by file type.
- Image classification runs on every image entering the watch folder; on slower Macs the first scan with many images can take a few seconds per file (on-device inference).
- Undo is session-aware: moved-back files are skipped until the app restarts. After a restart, a file sitting in the watch folder will be sorted again — worth stating in the description so users aren't surprised.
- Custom rules match on file extension or a keyword in the filename only (not file contents — that's what the optional Apple Intelligence tier is for). Filters (include/ignore) match on extension, added date, or selected files/folders.

## Roadmap ideas (post-1.0)

1. iCloud Drive destination support for cross-device sync.
2. App Intents / Shortcuts action ("Sort Downloads now").
3. Rule and filter import/export, plus a "test" preview pane showing which tier/filters would catch a sample file.
