//
//  SortEngine.swift
//  Sortilege
//
//  The sorting engine: realtime directory watcher, periodic catch-up scan,
//  three-tier classification, history and undo.
//

import Foundation
import AppKit

// MARK: - Sorting engine

@MainActor
final class SortEngine: ObservableObject {
    static let shared = SortEngine()

    @Published private(set) var history: [MoveRecord] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var watchPath: String?
    @Published private(set) var destPath: String?
    @Published private(set) var aiAvailable = false
    @Published private(set) var isGeneratingPreview = false
    /// Progress while collecting the plan or generating the report:
    /// index = files processed so far, total = candidate count.
    @Published private(set) var planProgress = (index: 0, total: 0)
    /// Plan-review state, published so the review window updates
    /// reactively while collection runs.
    @Published private(set) var isCollectingPlan = false
    @Published private(set) var planEntries: [PreviewReport.Entry] = []
    @Published private(set) var planRemainingCount = 0
    @Published var lastError: String?
    /// True while the user is reviewing the plan for a newly selected
    /// folder. The engine does not scan or move anything while paused.
    @Published private(set) var isPaused = false

    /// Files younger than this are skipped (still downloading / being written).
    static let minAge: TimeInterval = 15
    /// Periodic catch-up scan interval.
    static let periodicInterval: TimeInterval = 60
    /// Debounce after a directory-change event.
    static let debounce: Duration = .seconds(3)

    /// Extensions that usually mean "download still in progress".
    static let inFlightExtensions: Set<String> = [
        "download", "crdownload", "part", "partial", "opdownload", "tmp"
    ]

    private var watchURL: URL?
    private var destURL: URL?
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var debounceTask: Task<Void, Never>?
    private let ai = AIClassifier()
    private let fileManager = FileManager.default

    /// Paths of files the user has moved back via Undo. Skipped for the
    /// rest of the session so they are not automatically re-sorted.
    private var skipPaths: Set<String> = []

    /// Paths already recorded as dry-run entries this session. In dry-run
    /// mode nothing moves, so without this guard every periodic scan would
    /// record the same file into history again and again.
    private var dryRunRecordedPaths: Set<String> = []

    private init() {
        loadHistory()
        // Restore the persisted pause immediately (not just in start()):
        // the menu panel can render before the launch task runs start(),
        // and it must show the true state from the first frame.
        if AppSettings.shared.startPaused {
            isPaused = true
        }
    }

    // MARK: Lifecycle

    /// Called once at app launch.
    func start() {
        aiAvailable = ai.isAvailable
        // Restore the persisted pause: if the user paused sorting before
        // quitting, the engine stays paused after relaunch.
        if AppSettings.shared.startPaused {
            isPaused = true
        }
        reload()
    }

    /// Re-reads settings and (re)starts watching. Call after the user
    /// changes folders, or after the first folder is granted.
    func reload() {
        stopWatcher()
        stopTimer()

        watchURL = AppSettings.shared.resolveWatchFolder()
        destURL = AppSettings.shared.resolveDestFolder() ?? watchURL
        watchPath = watchURL?.path
        destPath = destURL?.path

        guard let watchURL else { return }
        startWatcher()
        startTimer()
        guard !isPaused else { return }
        Task { await scan() }
    }

    /// Pauses automatic sorting (watcher events and timer scans are
    /// ignored while paused). Used while the user reviews the plan for a
    /// newly selected folder.
    func pause() {
        isPaused = true
        AppSettings.shared.startPaused = true
        AppSettings.shared.persistToggles()
    }

    /// Lifts the pause and runs an immediate scan.
    func resume() {
        isPaused = false
        AppSettings.shared.startPaused = false
        AppSettings.shared.persistToggles()
        Task { await scan() }
    }

    /// Full cancel of the folder selection: unpause and reload with no
    /// folders configured — the engine stops watching entirely.
    func cancelPlan() {
        isPaused = false
        reload()
    }

    // MARK: Realtime watcher

