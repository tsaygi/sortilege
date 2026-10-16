//
//  Models.swift
//  Sortilege
//
//  Shared data models: categories, activity history, custom rules, filters.
//

import Foundation

// MARK: - Categories

enum Category: String, CaseIterable {
    case documents, spreadsheets, presentations, photos, videos
    case audio, installers, archives, code, other

    var folderName: String {
        switch self {
        case .documents:     return "Documents"
        case .spreadsheets:  return "Spreadsheets"
        case .presentations: return "Presentations"
        case .photos:        return "Photos"
        case .videos:        return "Videos"
        case .audio:         return "Audio"
        case .installers:    return "Installers"
        case .archives:      return "Archives"
        case .code:          return "Code"
        case .other:         return "Other"
        }
    }
}

// MARK: - History model

/// One entry in the activity log. `wasMoved` is false for dry runs and
/// errors; `undone` flips to true when the user has moved the file back.
struct MoveRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileName: String
    var folder: String
    var decidedBy: String
    var date: Date
    var sourcePath: String
    var destinationPath: String
    var wasMoved: Bool
    var undone: Bool = false
    var note: String?

    init(fileName: String, folder: String, decidedBy: String, date: Date,
         sourcePath: String = "", destinationPath: String = "",
         wasMoved: Bool = true, note: String? = nil) {
        self.fileName = fileName
        self.folder = folder
        self.decidedBy = decidedBy
        self.date = date
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.wasMoved = wasMoved
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id, fileName, folder, decidedBy, date
        case sourcePath, destinationPath, wasMoved, undone, note
    }

    /// Tolerates history written by older versions of the app.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try container.decode(String.self, forKey: .fileName)
        folder = try container.decode(String.self, forKey: .folder)
        decidedBy = try container.decode(String.self, forKey: .decidedBy)
        date = try container.decode(Date.self, forKey: .date)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        destinationPath = try container.decodeIfPresent(String.self, forKey: .destinationPath) ?? ""
        wasMoved = try container.decodeIfPresent(Bool.self, forKey: .wasMoved) ?? true
        undone = try container.decodeIfPresent(Bool.self, forKey: .undone) ?? false
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

// MARK: - Custom rules (highest-priority sorting tier)

/// A user-defined rule: match files by extension or by a keyword in the
/// filename and send them to a folder of the user's choice (created on
/// demand inside the destination root). Custom rules run BEFORE the
/// built-in categories and before Apple Intelligence.
struct CustomRule: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case fileExtension
        case fileNameContains

        var label: String {
            switch self {
            case .fileExtension:     return "Extension"
            case .fileNameContains: return "Name contains"
            }
        }
    }

    var id = UUID()
    var kind: Kind = .fileExtension
    var pattern: String = ""
    var folder: String = ""
    var enabled: Bool = true

    var isValid: Bool {
        !pattern.trimmingCharacters(in: .whitespaces).isEmpty
            && !folder.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func matches(_ url: URL) -> Bool {
        guard enabled, isValid else { return false }
        let needle = pattern.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .fileExtension:
            return url.pathExtension.lowercased() == needle.lowercased()
        case .fileNameContains:
            return url.lastPathComponent.localizedCaseInsensitiveContains(needle)
        }
    }
}

// MARK: - Filters (include / ignore conditions)

/// Decides which files the engine considers AT ALL. Filters run before
/// every sorting tier (custom rules, Apple Intelligence, built-in rules).
///
/// "Only" filters form an allowlist: when any exist, a file must match at
/// least one of them. "Ignore" filters form a blocklist: any match skips
/// the file. Both can be combined freely.
struct SortFilter: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case byExtension
        case byDate
        case byPath

        var label: String {
            switch self {
            case .byExtension: return "Extension"
            case .byDate:     return "Date added"
            case .byPath:     return "File / Folder"
            }
        }
    }

    enum Action: String, Codable, CaseIterable {
        case only
        case ignore

        var label: String {
            switch self {
            case .only:   return "Only sort files matching"
            case .ignore: return "Ignore files matching"
            }
        }
    }

    var id = UUID()
    var kind: Kind = .byExtension
    var action: Action = .ignore
    var enabled: Bool = true

    /// byExtension: comma-separated extension list ("png, gif, webp").
    var extensions: String = ""
    /// byDate: cutoff date. Matches when the file's added/modified date is
    /// after (true) or before (false) the cutoff.
    var cutoff: Date = Date()
    var after: Bool = true
    /// byPath: absolute paths of user-selected files or folders. A folder
    /// matches every file inside it (prefix match).
    var paths: [String] = []

    var isConfigured: Bool {
        switch kind {
        case .byExtension:
            return !extensions.trimmingCharacters(in: .whitespaces).isEmpty
        case .byDate:
            return true
        case .byPath:
            return !paths.isEmpty
        }
    }

    func matches(_ url: URL, fileDate: Date) -> Bool {
        switch kind {
        case .byExtension:
            let list = extensions
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            return list.contains(url.pathExtension.lowercased())
        case .byDate:
            return after ? fileDate > cutoff : fileDate < cutoff
        case .byPath:
            return paths.contains { path in
                url.path == path || url.path.hasPrefix(path + "/")
            }
        }
    }
}
