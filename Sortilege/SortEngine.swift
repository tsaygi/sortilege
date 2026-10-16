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
    @Published var lastError: String?

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

    private init() {
        loadHistory()
    }

    // MARK: Lifecycle

    /// Called once at app launch.
    func start() {
        aiAvailable = ai.isAvailable
        reload()
    }

    /// Re-reads settings and (re)starts watching. Call after the user
    /// changes folders, or after the first folder is granted.
    func reload() {
        stopWatcher()
        stopTimer()

        watchURL = Settings.shared.resolveWatchFolder()
        destURL = Settings.shared.resolveDestFolder() ?? watchURL
        watchPath = watchURL?.path
        destPath = destURL?.path

        guard let watchURL else { return }
        startWatcher()
        startTimer()
        Task { await scan() }
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
        guard !isScanning, let watchURL else { return }
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

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }

            let name = entry.lastPathComponent
            if name.hasPrefix(".") { continue }
            if Self.inFlightExtensions.contains(entry.pathExtension.lowercased()) { continue }
            if skipPaths.contains(entry.path) { continue }

            // Include/ignore filters (extensions, dates, selected paths).
            let fileDate = values.addedToDirectoryDate
                ?? values.contentModificationDate ?? Date()
            if !Settings.shared.shouldProcess(url: entry, fileDate: fileDate) {
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

        if Settings.shared.dryRun {
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
        if let customFolder = Settings.shared.customRuleMatch(url) {
            return (customFolder, "custom")
        }

        // Tier 0.5 — Apple Intelligence multimodal (macOS 27+): the model
        // looks at the image itself: screenshot vs photo vs graphic.
        if Settings.shared.useAI, RuleClassifier.isImage(url),
           ai.isMultimodalAvailable,
           let imageCategory = await ai.classifyImage(at: url) {
            return (imageCategory.folderName, "AI")
        }

        // Tier 2 — Apple Intelligence reads the actual content.
        if Settings.shared.useAI,
           TextExtractor.textishExtensions.contains(url.pathExtension.lowercased()),
           ai.isAvailable,
           let text = TextExtractor.extract(from: url), !text.isEmpty,
           let aiCategory = await ai.classify(
                filename: url.lastPathComponent, text: text) {
            return (aiCategory.category.folderName, "AI")
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
    /// rest of the session.
    func undo(_ recordID: MoveRecord.ID) {
        guard let index = history.firstIndex(where: { $0.id == recordID }) else { return }
        var entry = history[index]
        guard entry.wasMoved, !entry.undone,
              !entry.sourcePath.isEmpty, !entry.destinationPath.isEmpty else { return }

        let from = URL(fileURLWithPath: entry.destinationPath)
        let backTo = URL(fileURLWithPath: entry.sourcePath)

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
        } catch {
            entry.note = "undo failed: " + error.localizedDescription
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
        defer { isGeneratingPreview = false }

        let entries = await collectPreviewEntries()

        do {
            let reportURL = try PreviewReport.write(
                entries: entries,
                watchPath: watchURL.path,
                destPath: (destURL ?? watchURL).path,
                aiOn: Settings.shared.useAI && ai.isAvailable)
            // NSWorkspace.open hands the file to the default browser; macOS
            // automatically grants the browser read access to this file.
            NSWorkspace.shared.open(reportURL)
        } catch {
            lastError = "Could not create preview report: \(error.localizedDescription)"
        }
    }

    /// Mirrors scan()'s candidate selection, but records what WOULD happen
    /// (including filter skips) instead of moving anything.
    private func collectPreviewEntries() async -> [PreviewReport.Entry] {
        guard let watchURL else { return [] }
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey,
            .addedToDirectoryDateKey
        ]
        guard let items = try? fileManager.contentsOfDirectory(
            at: watchURL, includingPropertiesForKeys: keys) else { return [] }

        var entries: [PreviewReport.Entry] = []
        for entry in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let name = entry.lastPathComponent
            if name.hasPrefix(".") { continue }
            if Self.inFlightExtensions.contains(entry.pathExtension.lowercased()) { continue }
            if let modified = values.contentModificationDate,
               Date().timeIntervalSince(modified) < Self.minAge { continue }

            if skipPaths.contains(entry.path) {
                entries.append(PreviewReport.Entry(
                    fileName: name, sourcePath: entry.path,
                    outcome: .skip(reason: "moved back this session — left untouched")))
                continue
            }

            let fileDate = values.addedToDirectoryDate
                ?? values.contentModificationDate ?? Date()
            if !Settings.shared.shouldProcess(url: entry, fileDate: fileDate) {
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
        }
        return entries
    }

    // MARK: Misc actions

    func openDestination() {
        guard let folder = destURL ?? watchURL else { return }
        NSWorkspace.shared.open(folder)
    }
}