    private func startWatcher() {
        guard let watchURL else { return }
        let fd = open(watchURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .global(qos: .utility))

        // The handler must not capture this @MainActor object directly
        // (Sendable closure); hop through the shared main-actor instance.
        source.setEventHandler {
            Task { @MainActor in
                SortEngine.shared.watcherFired()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func stopWatcher() {
        watcher?.cancel()
        watcher = nil
    }

    private func watcherFired() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.scan()
        }
    }

    // MARK: Periodic catch-up

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.periodicInterval,
                                     repeats: true) { _ in
            Task { @MainActor in
                SortEngine.shared.timerTick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func timerTick() {
        Task { await scan() }
    }

    // MARK: Scanning

    func scan() async {
        guard !isPaused, !isScanning, let watchURL else { return }
        isScanning = true
        defer {
            isScanning = false
            lastScanDate = Date()
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey,
            .addedToDirectoryDateKey
        ]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: watchURL, includingPropertiesForKeys: keys) else { return }

        let sortFolders = AppSettings.shared.sortFolders
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }
            // Folders are only considered when "move folders directly" is
            // enabled; otherwise they are left at the source untouched.
            if values.isRegularFile != true && !(sortFolders && values.isDirectory == true) {
                continue
            }

            let name = entry.lastPathComponent
            if name.hasPrefix(".") { continue }
            if Self.inFlightExtensions.contains(entry.pathExtension.lowercased()) { continue }
            if skipPaths.contains(entry.path) { continue }
            if AppSettings.shared.isIgnored(entry.path) { continue }

            // Include/ignore filters (extensions, dates, selected paths).
            let fileDate = values.addedToDirectoryDate
                ?? values.contentModificationDate ?? Date()
            if !AppSettings.shared.shouldProcess(url: entry, fileDate: fileDate) {
                continue
            }

            if let modified = values.contentModificationDate,
               Date().timeIntervalSince(modified) < Self.minAge {
                continue
            }

            await process(entry)
        }
    }

    private func process(_ url: URL) async {
        let (folder, decidedBy) = await classify(url)
        let root = (destURL ?? watchURL)!  // scan() guarantees a watch folder
        let destinationFolder = root.appendingPathComponent(folder)
        let destination = uniqueDestination(
            destinationFolder.appendingPathComponent(url.lastPathComponent))

        if AppSettings.shared.dryRun {
            // Dedupe against history itself (survives restarts), not just
            // this session: the same file with the same planned destination
            // is recorded once. A real move for the same source path clears
            // the dry-run record so it can be planned again later.
            let duplicate = history.contains {
                !$0.wasMoved && $0.sourcePath == url.path
                    && $0.destinationPath == destination.path
            }
            guard !duplicate else { return }
            dryRunRecordedPaths.insert(url.path)
            record(MoveRecord(fileName: url.lastPathComponent,
                              folder: folder,
                              decidedBy: decidedBy,
                              date: Date(),
                              sourcePath: url.path,
                              destinationPath: destination.path,
                              wasMoved: false,
                              note: "dry run — nothing was moved"))
            return
        }

        do {
            try fileManager.createDirectory(at: destinationFolder,
                                            withIntermediateDirectories: true)
            try fileManager.moveItem(at: url, to: destination)
            // The plan is now reality: drop stale dry-run entries for this
            // file so it can be planned again if it ever returns.
            history.removeAll {
                !$0.wasMoved && $0.sourcePath == url.path
            }
            record(MoveRecord(fileName: url.lastPathComponent,
                              folder: folder,
                              decidedBy: decidedBy,
                              date: Date(),
                              sourcePath: url.path,
                              destinationPath: destination.path,
                              wasMoved: true))
        } catch {
            record(MoveRecord(fileName: url.lastPathComponent,
                              folder: folder,
                              decidedBy: decidedBy,
                              date: Date(),
                              wasMoved: false,
                              note: "error: " + error.localizedDescription))
        }
    }

    func classify(_ url: URL) async -> (folder: String, decidedBy: String) {
        // Tier 0 — user-defined custom rules (highest priority).
        if let customFolder = AppSettings.shared.customRuleMatch(url) {
            return (customFolder, "custom")
        }

        // Tier 0.5 — Apple Intelligence multimodal (macOS 27+): the model
        // looks at the image itself: screenshot vs photo vs graphic.
        if AppSettings.shared.useAI, RuleClassifier.isImage(url),
           ai.isMultimodalAvailable,
           let imageFolder = await ai.classifyImage(at: url) {
            return (imageFolder, "AI")
        }

        // Tier 2 — Apple Intelligence reads the actual content.
        if AppSettings.shared.useAI,
           TextExtractor.textishExtensions.contains(url.pathExtension.lowercased()),
           ai.isAvailable,
           let text = TextExtractor.extract(from: url), !text.isEmpty,
           let aiFolder = await ai.classify(
                filename: url.lastPathComponent, text: text) {
            return (aiFolder, "AI")
        }

        // Tier 1 — extension / UTType rules.
        if let rule = RuleClassifier.classify(url) {
            return (rule.folderName, "rules")
        }
        return (Category.other.folderName, "rules")
    }

    private func uniqueDestination(_ destination: URL) -> URL {
        guard fileManager.fileExists(atPath: destination.path) else { return destination }
        let base = destination.deletingPathExtension()
        let ext = destination.pathExtension
        for i in 2...9999 {
            let name = ext.isEmpty
                ? "\(base.lastPathComponent) \(i)"
                : "\(base.lastPathComponent) \(i).\(ext)"
            let candidate = destination.deletingLastPathComponent()
                .appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return destination.deletingLastPathComponent()
            .appendingPathComponent("\(base.lastPathComponent)-\(UUID().uuidString)")
    }

    // MARK: History

    private func record(_ entry: MoveRecord) {
        history.insert(entry, at: 0)
        if history.count > 100 { history.removeLast(history.count - 100) }
        saveHistory()
    }

    var movedToday: Int {
        let calendar = Calendar.current
        return history.filter { calendar.isDateInToday($0.date) }.count
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "sortilege.history"),
              let decoded = try? JSONDecoder().decode([MoveRecord].self, from: data) else {
            history = []
            return
        }
        history = decoded
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "sortilege.history")
        }
    }

    // MARK: Undo

    /// True if at least one move can still be undone.
    var hasUndoableMoves: Bool {
        history.contains { $0.wasMoved && !$0.undone }
    }

    /// Moves a sorted file back to where it came from. Restored files are
    /// added to `skipPaths` so they are not automatically re-sorted for the
    /// rest of the session. Every failure path records a note so nothing
    /// fails silently.
    func undo(_ recordID: MoveRecord.ID) {
        NSLog("Sortilege[diag]: undo called for \(recordID)")
        guard let index = history.firstIndex(where: { $0.id == recordID }) else {
            NSLog("Sortilege[diag]: undo aborted — record not found in history")
            return
        }
        var entry = history[index]

        NSLog("Sortilege[diag]: undo record found: fileName=\(entry.fileName) wasMoved=\(entry.wasMoved) undone=\(entry.undone) src=\(entry.sourcePath) dst=\(entry.destinationPath)")
        guard entry.wasMoved, !entry.undone else {
            if !entry.wasMoved { entry.note = "cannot undo: the file was never moved" }
            history[index] = entry
            saveHistory()
            return
        }

        guard !entry.sourcePath.isEmpty, !entry.destinationPath.isEmpty else {
            entry.note = "cannot undo: missing source or destination path"
            history[index] = entry
            saveHistory()
            return
        }

        let from = URL(fileURLWithPath: entry.destinationPath)
        let backTo = URL(fileURLWithPath: entry.sourcePath)

        // Explicit security-scoped access for both endpoints, from the
        // stored bookmarks. Without an active scope the sandbox makes
        // fileExists return false and moveItem throw.
        var scopes: [URL] = []
        for url in [AppSettings.shared.resolveWatchFolder(),
                    AppSettings.shared.resolveDestFolder()].compactMap({ $0 }) {
            if url.startAccessingSecurityScopedResource() {
                scopes.append(url)
            }
        }
        defer {
            for url in scopes { url.stopAccessingSecurityScopedResource() }
        }

        NSLog("Sortilege[diag]: undo checking source exists at \(from.path): \(fileManager.fileExists(atPath: from.path))")
        guard fileManager.fileExists(atPath: from.path) else {
            // Already moved or deleted elsewhere — don't keep offering undo.
            entry.undone = true
            entry.note = "file no longer exists at the destination"
            skipPaths.insert(entry.sourcePath)
            history[index] = entry
            saveHistory()
            return
        }

        do {
            try fileManager.createDirectory(
                at: backTo.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try fileManager.moveItem(at: from, to: uniqueDestination(backTo))
            entry.undone = true
            skipPaths.insert(entry.sourcePath)
            AppSettings.shared.addIgnoredPath(entry.sourcePath)
            NSLog("Sortilege[diag]: undo succeeded — moved back to \(backTo.path)")
        } catch {
            NSLog("Sortilege[diag]: undo moveItem threw: \(error)")
            entry.note = "undo failed: " + error.localizedDescription
            lastError = "Undo failed for \(entry.fileName): \(error.localizedDescription)"
        }
        history[index] = entry
        saveHistory()
    }

    func undoAll() {
        let ids = history.filter { $0.wasMoved && !$0.undone }.map(\.id)
        for id in ids { undo(id) }
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    // MARK: Dry-run preview report

    /// Runs a full simulated sort — custom rules, Apple Intelligence and
    /// filters all applied, but nothing is moved — then writes a
    /// self-contained HTML report and opens it in the default browser.
    func generatePreviewReport() async {
        guard !isScanning, !isGeneratingPreview else { return }
        guard let watchURL else {
            lastError = "No watch folder selected."
            return
        }
        isGeneratingPreview = true
        lastError = nil
        planProgress = (index: 0, total: 0)
        defer {
            isGeneratingPreview = false
            planProgress = (index: 0, total: 0)
        }

        let entries = await collectPreviewEntries()

        do {
            let reportURL = try PreviewReport.write(
                entries: entries,
                watchPath: watchURL.path,
                destPath: (destURL ?? watchURL).path,
                aiOn: AppSettings.shared.useAI && ai.isAvailable)
            // NSWorkspace.open hands the file to the default browser; macOS
            // automatically grants the browser read access to this file.
            NSWorkspace.shared.open(reportURL)
        } catch {
            lastError = "Could not create preview report: \(error.localizedDescription)"
        }
    }

    /// Mirrors scan()'s candidate selection, but records what WOULD happen
    /// (including filter skips) instead of moving anything.
    /// Collects a QUICK sort plan for the folder-plan review window: only
    /// the first `sampleLimit` candidate files are classified (AI calls can
    /// take seconds per file on big folders); the remaining count is
    /// reported via `remainingCount` so the UI can show "and N more".
    func collectQuickPlan(sampleLimit: Int = 10) async
        -> (entries: [PreviewReport.Entry], remainingCount: Int) {
        guard let watchURL else { return ([], 0) }
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey,
            .addedToDirectoryDateKey
        ]
        guard let items = try? fileManager.contentsOfDirectory(
            at: watchURL, includingPropertiesForKeys: keys) else { return ([], 0) }

        NSLog("Sortilege[diag]: collectQuickPlan start, items=\(items.count)")
        isCollectingPlan = true
        planEntries = []
        planRemainingCount = 0
        defer {
            NSLog("Sortilege[diag]: collectQuickPlan end, entries=\(entries.count) remaining=\(remaining)")
            isCollectingPlan = false
        }

        var entries: [PreviewReport.Entry] = []
        var processed = 0
        var remaining = 0
        let sortFolders = AppSettings.shared.sortFolders
        planProgress = (index: 0, total: 0)

        // First pass: gather candidates cheaply (no AI) so the progress
        // indicator can show a real total before classification begins.
        var candidates: [URL] = []
        for entry in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isRegularFile != true && !(sortFolders && values.isDirectory == true) {
                continue
            }
            let name = entry.lastPathComponent
            if name.hasPrefix(".") { continue }
            if Self.inFlightExtensions.contains(entry.pathExtension.lowercased()) { continue }
            if let modified = values.contentModificationDate,
               Date().timeIntervalSince(modified) < Self.minAge { continue }
            if skipPaths.contains(entry.path) || AppSettings.shared.isIgnored(entry.path) {
                continue
            }
            let fileDate = values.addedToDirectoryDate
                ?? values.contentModificationDate ?? Date()
            if !AppSettings.shared.shouldProcess(url: entry, fileDate: fileDate) {
                continue
            }
            candidates.append(entry)
        }
        let sortFoldersUsed = min(candidates.count, sampleLimit)
        planProgress = (index: 0, total: sortFoldersUsed)

        for entry in candidates {
            let name = entry.lastPathComponent
            if processed < sampleLimit {
                let (folder, decidedBy) = await classify(entry)
                let destination = (destURL ?? watchURL)
                    .appendingPathComponent(folder)
                    .appendingPathComponent(name).path
                entries.append(PreviewReport.Entry(
                    fileName: name, sourcePath: entry.path,
                    outcome: .move(folder: folder, decidedBy: decidedBy,
                                  destination: destination)))
                processed += 1
                planProgress = (index: processed, total: sortFoldersUsed)
            } else {
                remaining += 1
            }
        }
        planEntries = entries
        planRemainingCount = remaining
        return (entries, remaining)
    }

    private func collectPreviewEntries() async -> [PreviewReport.Entry] {
        guard let watchURL else { return [] }
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey,
            .addedToDirectoryDateKey
        ]
        guard let items = try? fileManager.contentsOfDirectory(
            at: watchURL, includingPropertiesForKeys: keys) else { return [] }

        let sortFolders = AppSettings.shared.sortFolders
        var entries: [PreviewReport.Entry] = []

        // Cheap first pass: collect every candidate so the progress bar has
        // a real total before the slow (AI) classification begins.
        var candidates: [(entry: URL, values: URLResourceValues)] = []
        for entry in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isRegularFile != true && !(sortFolders && values.isDirectory == true) {
                continue
            }
            let name = entry.lastPathComponent
            if name.hasPrefix(".") { continue }
            if Self.inFlightExtensions.contains(entry.pathExtension.lowercased()) { continue }
            if let modified = values.contentModificationDate,
               Date().timeIntervalSince(modified) < Self.minAge { continue }
            candidates.append((entry, values))
        }
        planProgress = (index: 0, total: candidates.count)

        var processed = 0
        for candidate in candidates {
            let entry = candidate.entry
            let values = candidate.values
            let name = entry.lastPathComponent

            if skipPaths.contains(entry.path) {
                entries.append(PreviewReport.Entry(
                    fileName: name, sourcePath: entry.path,
                    outcome: .skip(reason: "moved back this session — left untouched")))
                continue
            }
            if AppSettings.shared.isIgnored(entry.path) {
                entries.append(PreviewReport.Entry(
                    fileName: name, sourcePath: entry.path,
                    outcome: .skip(reason: "on the ignored list (Settings → Ignored files)")))
                continue
            }
            let fileDate = values.addedToDirectoryDate
                ?? values.contentModificationDate ?? Date()
            if !AppSettings.shared.shouldProcess(url: entry, fileDate: fileDate) {
                entries.append(PreviewReport.Entry(
                    fileName: name, sourcePath: entry.path,
                    outcome: .skip(reason: "matched an include/ignore filter")))
                continue
            }

            let (folder, decidedBy) = await classify(entry)
            let destination = (destURL ?? watchURL)
                .appendingPathComponent(folder)
                .appendingPathComponent(name).path
            entries.append(PreviewReport.Entry(
                fileName: name, sourcePath: entry.path,
                outcome: .move(folder: folder, decidedBy: decidedBy, destination: destination)))
            processed += 1
            planProgress = (index: processed, total: candidates.count)
        }
        return entries
    }

    // MARK: Misc actions

    func openDestination() {
        guard let folder = destURL ?? watchURL else { return }
        NSWorkspace.shared.open(folder)
    }
}
