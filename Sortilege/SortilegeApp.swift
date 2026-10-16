//
//  SortilegeApp.swift
//  Sortilege
//
//  App entry point. Sortilege is a macOS menu bar (tray) app that watches
//  a folder in realtime and periodically, then sorts files into category
//  folders.
//
//  Motivation: Finder/iTunes device backups do not include ~/Downloads.
//  Sorting files into a backed-up location (e.g. ~/Documents/Sorted)
//  closes that gap automatically, in real time.
//
//  Architecture
//  ------------
//  • MenuBarExtra (macOS 13+) — quick UI lives in the menu bar dropdown,
//    no Dock icon (LSUIElement). The app can be fully "hidden" while working.
//  • A standard Settings scene (⌘,) holds the full configuration. Apple
//    Intelligence sorting is OPTIONAL — the user enables/disables it there,
//    and the app always works in rules-only mode when it is off or
//    unavailable.
//  • Realtime watching: DispatchSource on the watched directory fires on
//    every change; a short debounce + min-age guard avoids grabbing files
//    that are still downloading.
//  • Periodic catch-up: a 60 s timer guarantees files that appeared while
//    the Mac was asleep (or arrived before launch) are picked up.
//  • Classification: extension/UTType rules first; Apple Intelligence
//    (Foundation Models framework, macOS 26+, on-device, guided generation)
//    refines text-bearing files (PDF/text/HTML/CSV/...) by content.
//    Falls back to rules when Apple Intelligence is unavailable.
//  • Sandboxing / App Store ready: folders are granted via NSOpenPanel and
//    remembered with security-scoped bookmarks (no broad filesystem access).
//  • Launch at login via SMAppService (App Store compliant).
//  • Activity & Undo window: every move is recorded with its source and
//    destination, so any file can be moved back with one click. Files
//    restored this way are skipped for the rest of the session.
//  • Custom rules: user-defined "extension" or "filename contains" rules
//    that run BEFORE the built-in categories and Apple Intelligence.
//  • Include/ignore filters: sort only (or never) files matching an
//    extension list, an added-before/after date, or selected files/folders.
//  • Multimodal Apple Intelligence (macOS 27+): images are looked at and
//    classified as screenshots, photos or graphics.
//
//  Setup steps are in docs/SETUP.md.
//

import SwiftUI

// MARK: - App entry point

@main
struct SortilegeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Sortilege", systemImage: "tray.and.arrow.down.fill") {
            MenuBarPanel()
        }
        .menuBarExtraStyle(.window)

        // Activity & Undo window, opened from the dropdown's "Undo…" button.
        Window("Activity & Undo", id: "activity") {
            ActivityWindow()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tray-only app: no Dock icon (also enforced via LSUIElement).
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            SortEngine.shared.start()
        }
    }

}

/// Owns the single Settings window. A dedicated singleton (not the app
/// delegate) so the menu bar panel always reaches the same instance —
/// NSApp.delegate is not always the adaptor instance in every launch mode.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func open() {
        if let window = window {
            bringToFront(window)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Sortilege Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsWindow())
        self.window = window
        bringToFront(window)
    }

    /// Accessory apps don't come forward on their own. The MenuBarExtra
    /// dropdown itself lives at status-bar level (NSStatusWindowLevel),
    /// which sits far above .floating — so the settings window is raised
    /// above that level first, then settles back to normal so it behaves
    /// like a regular window afterwards.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.level = NSWindow.Level(rawValue: NSStatusWindowLevel.rawValue + 1)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.level = .normal
            window.makeKeyAndOrderFront(nil)
        }
    }
}
