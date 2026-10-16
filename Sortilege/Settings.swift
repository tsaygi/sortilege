//
//  Settings.swift
//  Sortilege
//
//  Persisted, sandbox-safe settings: security-scoped bookmarks, toggles,
//  custom rules and filters.
//

import Foundation
import ServiceManagement

// MARK: - Settings (persisted, sandbox-safe)

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let watchBookmark = "sortilege.watchBookmark"
        static let destBookmark = "sortilege.destBookmark"
        static let useAI = "sortilege.useAI"
        static let dryRun = "sortilege.dryRun"
        static let history = "sortilege.history"
        static let rules = "sortilege.rules"
        static let filters = "sortilege.filters"
    }

    @Published var watchBookmark: Data?
    @Published var destBookmark: Data?
    @Published var useAI: Bool
    @Published var dryRun: Bool
    @Published var launchAtLogin: Bool {
        didSet { updateLoginItem() }
    }
    /// User-defined rules, checked before built-in rules and Apple Intelligence.
    @Published var customRules: [CustomRule] {
        didSet { persistCustomRules() }
    }
    /// Include/ignore filters applied before any sorting tier.
    @Published var filters: [SortFilter] {
        didSet { persistFilters() }
    }

    private init() {
        watchBookmark = defaults.data(forKey: Key.watchBookmark)
        destBookmark = defaults.data(forKey: Key.destBookmark)
        useAI = defaults.object(forKey: Key.useAI) as? Bool ?? true
        dryRun = defaults.object(forKey: Key.dryRun) as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled

        if let data = defaults.data(forKey: Key.rules),
           let rules = try? JSONDecoder().decode([CustomRule].self, from: data) {
            customRules = rules
        } else {
            customRules = []
        }
        if let data = defaults.data(forKey: Key.filters),
           let savedFilters = try? JSONDecoder().decode([SortFilter].self, from: data) {
            filters = savedFilters
        } else {
            filters = []
        }
    }

    // MARK: Folder management (security-scoped bookmarks)

    func setWatchFolder(_ url: URL) {
        watchBookmark = try? url.bookmarkData()
        defaults.set(watchBookmark ?? Data(), forKey: Key.watchBookmark)
    }

    func setDestFolder(_ url: URL) {
        destBookmark = try? url.bookmarkData()
        defaults.set(destBookmark ?? Data(), forKey: Key.destBookmark)
    }

    func clearDestFolder() {
        destBookmark = nil
        defaults.removeObject(forKey: Key.destBookmark)
    }

    func resolveWatchFolder() -> URL? {
        guard let data = watchBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                  options: [], relativeTo: nil,
                                  bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            watchBookmark = fresh
            defaults.set(fresh, forKey: Key.watchBookmark)
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    func resolveDestFolder() -> URL? {
        guard let data = destBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                  options: [], relativeTo: nil,
                                  bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            destBookmark = fresh
            defaults.set(fresh, forKey: Key.destBookmark)
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    // MARK: Toggles

    func persistToggles() {
        defaults.set(useAI, forKey: Key.useAI)
        defaults.set(dryRun, forKey: Key.dryRun)
    }

    // MARK: Custom rules

    private func persistCustomRules() {
        if let data = try? JSONEncoder().encode(customRules) {
            defaults.set(data, forKey: Key.rules)
        }
    }

    func addRule() {
        customRules.append(CustomRule())
    }

    func removeRule(_ id: UUID) {
        customRules.removeAll { $0.id == id }
    }

    /// Returns the destination folder name of the first matching custom
    /// rule, or nil when no rule matches.
    func customRuleMatch(_ url: URL) -> String? {
        for rule in customRules where rule.matches(url) {
            return rule.folder.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: Include / ignore filters

    private func persistFilters() {
        if let data = try? JSONEncoder().encode(filters) {
            defaults.set(data, forKey: Key.filters)
        }
    }

    func addFilter() {
        filters.append(SortFilter())
    }

    func removeFilter(_ id: UUID) {
        filters.removeAll { $0.id == id }
    }

    /// Applies all enabled, configured filters. Returns false when the file
    /// should be skipped entirely (never sorted).
    ///
    /// - If any "Only sort files matching" filters exist, the file must
    ///   match at least one of them.
    /// - Any matching "Ignore files matching" filter skips the file.
    func shouldProcess(url: URL, fileDate: Date) -> Bool {
        let active = filters.filter { $0.enabled && $0.isConfigured }
        let allowlist = active.filter { $0.action == .only }
        if !allowlist.isEmpty,
           !allowlist.contains(where: { $0.matches(url, fileDate: fileDate) }) {
            return false
        }
        if active.contains(where: {
            $0.action == .ignore && $0.matches(url, fileDate: fileDate)
        }) {
            return false
        }
        return true
    }

    private func updateLoginItem() {
        // SMAppService is App Store compliant (no deprecated SMLoginItemSetEnabled).
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Sortilege: login item error: \(error.localizedDescription)")
        }
    }
}
