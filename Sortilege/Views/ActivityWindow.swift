//
//  ActivityWindow.swift
//  Sortilege
//
//  The Activity & Undo window: full history with per-move undo.
//

import SwiftUI

// MARK: - Activity & Undo window

struct ActivityWindow: View {
    @ObservedObject private var engine = SortEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if engine.history.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(engine.history) { record in
                        ActivityRow(record: record)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    private var toolbar: some View {
        HStack {
            Text("Activity & Undo").font(.headline)
            Text("\(engine.history.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Undo All") { engine.undoAll() }
                .disabled(!engine.hasUndoableMoves)
            Button("Clear History") { engine.clearHistory() }
                .disabled(engine.history.isEmpty)
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nothing sorted yet — activity will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        Text("Moved-back files stay untouched for the rest of the session. "
             + "Dry-run and error entries are never moved. "
             + "History is kept on this Mac only.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(8)
    }
}

private struct ActivityRow: View {
    let record: MoveRecord
    @ObservedObject private var engine = SortEngine.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .foregroundStyle(record.undone ? Color.secondary : Color.accentColor)
                    Text(record.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = record.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            statusControl
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        if record.undone { return "arrow.uturn.backward.circle" }
        if !record.wasMoved { return "eye" }
        return "checkmark.circle"
    }

    private var subtitle: String {
        let origin = URL(fileURLWithPath: record.sourcePath)
            .deletingLastPathComponent().lastPathComponent
        let time = record.date.formatted(date: .omitted, time: .shortened)
        let via = record.decidedBy
        return "\(origin.isEmpty ? "?" : origin) → \(record.folder) · \(via) · \(time)"
    }

    @ViewBuilder
    private var statusControl: some View {
        if record.undone {
            Label("Moved back", systemImage: "arrow.uturn.backward")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if record.wasMoved {
            Button("Move Back") { engine.undo(record.id) }
                .controlSize(.small)
        } else {
            Text("no move (dry run)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
