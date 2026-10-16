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
    private var settingsWindow: NSWindow?

    /// Accessible from the menu bar panel (AppDelegate lives outside the
    /// SwiftUI scene graph, so the panel can't reach it via environment).
    static var shared: AppDelegate {
        // Computed, not cached: always resolves the real adaptor instance
        // (NSApp.delegate is set once the app object is initialized).
        NSApp.delegate as? AppDelegate ?? AppDelegate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tray-only app: no Dock icon (also enforced via LSUIElement).
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            SortEngine.shared.start()
        }
    }

    /// Settings window: a plain NSWindow hosting the SwiftUI settings UI.
    /// SwiftUI's Settings scene and openWindow proved unreliable in a
    /// MenuBarExtra-only accessory (LSUIElement) app; a direct NSWindow
    /// always comes to the front.
    func openSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
