# Sortilege — App Store submission checklist

## Checklist

- [ ] Product page in **App Store Connect**: name, bundle ID, SKU; set the "Made for Mac" / macOS platform availability.
- [ ] **Screenshots**: menu bar dropdown open (folders + toggles), recent activity list, and one showing the sorted destination folder in Finder. Menu-bar utilities typically submit the dropdown window as the main shot.
- [ ] **Review notes** for App Review, e.g.:
  > "Sortilege organizes downloaded files into categorized folders. It needs access to a user-selected folder (granted via NSOpenPanel, stored as a security-scoped bookmark). No network access, no data collection; classification runs on-device via the Foundation Models framework with an extension-based fallback. Apple Intelligence sorting is an optional feature controlled in Settings — the app is fully functional with it disabled or unavailable."
- [ ] Your **App Store description** should state clearly that AI sorting is optional and the app works via rules on any supported Mac — this widens your audience to non-Apple-Intelligence machines and preempts review questions.
- [ ] Upload via **Product → Archive → Distribute App → App Store Connect**.
- [ ] Turn on "Sign in to App Store Connect…" automatic signing; Xcode manages the Mac distribution certificate.
