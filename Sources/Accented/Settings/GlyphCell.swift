import SwiftUI

/// One 36pt glyph tile. Shared by the Characters tab (tap = disable globally) and the palette
/// editor (tap = include in the palette), so the two grids can never drift apart visually.
struct GlyphCell: View {
    let glyph: String
    /// `false` dims the glyph and fills the tile — "present but switched off".
    let isOn: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 20))
                .frame(width: 36, height: 36)
                .opacity(isOn ? 1 : 0.28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isOn ? Color.clear : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
