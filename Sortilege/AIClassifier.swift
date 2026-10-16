//
//  AIClassifier.swift
//  Sortilege
//
//  Tier 2: on-device Apple Intelligence classification (Foundation Models).
//  Text classification needs macOS 26+; multimodal image classification
//  needs macOS 27+. Falls back to rules when unavailable.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// String-raw-value enums conform to `Generable` for guided generation.
/// Synthesis only happens on the primary declaration, so the conformance
/// is declared here (inside the availability-guarded region).
@available(macOS 26.0, *)
enum AICategory: String, CaseIterable, Generable {
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

    var category: Category {
        switch self {
        case .document:     return .documents
        case .spreadsheet:  return .spreadsheets
        case .presentation: return .presentations
        case .sourceCode:   return .code
        case .other:        return .other
        }
    }
}

/// Multimodal classification result for image files (macOS 27+).
/// Guided generation forces the model to answer with one of these cases.
@available(macOS 27.0, *)
enum ImageCategory: String, CaseIterable, Generable {
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
#endif

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
            You classify images for a file-organizing app. Categories:
            screenshot — screen captures of app windows, menus, dialogs,
            the desktop, or any user interface;
            photo — real-world photographs taken by a camera (people,
            places, objects, photographed pages);
            graphic — charts, diagrams, logos, illustrations, rendered
            or generated artwork, memes.
            Judge only by what is visible in the image itself.
            """)

        // Multimodal PromptBuilder: text and image Attachment together.
        // If your SDK names the initializer differently (e.g. Attachment(url:)),
        // adjust this one line.
        let result = try? await session.respond(generating: ImageCategory.self) {
            "Classify this image into exactly one category."
            Attachment(imageURL: imageURL)
        }
        return result?.content.folderName
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
            Classify the file described by the user into exactly one category:
            document (letters, reports, manuals, invoices, receipts, ebooks),
            spreadsheet (tabular data, financial data, CSV-like content),
            presentation (slide decks), sourceCode (program source code or
            configuration), or other (none of the above).
            Judge by the actual content, not only the filename.
            """)

        let prompt = """
            Filename: \(filename)

            Content excerpt (first \(text.count) characters):
            \(text)
            """

        // Guided generation: the response is a strongly-typed AICategory.
        // If your SDK revision makes LanguageModelSession.init throwing,
        // prefix the initializer above with `try`.
        let response = try? await session.respond(to: prompt, generating: AICategory.self)
        return response?.content.category.folderName
        #else
        return nil
        #endif
    }
}
