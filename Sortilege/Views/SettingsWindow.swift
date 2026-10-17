//
//  SettingsWindow.swift
//  Sortilege
//
//  The Settings (⌘,) window: Apple Intelligence toggle, dry run,
//  launch at login, custom rules and filters editors, folders.
//

import SwiftUI

// MARK: - Settings window (⌘,)

struct SettingsWindow: View {
    @ObservedObject private var engine = SortEngine.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Sort using Apple Intelligence", isOn: aiBinding)
                    .disabled(!engine.aiAvailable)
                if engine.aiAvailable {
                    Label("""
                        When enabled, the on-device Apple Intelligence model reads
                        the content of text-bearing files (PDF, text, HTML, CSV)
                        and sorts them as documents, spreadsheets, presentations,
                        code or other — and, on macOS 27+, looks at images to
                        sort them as screenshots, photos or graphics. Runs
                        entirely on-device — nothing leaves your Mac. When
                        disabled, files are sorted by file type and extension
                        rules only.
                        """, systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("""
                        Apple Intelligence is unavailable on this Mac (requires
                        a Mac with Apple Intelligence enabled). Sortilege
                        continues in rules-only mode.
                        """, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Apple Intelligence (optional)")
            }

            Section {
                Toggle("Dry run — log planned moves without moving files",
                       isOn: dryRunBinding)
                Toggle("Paused — stop watching and sorting", isOn: pausedBinding)
                Toggle("Move folders directly", isOn: foldersBinding)
                if settings.sortFolders {
                    Label("""
                        Top-level folders in the watch folder are moved whole into
                        the category folder (classified by name and extension —
                        their contents are never inspected).
                        """, systemImage: "folder.badge.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("""
                        Folders are left at the source without being processed —
                        only top-level files are sorted.
                        """, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sorting behavior")
            }

            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            } header: {
                Text("Startup")
            }

            Section {
                customRulesEditor
            } header: {
                Text("Custom rules (checked first)")
            } footer: {
                Text("Custom rules run before the built-in categories and Apple "
                     + "Intelligence. Matching files go to your folder, created "
                     + "inside the destination on demand.")
            }

            Section {
                filtersEditor
            } header: {
                Text("Filters (include / ignore)")
            } footer: {
                Text("Filters decide which files are considered at all, before "
                     + "rules and AI. “Only sort files matching” builds an "
                     + "allowlist; “Ignore files matching” builds a blocklist. "
                     + "Combined: a file must pass the allowlist, then not hit "
                     + "any blocklist entry.")
            }

            Section {
                ignoredFilesEditor
            } header: {
                Text("Ignored files")
            } footer: {
                Text("Files moved back via Undo are added here automatically "
                     + "and are never sorted again — even after a restart. "
                     + "Remove an entry to let Sortilege sort the file again.")
            }

            Section {
                folderPickers
            } header: {
                Text("Folders")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 580)
    }

    // MARK: Bindings

    private var aiBinding: Binding<Bool> {
        Binding(
            get: { settings.useAI },
            set: { settings.useAI = $0; settings.persistToggles() })
    }

    private var dryRunBinding: Binding<Bool> {
        Binding(
            get: { settings.dryRun },
            set: { settings.dryRun = $0; settings.persistToggles() })
    }

    private var foldersBinding: Binding<Bool> {
        Binding(
            get: { settings.sortFolders },
            set: { settings.sortFolders = $0; settings.persistToggles() })
    }

    private var pausedBinding: Binding<Bool> {
        Binding(
            get: { engine.isPaused },
            set: { paused in
                if paused {
                    engine.pause()
                } else {
                    engine.resume()
                }
            })
    }

    // MARK: Folders

    private var folderPickers: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Watched folder")
                Spacer()
                Text(engine.watchPath ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("Choose…") { chooseWatchFolder() }
            }
            HStack {
                Text("Destination")
                Spacer()
                Text(engine.destPath ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                if settings.destBookmark == nil {
                    Button("Choose…") { chooseDestFolder() }
                } else {
                    Button("Reset to Watch Folder") {
                        settings.clearDestFolder()
                        engine.reload()
                    }
                }
            }
        }
    }

    // MARK: Filters editor

    private var filtersEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.filters.isEmpty {
                Text("No filters — every file in the watch folder is considered. "
                     + "Add a filter to restrict sorting by extension, by the "
                     + "date a file was added, or by selected files/folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($settings.filters) { $filter in
                FilterEditorRow(filter: $filter) {
                    settings.removeFilter(filter.id)
                }
            }
            Button {
                settings.addFilter()
            } label: {
                Label("Add Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Custom rules editor

    private var customRulesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.customRules.isEmpty {
                Text("No custom rules yet. Example: extension “dmg” → “Installers”, "
                     + "or name contains “invoice” → “Invoices”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($settings.customRules) { $rule in
                RuleEditorRow(rule: $rule) {
                    settings.removeRule(rule.id)
                }
            }
            Button {
                settings.addRule()
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
        }
        .padding(.vertical, 2)
    }

    private var ignoredFilesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.ignoredPaths.isEmpty {
                Text("No ignored files. When you move a file back with Undo, "
                     + "it is added here so it is never sorted again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.ignoredPaths, id: \.self) { path in
                HStack {
                    Image(systemName: pathIcon(path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text((path as NSString).lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Allow Again") {
                        settings.removeIgnoredPath(path)
                    }
                    .controlSize(.small)
                    Button(role: .destructive) {
                        settings.removeIgnoredPath(path)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func pathIcon(_ path: String) -> String {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return isDirectory.boolValue ? "folder" : "doc"
    }

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

/// One editable custom rule row: match type, pattern, target folder,
/// enable toggle, and delete button.
private struct RuleEditorRow: View {
    @Binding var rule: CustomRule
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("Match", selection: $rule.kind) {
                    ForEach(CustomRule.Kind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                .fixedSize()

                Spacer()
                Toggle("Enabled", isOn: $rule.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 6) {
                TextField(placeholder, text: $rule.pattern)
                    .frame(minWidth: 90, maxWidth: 160)
                    .fixedSize()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Folder (e.g. Invoices)", text: $rule.folder)
            }
            if !rule.isValid && !(rule.pattern.isEmpty && rule.folder.isEmpty) {
                Text("Fill in both fields to activate this rule.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var placeholder: String {
        rule.kind == .fileExtension ? "dmg" : "invoice"
    }
}

/// One editable include/ignore filter row. The editor changes shape with
/// the filter kind: extension list, date + after/before, or a picker for
/// selected files and folders.
private struct FilterEditorRow: View {
    @Binding var filter: SortFilter
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Kind", selection: $filter.kind) {
                    ForEach(SortFilter.Kind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .fixedSize()

                Spacer()
                Toggle("Enabled", isOn: $filter.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            Picker("Action", selection: $filter.action) {
                ForEach(SortFilter.Action.allCases, id: \.self) { action in
                    Text(action.label).tag(action)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            kindEditor
        }
        .padding(8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var kindEditor: some View {
        switch filter.kind {
        case .byExtension:
            TextField("Extensions, comma-separated (e.g. png, gif, webp)",
                      text: $filter.extensions)
        case .byDate:
            HStack {
                DatePicker("Date added", selection: $filter.cutoff)
                    .labelsHidden()
                Picker("Direction", selection: $filter.after) {
                    Text("after").tag(true)
                    Text("before").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 140)
                .fixedSize()
                .labelsHidden()
            }
        case .byPath:
            VStack(alignment: .leading, spacing: 4) {
                if filter.paths.isEmpty {
                    Text("Nothing selected yet — files or folders picked here "
                         + "are matched exactly (folders match their contents).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(filter.paths, id: \.self) { path in
                    HStack {
                        Image(systemName: pathIcon(path))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            filter.paths.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Select Files or Folders…") { selectPaths() }
                    .controlSize(.small)
            }
        }
    }

    private func pathIcon(_ path: String) -> String {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return isDirectory.boolValue ? "folder" : "doc"
    }

    private func selectPaths() {
        if let urls = FolderPicker.chooseMany(
            message: "Select files or folders this filter should match.") {
            for url in urls where !filter.paths.contains(url.path) {
                filter.paths.append(url.path)
            }
        }
    }
}
