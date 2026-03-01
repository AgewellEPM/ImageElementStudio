import AppKit
import SwiftUI

struct EmulatorTokenPalette {
    var canvasBackground: Color
    var surfaceBase: Color
    var surfaceElevated: Color
    var surfacePanel: Color
    var surfaceNav: Color
    var textPrimary: Color
    var textSecondary: Color
    var textInverse: Color
    var accentPrimary: Color
    var accentSecondary: Color
    var accentSoft: Color
    var strokeDefault: Color
    var strokeSoft: Color
    var controlRadius: CGFloat
    var panelRadius: CGFloat
    var titleScale: CGFloat
    var metricScale: CGFloat
    var bodyScale: CGFloat

    init(tokens: DesignTokenSet?) {
        let colors = tokens?.colors ?? [:]
        let radius = tokens?.radius ?? [:]
        let typography = tokens?.typography ?? [:]

        canvasBackground = Color(hex: colors["canvas.bg"] ?? "", fallback: Color(nsColor: .windowBackgroundColor))
        surfaceBase = Color(hex: colors["surface.base"] ?? "", fallback: Color.white)
        surfaceElevated = Color(hex: colors["surface.elevated"] ?? "", fallback: Color.white.opacity(0.95))
        surfacePanel = Color(hex: colors["surface.panel"] ?? "", fallback: Color.white.opacity(0.92))
        surfaceNav = Color(hex: colors["surface.nav"] ?? "", fallback: Color.white.opacity(0.9))
        textPrimary = Color(hex: colors["text.primary"] ?? "", fallback: .primary)
        textSecondary = Color(hex: colors["text.secondary"] ?? "", fallback: .secondary)
        textInverse = Color(hex: colors["text.inverse"] ?? "", fallback: .white)
        accentPrimary = Color(hex: colors["accent.primary"] ?? "", fallback: .blue)
        accentSecondary = Color(hex: colors["accent.secondary"] ?? "", fallback: .indigo)
        accentSoft = Color(hex: colors["accent.soft"] ?? "", fallback: .blue.opacity(0.18))
        strokeDefault = Color(hex: colors["stroke.default"] ?? "", fallback: .secondary.opacity(0.3))
        strokeSoft = Color(hex: colors["stroke.soft"] ?? "", fallback: .secondary.opacity(0.16))
        controlRadius = CGFloat(radius["control"] ?? 10)
        panelRadius = CGFloat(radius["panel"] ?? 14)
        titleScale = CGFloat(Self.typographyScale(from: typography["title"], base: 20))
        metricScale = CGFloat(Self.typographyScale(from: typography["metric"], base: 24))
        bodyScale = CGFloat(Self.typographyScale(from: typography["body"], base: 13))
    }

    private static func typographyScale(from value: String?, base: Double) -> Double {
        guard let value else { return 1.0 }
        let components = value
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let last = components.last, let size = Double(last), base > 0 {
            return max(0.6, min(1.8, size / base))
        }
        if let numeric = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), base > 0 {
            return max(0.6, min(1.8, numeric / base))
        }
        return 1.0
    }
}
