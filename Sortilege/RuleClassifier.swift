//
//  RuleClassifier.swift
//  Sortilege
//
//  Tier 3: extension / UTType-based classification.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Rule-based classifier (tier 3)

enum RuleClassifier {

    private static let installerExtensions: Set<String> = [
        "dmg", "pkg", "mpkg", "iso", "exe", "msi"
    ]

    private static let codeExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "rb", "go", "rs", "java",
        "kt", "c", "cpp", "h", "hpp", "m", "mm", "sh", "zsh", "bash", "pl",
        "php", "css", "scss", "sql", "json", "yaml", "yml", "toml", "xml"
    ]

    static func classify(_ url: URL) -> Category? {
        let ext = url.pathExtension.lowercased()

        if installerExtensions.contains(ext) { return .installers }
        if codeExtensions.contains(ext) { return .code }

        guard let type = UTType(filenameExtension: ext),
              !type.identifier.hasPrefix("dyn.") else { return nil }

        switch type {
        case let t where t.conforms(to: .image):        return .photos
        case let t where t.conforms(to: .movie):        return .videos
        case let t where t.conforms(to: .audio):       return .audio
        case let t where t.conforms(to: .spreadsheet):  return .spreadsheets
        case let t where t.conforms(to: .presentation): return .presentations
        case let t where t.conforms(to: .archive):      return .archives
        case let t where t.conforms(to: .pdf):          return .documents
        case let t where t.conforms(to: .text):         return .documents
        default:                                        return nil
        }
    }

    /// True when the file is an image type (used to route it to the
    /// multimodal Apple Intelligence tier).
    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?
            .conforms(to: .image) ?? false
    }
}
