//
//  MenuBarPanel.swift
//  Sortilege
//
//  The menu bar dropdown UI.
//

import SwiftUI

// MARK: - Menu bar UI

struct MenuBarPanel: View {
    @ObservedObject private var engine = SortEngine.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = engine.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Divider()

            if engine.isGeneratingPreview {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating HTML report…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let progress = engine.planProgress
                    if progress.total > 0 {
                        ProgressView(value: Double(progress.index) / Double(progress.total))
                            .progressViewStyle(.linear)
                        Text("\(progress.index) of \(progress.total) files analyzed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
            }

            if settings.watchBookmark == nil {
                firstRunPrompt
                Divider()
                settingsRow
            } else {
                folderRows
                Divider()
                settingsRow
                Divider()
                actionButtons
                Divider()
                historySection
            }

            Divider()

            HStack {
                Button {
                    if engine.isPaused {
                        engine.resume()
                    } else {
                        engine.pause()
                    }
                } label: {
                    Label(engine.isPaused ? "Resume" : "Pause",
                          systemImage: engine.isPaused ? "play.fill" : "pause.fill")
                }
                .disabled(settings.watchBookmark == nil)
                Spacer()
                Button("Quit Sortilege") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    // MARK: Header

    private var statusLine: String {
        if engine.isPaused { return "Paused — no files are being moved" }
        if engine.isGeneratingPreview { return "Generating preview report…" }
        if engine.isScanning { return "Scanning…" }
        var line = "Watching in the background · \(engine.movedToday) moved today"
        if let last = engine.lastScanDate {
            line += " · last scan \(last.formatted(date: .omitted, time: .shortened))"
        }
        return line
    }
    private var header: some View {
        HStack(alignment: .center) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sortilege").font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        Text(engine.aiAvailable && settings.useAI ? "AI on" : "Rules")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(.quaternary.opacity(0.5)))
    }

    // MARK: First run

    private var firstRunPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose the folder to watch — usually your Downloads folder.")
                .font(.callout)
            Text("Sortilege moves new files into category folders so they land "
                 + "in a location your backups actually include.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Set…") { chooseWatchFolder() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Folders

    private var folderRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watching").font(.caption).foregroundStyle(.secondary)
                    Text(engine.watchPath ?? "—")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Change…") { chooseWatchFolder() }
                    .controlSize(.small)
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Destination").font(.caption).foregroundStyle(.secondary)
                    Text(engine.destPath ?? "—")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Change…") { chooseDestFolder() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: Settings access

    /// Opens the Settings window. SwiftUI scene machinery (Settings scene,
    /// openWindow) proved unreliable in this MenuBarExtra-only accessory
    /// app, so the settings UI is hosted in a plain NSWindow managed by
    /// the AppDelegate.
    private func openSettingsWindow() {
        AuxiliaryWindowController.shared.openSettings()
    }

    private var settingsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Apple Intelligence")
                    .font(.caption)
                Text(settings.useAI && engine.aiAvailable
                     ? "On — text and images sorted by content"
                     : "Off — rule-based sorting only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings…") { openSettingsWindow() }
                .controlSize(.small)
        }
    }

    // MARK: Actions


    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task { await engine.scan() }
            } label: {
                Label("Scan Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(engine.isPaused || engine.isScanning || engine.isGeneratingPreview)

            // Dry run: simulate the full sort and open an HTML report in
            // the default browser showing where every file would go.
            Button {
                Task { await engine.generatePreviewReport() }
            } label: {
                Label("Preview…", systemImage: "wand.and.stars")
            }
            .disabled(engine.isScanning || engine.isGeneratingPreview)

            Button {
                AuxiliaryWindowController.shared.openActivity()
            } label: {
                Label("Undo…", systemImage: "arrow.uturn.backward")
            }
            .disabled(engine.isScanning || engine.isGeneratingPreview)

            Spacer()

            Button {
                engine.openDestination()
            } label: {
                Label("Open", systemImage: "folder")
            }
        }
        .controlSize(.small)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent activity").font(.caption).foregroundStyle(.secondary)
            if engine.history.isEmpty {
                Text("Nothing sorted yet — drop a file into the watch folder.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(engine.history.prefix(6)) { record in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                        Text(record.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("→ \(record.folder) · \(record.decidedBy)")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: Pickers

    /// Pauses sorting, reloads the engine with the new folder, collects
    /// the plan, and shows the review window. Sorting only starts when the
    /// user accepts the plan.
    private func reviewPlan() {
        NSLog("Sortilege[diag]: reviewPlan — watch=\(engine.watchPath ?? "nil") dest=\(engine.destPath ?? "nil")")
        engine.pause()
        engine.reload()
        AuxiliaryWindowController.shared.openPlanReviewCollecting(
            watchPath: engine.watchPath ?? "")
        Task { @MainActor in
            _ = await engine.collectQuickPlan()
        }
    }

    private func chooseWatchFolder() {
        guard let watchURL = FolderPicker.choose(
            message: "Choose the folder Sortilege should watch (e.g. Downloads).") else {
            return
        }
        // The destination is required before the plan is shown: ask for
        // it right away. Cancelling the destination prompt cancels the
        // whole selection.
        guard let destURL = FolderPicker.choose(
            message: "Choose where \(watchURL.lastPathComponent) files should be sorted into. "
                   + "Tip: pick a folder inside Documents so files get backed up.") else {
            return
        }
        settings.setWatchFolder(watchURL)
        settings.setDestFolder(destURL)
        reviewPlan()
    }

    private func chooseDestFolder() {
        if let url = FolderPicker.choose(
            message: "Choose where category folders should be created. "
                   + "Tip: pick a folder inside Documents so files get backed up.") {
            settings.setDestFolder(url)
            reviewPlan()
        }
    }
}
