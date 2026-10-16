//
//  PlanReviewWindow.swift
//  Sortilege
//
//  Shown when the user selects a new folder: lists the planned sort and
//  lets the user start sorting, open the dry-run HTML report, or cancel.
//  The engine stays paused while this window is open.
//

import SwiftUI

// MARK: - Folder plan review window

struct PlanReviewWindow: View {
    let watchPath: String
    let entries: [PreviewReport.Entry]
    /// Invoked when the user cancels the plan (Cancel button or window
    /// close): clears both folder selections and returns the app to its
    /// first-run state.
    var onCancel: () -> Void

    @ObservedObject private var engine = SortEngine.shared

    private var moves: [PreviewReport.Entry] {
        entries.compactMap {
            if case .move = $0.outcome { return $0 }
            return nil
        }
    }

    private var skips: [PreviewReport.Entry] {
        entries.compactMap {
            if case .skip = $0.outcome { return $0 }
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            planList
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundStyle(.tint)
                Text("Review the sort plan").font(.headline)
                Spacer()
            }
            Text("Folder selected: \(watchPath)")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Text("Nothing has been moved yet — sorting is paused until you start it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var planList: some View {
        List {
            Section("\(moves.count) file(s) would move") {
                ForEach(Array(moves.enumerated()), id: \.offset) { _, entry in
                    if case let .move(folder, by, destination) = entry.outcome {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.fileName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(destination)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text("→ \(folder) · \(by)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
            if !skips.isEmpty {
                Section("\(skips.count) file(s) would be skipped") {
                    ForEach(Array(skips.enumerated()), id: \.offset) { _, entry in
                        if case let .skip(reason) = entry.outcome {
                            HStack {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                                Text(entry.fileName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(reason)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            if entries.isEmpty {
                Text("No files to sort in this folder right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                cancel()
            }
            Spacer()
            Button("Open HTML Report") {
                Task { await engine.generatePreviewReport() }
            }
            .disabled(engine.isGeneratingPreview)
            Button("Start Sorting") {
                engine.resume()
                AuxiliaryWindowController.shared.closePlanReview()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private func cancel() {
        AuxiliaryWindowController.shared.closePlanReview()
        onCancel()
    }
}
