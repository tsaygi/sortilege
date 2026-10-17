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

/// Owns the app's single-instance auxiliary windows (Settings, Activity
/// & Undo). A dedicated singleton (not the app delegate) so the menu bar
/// panel always reaches the same instance — NSApp.delegate is not always
/// the adaptor instance in every launch mode.
@MainActor
final class AuxiliaryWindowController {
    static let shared = AuxiliaryWindowController()
    private var settingsWindow: NSWindow?
    private var activityWindow: NSWindow?
    private var planWindow: NSWindow?
    private var planDelegate: PlanWindowDelegate?
    private var planWatchPath: String = ""

    func openSettings() {
        let window = settingsWindow ?? makeWindow(
            title: "Sortilege Settings",
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            view: SettingsWindow())
        settingsWindow = window
        bringToFront(window)
    }

    func openActivity() {
        let window = activityWindow ?? makeWindow(
            title: "Activity & Undo",
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
            view: ActivityWindow())
        activityWindow = window
        bringToFront(window)
    }

    /// Plan review window for a newly selected folder. Replaces any
    /// previous plan window so only one review is ever open. Closing the
    /// window (red button) cancels the plan, same as the Cancel button.
    func openPlanReview(watchPath: String, entries: [PreviewReport.Entry],
                        remainingCount: Int = 0, isCollecting: Bool = false) {
        planWindow?.close()
        planWatchPath = watchPath
        let delegate = PlanWindowDelegate(onClose: cancelPlanSelection)
        let window = makeWindow(
            title: "Review Sort Plan",
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            view: PlanReviewWindow(watchPath: watchPath, entries: entries,
                                   remainingCount: remainingCount,
                                   isCollecting: isCollecting,
                                   onCancel: cancelPlanSelection))
        window.delegate = delegate
        planWindow = window
        planDelegate = delegate
        bringToFront(window)
    }

    /// Opens the plan window immediately in its "collecting" state so the
    /// user sees progress on big folders instead of nothing.
    func openPlanReviewCollecting(watchPath: String) {
        openPlanReview(watchPath: watchPath, entries: [], isCollecting: true)
    }

    /// Flips an open collecting plan window to the finished plan.
    func finishPlanReview(entries: [PreviewReport.Entry], remainingCount: Int) {
        guard let window = planWindow else { return }
        window.contentView = NSHostingView(rootView: PlanReviewWindow(
            watchPath: planWatchPath,
            entries: entries, remainingCount: remainingCount,
            isCollecting: false, onCancel: cancelPlanSelection))
        bringToFront(window)
    }

    /// Closes the plan review window WITHOUT cancelling (used by the
    /// Start Sorting button). The plan window is not a SwiftUI scene, so
    /// dismiss() inside it cannot close it.
    func closePlanReview() {
        // Detach the delegate first: closing the window here is a
        // confirmation, not a cancel.
        planWindow?.delegate = nil
        planDelegate = nil
        planWindow?.close()
        planWindow = nil
    }

    /// Full cancel: clears both folder selections, stops watching, and
    /// returns the app to its first-run state ("Set…" in the dropdown).
    private func cancelPlanSelection() {
        planWindow?.delegate = nil
        planDelegate = nil
        planWindow?.close()
        planWindow = nil
        AppSettings.shared.clearAllFolders()
        SortEngine.shared.cancelPlan()
    }

    private func makeWindow(title: String, contentRect: NSRect, view: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: view)
        return window
    }

    /// Accessory apps don't come forward on their own, and they deactivate
    /// when the MenuBarExtra dropdown closes — a .normal level window is
    /// then pushed behind the frontmost app immediately. The dropdown panel
    /// itself behaves like a popup menu and lives far above .floating. The
    /// window is kept just above the popup-menu level while open: it
    /// appears in front of the still-open panel and stays in front of
    /// every ordinary app window until closed.
    private func bringToFront(_ window: NSWindow) {
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        // Re-front once more after the panel has finished dismissing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak window] in
            guard let window = window, window.isVisible else { return }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// Window delegate for the plan review window: treats a user close of the
/// window as cancelling the folder selection.
final class PlanWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
