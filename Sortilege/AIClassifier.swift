//
//  AIClassifier.swift
//  Sortilege
//
//  Tier 2: on-device Apple Intelligence classification (Foundation Models).
//  Text classification needs macOS 26+; multimodal image classification
//  needs macOS 27+. Falls back to rules when unavailable.
//
//  Classification asks the model to answer with a single keyword and maps
//  it to a category explicitly — no Generable/guided-generation machinery,
//  so this compiles against any FoundationModels SDK revision.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI classification results

/// Categories the on-device model can pick for text-bearing files.
/// The raw values are the exact keywords the model is instructed to answer
/// with; `folderName` is the destination folder.
enum AICategory: String, CaseIterable {
    /// General documents: letters, reports, manuals, invoices, receipts, ebooks.
    case document
    /// Tabular or financial data, CSV-like content, ledgers.
    case spreadsheet
    /// Slide decks and presentations.
    case presentation
    /// Program source code or machine configuration.
    case sourceCode
    /// Anything that is not covered above.
    case other

    var folderName: String {
        switch self {
        case .document:     return Category.documents.folderName
        case .spreadsheet:  return Category.spreadsheets.folderName
        case .presentation: return Category.presentations.folderName
        case .sourceCode:   return Category.code.folderName
        case .other:        return Category.other.folderName
        }
    }
}

/// Categories the on-device model can pick for image files (macOS 27+).
enum ImageCategory: String, CaseIterable {
    /// Screen captures: app windows, menus, dialogs, the desktop, any UI.
    case screenshot
    /// Real-world photographs taken by a camera.
    case photo
    /// Charts, diagrams, logos, illustrations, rendered/generated artwork.
    case graphic

    var folderName: String {
        switch self {
        case .screenshot: return "Screenshots"
        case .photo:      return "Photos"
        case .graphic:    return "Graphics"
        }
    }
}

// MARK: - Classifier

final class AIClassifier {

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    /// True when the on-device model is ready for MULTIMODAL prompts
    /// (image input needs macOS 27+, text-only needs macOS 26+).
    var isMultimodalAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    /// Multimodal classification (macOS 27+): the on-device model looks at
    /// the image itself and decides screenshot / photo / graphic.
    /// Returns the destination folder name, or nil when unavailable.
    func classifyImage(at imageURL: URL) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 27.0, *) else { return nil }
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }

        let session = LanguageModelSession(instructions: """
            You classify images for a file-organizing app.
            Answer with exactly one word, nothing else:
            screenshot — screen captures of app windows, menus, dialogs,
            the desktop, or any user interface;
            photo — real-world photographs taken by a camera (people,
            places, objects, photographed pages);
            graphic — charts, diagrams, logos, illustrations, rendered
            or generated artwork, memes.
            Judge only by what is visible in the image itself.
            """)

        // Multimodal prompt: text and image Attachment together. If your
        // SDK names the initializer differently (e.g. Attachment(url:)),
        // adjust this one line.
        let response = try? await session.respond {
            "Classify this image into exactly one category."
            Attachment(imageURL: imageURL)
        }
        guard let answer = response?.content,
              let category = Self.match(ImageCategory.self, in: answer) else {
            return nil
        }
        return category.folderName
        #else
        return nil
        #endif
    }

    /// Text classification (macOS 26+): the on-device model reads the
    /// file's content and decides the category.
    /// Returns the destination folder name, or nil when unavailable.
    func classify(filename: String, text: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return nil }
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }

        let session = LanguageModelSession(instructions: """
            You are the classification engine of a file-organizing app.
            Answer with exactly one word, nothing else:
            document — letters, reports, manuals, invoices, receipts, ebooks;
            spreadsheet — tabular data, financial data, CSV-like content;
            presentation — slide decks;
            sourceCode — program source code or configuration;
            other — none of the above.
            Judge by the actual content, not only the filename.
            """)

        let prompt = """
            Filename: \(filename)

            Content excerpt (first \(text.count) characters):
            \(text)
            """

        let response = try? await session.respond(to: prompt)
        guard let answer = response?.content,
              let category = Self.match(AICategory.self, in: answer) else {
            return nil
        }
        return category.folderName
        #else
        return nil
        #endif
    }

    /// Maps a free-text model answer to a category. Tolerates stray
    /// punctuation, casing, and surrounding words ("Document.",
    /// "The answer is SOURCECODE").
    private static func match<T: RawRepresentable & CaseIterable>(
        _ type: T.Type, in answer: String
    ) -> T? where T.RawValue == String {
        let words = answer
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        for word in words {
            if let exact = T(rawValue: String(word)) { return exact }
        }
        for candidate in type.allCases as? [T] ?? [] {
            let raw = candidate.rawValue
            if answer.lowercased().contains(raw) { return candidate }
        }
        return nil
    }
}
