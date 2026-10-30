//
//  Components.swift
//  Sortilege
//
//  Small shared building blocks for the app's windows and menu panel.
//

import SwiftUI

// MARK: - Card

extension View {
    /// Rounded, softly filled container used to group related rows.
    func card(padding: CGFloat = 10) -> some View {
        self
            .padding(padding)
            .background(.quaternary.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Tile button

/// Icon-over-label button for the action row of the menu panel.
struct TileButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(TileLabelStyle())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(configuration.isPressed ? 0.9 : 0.4)))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct TileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tint)
            configuration.title
                .font(.caption2)
        }
    }
}

// MARK: - Status dot

/// Small colored dot, optionally pulsing, for the engine state.
struct StatusDot: View {
    let color: Color
    var pulsing = false
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .scaleEffect(pulsing && pulse ? 2.0 : 1)
                    .opacity(pulsing && pulse ? 0 : 1))
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Folder category styling

enum FolderStyle {
    /// SF Symbol for a destination folder name.
    static func symbol(for folder: String) -> String {
        switch folder.lowercased() {
        case "documents":     return "doc.text"
        case "spreadsheets":  return "tablecells"
        case "presentations": return "rectangle.on.rectangle"
        case "photos":        return "photo"
        case "screenshots":   return "camera.viewfinder"
        case "graphics":      return "paintpalette"
        case "videos":        return "film"
        case "audio":         return "waveform"
        case "installers":    return "shippingbox"
        case "archives":      return "archivebox"
        case "code":          return "chevron.left.forwardslash.chevron.right"
        default:              return "folder"
        }
    }
}
