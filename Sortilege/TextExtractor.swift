//
//  TextExtractor.swift
//  Sortilege
//
//  Extracts a text excerpt from text-bearing files so Apple Intelligence
//  can classify them by content.
//

import Foundation
import PDFKit

// MARK: - Text extraction (for Apple Intelligence)

enum TextExtractor {

    static let textishExtensions: Set<String> = [
        "pdf", "txt", "text", "rtf", "md", "markdown", "html", "htm",
        "csv", "log", "json", "xml"
    ]

    static func extract(from url: URL, limit: Int = 4000) -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url), let text = document.string,
                  !text.isEmpty else { return nil }
            return String(text.prefix(limit))
        case "rtf", "html", "htm":
            guard let attributed = try? NSAttributedString(
                url: url, options: [:], documentAttributes: nil) else { return nil }
            return String(attributed.string.prefix(limit))
        default:
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.isEmpty else { return nil }
            return String(text.prefix(limit))
        }
    }
}
