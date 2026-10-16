//
//  FolderPicker.swift
//  Sortilege
//
//  NSOpenPanel helpers — the sandbox permission grant flow.
//

import AppKit

// MARK: - Folder picker (sandbox permission grant)

enum FolderPicker {
    @MainActor
    static func choose(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        // The confirm button must fit both flows: watching a folder and
        // choosing the destination.
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Multi-select panel for filters: any combination of files and folders.
    @MainActor
    static func chooseMany(message: String) -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = message
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return nil }
        return panel.urls
    }
}
