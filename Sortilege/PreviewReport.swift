//
//  PreviewReport.swift
//  Sortilege
//
//  Self-contained dry-run HTML report: what would move where, decided by
//  which tier, and what filters skipped.
//

import Foundation

// MARK: - Dry-run preview report (HTML)

enum PreviewReport {

    /// One line of the dry-run preview report.
    struct Entry {
        enum Outcome {
            case move(folder: String, decidedBy: String, destination: String)
            case skip(reason: String)
        }

        let fileName: String
        let sourcePath: String
        let outcome: Outcome
    }

    @discardableResult
    static func write(entries: [Entry],
                      watchPath: String,
                      destPath: String,
                      aiOn: Bool) throws -> URL {
        let url = reportURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try render(entries: entries, watchPath: watchPath,
                   destPath: destPath, aiOn: aiOn)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func reportURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Sortilege/preview-report.html")
    }

    private static func render(entries: [Entry],
                               watchPath: String,
                               destPath: String,
                               aiOn: Bool) -> String {
        func esc(_ string: String) -> String {
            string.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        struct MoveRow {
            let entry: Entry
            let folder: String
            let by: String
            let destination: String
        }

        var moves: [MoveRow] = []
        var skips: [Entry] = []
        for entry in entries {
            switch entry.outcome {
            case let .move(folder, by, destination):
                moves.append(MoveRow(entry: entry, folder: folder, by: by, destination: destination))
            case .skip:
                skips.append(entry)
            }
        }

        var folderCounts: [String: Int] = [:]
        for move in moves { folderCounts[move.folder, default: 0] += 1 }
        let chips = folderCounts
            .sorted { $0.key < $1.key }
            .map { "<span class='chip'><b>\(esc($0.key))</b> · \($0.value)</span>" }
            .joined()

        var rows = ""
        for entry in entries {
            switch entry.outcome {
            case let .move(folder, by, destination):
                let badgeClass = by == "AI" ? "ai" : (by == "custom" ? "custom" : "rules")
                rows += """
                <tr>
                  <td class='name'>\(esc(entry.fileName))</td>
                  <td><span class='badge \(badgeClass)'>\(esc(by))</span></td>
                  <td class='arrow'>→</td>
                  <td><b>\(esc(folder))</b><span class='path'>\(esc(destination))</span></td>
                </tr>
                """
            case let .skip(reason):
                rows += """
                <tr class='skipped'>
                  <td class='name'>\(esc(entry.fileName))</td>
                  <td colspan='3'><span class='skiptag'>skipped</span> \(esc(reason))</td>
                </tr>
                """
            }
        }
        if entries.isEmpty {
            rows = """
            <tr><td colspan='4' class='empty'>No files in the watch folder right now —
            drop files in and run the preview again.</td></tr>
            """
        }

        let timestamp = Date().formatted(date: .abbreviated, time: .standard)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>Sortilege — Dry Run Preview</title>
        <style>
          :root { color-scheme: light dark; }
          * { box-sizing: border-box; }
          body { font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
                 margin: 0 auto; max-width: 880px; padding: 36px 24px 64px; }
          h1 { font-size: 24px; margin: 0 0 6px; }
          p.meta { color: gray; margin: 4px 0; font-size: 13px; }
          .summary { margin: 18px 0 8px; padding: 14px 16px; border-radius: 12px;
                     background: rgba(100, 100, 255, 0.08);
                     border: 1px solid rgba(100, 100, 255, 0.22); font-size: 14px; }
          .chips { margin: 6px 0 20px; display: flex; flex-wrap: wrap; gap: 8px; }
          .chip { font-size: 12px; padding: 4px 10px; border-radius: 999px;
                  background: rgba(120, 120, 128, 0.14); }
          table { width: 100%; border-collapse: collapse; }
          th { text-align: left; font-size: 11px; text-transform: uppercase;
               letter-spacing: 0.05em; color: gray; padding: 8px 10px;
               border-bottom: 1px solid rgba(120, 120, 128, 0.35); }
          td { padding: 10px; border-bottom: 1px solid rgba(120, 120, 128, 0.15);
               vertical-align: top; }
          td.name { font-weight: 600; }
          td.arrow { color: gray; }
          td.empty { color: gray; text-align: center; padding: 24px; }
          .path { display: block; color: gray; font-size: 12px; margin-top: 2px;
                  word-break: break-all; }
          .badge { font-size: 11px; font-weight: 600; padding: 2px 8px; border-radius: 6px;
                   white-space: nowrap; }
          .badge.ai { background: rgba(52, 199, 89, 0.18); color: #1d8a3e; }
          .badge.custom { background: rgba(100, 100, 255, 0.16); color: #4b53c9; }
          .badge.rules { background: rgba(120, 120, 128, 0.16); color: gray; }
          tr.skipped td { opacity: 0.6; }
          .skiptag { font-size: 11px; font-weight: 700; text-transform: uppercase;
                     color: #b25e00; margin-right: 4px; }
          footer { margin-top: 24px; color: gray; font-size: 12px; }
        </style>
        </head>
        <body>
          <h1>Sortilege — Dry Run Preview</h1>
          <p class="meta">Simulation only — <b>nothing has been moved</b>.
             Generated \(esc(timestamp)).</p>
          <p class="meta">Watch: \(esc(watchPath)) &nbsp;·&nbsp;
             Destination: \(esc(destPath)) &nbsp;·&nbsp;
             Apple Intelligence: \(aiOn ? "on" : "off / unavailable")</p>

          <div class="summary">
            \(moves.count) file(s) would move &nbsp;·&nbsp; \(skips.count) would be skipped
          </div>
          <div class="chips">\(chips)</div>

          <table>
            <thead>
              <tr><th>File</th><th>Decided by</th><th></th><th>Destination</th></tr>
            </thead>
            <tbody>
            \(rows)
            </tbody>
          </table>

          <footer>
            This report was generated locally by Sortilege. To sort for real, use
            "Scan Now" or let the automatic watcher work. Files are never sent
            anywhere — Apple Intelligence runs on-device.
          </footer>
        </body>
        </html>
        """
    }
}
