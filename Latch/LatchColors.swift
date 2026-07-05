import SwiftUI

/// The Latch design tokens (SPEC §8 / design handoff) as SwiftUI colors. Hex strings live on the
/// pure `LaneKind` / `TargetHealth` enums (so they stay testable without SwiftUI); this maps them
/// to `Color` and names the surface/text tokens the shell paints with. (PLAN slice 11)
extension Color {
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(cleaned, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension LaneKind {
    var color: Color { Color(hex: colorHex) }
}

extension TargetHealth {
    var color: Color { Color(hex: colorHex) }
}

/// Surface, accent, and text tokens from the handoff. Grouped so the views read
/// `LatchTheme.window` etc. rather than sprinkling hex literals. (SPEC §8 Design Tokens)
enum LatchTheme {
    static let window = Color(hex: "#17171b")
    static let sidebar = Color(hex: "#1c1c20")
    static let center = Color(hex: "#141418")
    static let laneGutter = Color(hex: "#161619")
    static let rightPanel = Color(hex: "#1a1a1e")
    static let timelineHeader = Color(hex: "#18181c")

    static let teal = Color(hex: "#2DD4BF")
    static let systemBlue = Color(hex: "#0A84FF")

    // Status palette (SPEC §8) — the same values the pure `TargetHealth` enum carries, here as
    // SwiftUI colors for chrome (recording/latched/paused dots).
    static let critical = Color(hex: "#FF453A")
    static let warning = Color(hex: "#FF9F0A")
    static let healthy = Color(hex: "#30D158")

    static let textPrimary = Color(hex: "#ECECEF")
    static let textSecondary = Color(hex: "#c8c8cd")
    static let textMuted = Color(hex: "#8a8a90")
    static let textFaint = Color(hex: "#6c6c72")

    static let hairline = Color.white.opacity(0.07)
    static let chipFill = Color.white.opacity(0.045)
}
