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
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = engine.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .card()
            }

            if engine.isGeneratingPreview {
                previewProgress
            }

            if settings.watchBookmark == nil {
                firstRunPrompt
            } else {
                folderRows
                actionButtons
                historySection
            }

            footer
        }
        .padding(14)
        .frame(width: 380)
        .animation(.easeInOut(duration: 0.2), value: engine.isScanning)
        .animation(.easeInOut(duration: 0.2), value: engine.isPaused)
        .animation(.easeInOut(duration: 0.2), value: engine.lastError)
    }

    // MARK: Header

    private var statusColor: Color {
        if engine.isPaused { return .orange }
        if engine.isScanning || engine.isGeneratingPreview { return .blue }
        return .green
    }

    private var statusTitle: String {
        if engine.isPaused { return "Paused" }
        if engine.isGeneratingPreview { return "Generating preview…" }
        if engine.isScanning { return "Sorting…" }
        return "Watching"
    }

    private var statusDetail: String {
        if engine.isPaused { return "No files are being moved" }
        var parts = ["\(engine.movedToday) moved today"]
        if let last = engine.lastScanDate {
            parts.append("last scan \(last.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.gradient,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    StatusDot(color: statusColor,
                              pulsing: engine.isScanning || (!engine.isPaused && settings.watchBookmark != nil))
                    Text(settings.watchBookmark == nil ? "Sortilege" : statusTitle)
                        .font(.headline)
                }
                if settings.watchBookmark != nil {
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        let ai = engine.aiAvailable && settings.useAI
        return Label(ai ? "AI" : "Rules", systemImage: ai ? "sparkles" : "list.bullet")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(ai ? Color.accentColor.opacity(0.18)
                                           : Color.secondary.opacity(0.15)))
            .foregroundStyle(ai ? Color.accentColor : Color.secondary)
            .help(ai ? "Apple Intelligence sorts by content"
                     : "Rule-based sorting only")
    }

    private var previewProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
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
        .card()
    }

    // MARK: First run

    private var firstRunPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose the folder to watch")
                .font(.callout.weight(.medium))
            Text("Usually your Downloads folder. Sortilege moves new files into "
                 + "category folders so they land in a location your backups "
                 + "actually include.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose Folder…") { chooseWatchFolder() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    // MARK: Folders

    private var folderRows: some View {
        VStack(spacing: 0) {
            folderRow(title: "Watching", icon: "eye", path: engine.watchPath,
                      action: chooseWatchFolder)
            Divider().padding(.leading, 30)
            folderRow(title: "Sorted into", icon: "folder", path: engine.destPath,
                      action: chooseDestFolder)
        }
        .card(padding: 8)
    }

    private func folderRow(title: String, icon: String, path: String?,
                           action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "—")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Change", action: action)
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.vertical, 5)
    }

    // MARK: Actions

    private var busy: Bool { engine.isScanning || engine.isGeneratingPreview }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await engine.scan() }
            } label: {
                Label("Sort Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(engine.isPaused || busy)
            .help(engine.isPaused ? "Resume to sort" : "Scan the watch folder now")

            // Dry run: simulate the full sort and open an HTML report in
            // the default browser showing where every file would go.
            Button {
                Task { await engine.generatePreviewReport() }
            } label: {
                Label("Preview", systemImage: "wand.and.stars")
            }
            .disabled(busy)

            Button {
                AuxiliaryWindowController.shared.openActivity()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }

            Button {
                engine.openDestination()
            } label: {
                Label("Open", systemImage: "folder")
            }
        }
        .buttonStyle(TileButtonStyle())
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent activity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !engine.history.isEmpty {
                    Button("See all") { AuxiliaryWindowController.shared.openActivity() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            if engine.history.isEmpty {
                Text("Nothing sorted yet — drop a file into the watch folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(engine.history.prefix(5)) { record in
                        HStack(spacing: 8) {
                            Image(systemName: FolderStyle.symbol(for: record.folder))
                                .font(.caption)
                                .foregroundStyle(record.undone ? Color.secondary : Color.accentColor)
                                .frame(width: 18)
                            Text(record.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(record.folder)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.vertical, 4)
                        .help("\(record.fileName) → \(record.folder) · \(record.decidedBy)")
                    }
                }
                .card(padding: 8)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
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
            .buttonStyle(.borderedProminent)
            .tint(engine.isPaused ? .accentColor : .gray)
            .disabled(settings.watchBookmark == nil)

            Spacer()

            Button {
                AuxiliaryWindowController.shared.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Sortilege")
        }
        .controlSize(.regular)
    }

    // MARK: Pickers

    /// Pauses sorting, reloads the engine with the new folder, collects
    /// the plan, and shows the review window. Sorting only starts when the
    /// user accepts the plan.
    private func reviewPlan() {
        engine.pause()
        engine.reload()
        AuxiliaryWindowController.shared.openPlanReviewCollecting(
            watchPath: engine.watchPath ?? "")
        Task { @MainActor in
            let plan = await engine.collectQuickPlan()
            AuxiliaryWindowController.shared.finishPlanReview(
                entries: plan.entries,
                remainingCount: plan.remainingCount)
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
