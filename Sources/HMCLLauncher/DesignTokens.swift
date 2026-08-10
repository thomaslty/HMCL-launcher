import SwiftUI

/// The window is deliberately plain except in one place: the Start button and
/// the readiness squares. Everything else uses system semantic colours so the
/// app looks like it belongs on the machine.
enum Palette {
    /// A deep moss rather than Minecraft grass-green — reads as "go" without
    /// the costume. Lifted in dark mode so it keeps its weight on black.
    static let go = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.180, green: 0.569, blue: 0.388, alpha: 1)
            : NSColor(srgbRed: 0.122, green: 0.435, blue: 0.290, alpha: 1)
    })

    static let pending = Color.secondary.opacity(0.28)
    static let hairline = Color.primary.opacity(0.08)
}

enum TypeScale {
    /// Rounded, because the version number is the one warm thing on screen.
    static let version = Font.system(size: 34, weight: .semibold, design: .rounded)
    static let eyebrow = Font.system(size: 11, weight: .medium).smallCaps()
    /// Versions, timestamps and paths are data, so they get monospaced digits.
    static let data = Font.system(size: 11, design: .monospaced)
}

/// One filled square per prerequisite. Filled means installed, hollow means the
/// next Start will download it — which is how the 136 MB first run stops being a
/// surprise.
struct ReadinessDot: View {
    let label: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isReady ? Palette.go : Palette.pending)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(isReady ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(isReady ? "ready" : "not downloaded")")
    }
}

/// The single bold object in the window.
struct StartButtonStyle: ButtonStyle {
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.go.opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.35))
            )
            .contentShape(Rectangle())
    }
}
