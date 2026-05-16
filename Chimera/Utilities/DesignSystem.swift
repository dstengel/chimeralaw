// DesignSystem.swift
// Chimera Law
// Brand palette derived from lambsdorff.law: black/white primary,
// burgundy as the principal accent, olive as the secondary accent,
// warm gray for secondary text. Token names retain the historical
// `dk` prefix for diff hygiene; rename later if desired.

import SwiftUI

// MARK: - Colors (Adaptive Light/Dark)

extension Color {

    // Primary: Burgundy (lambsdorff.law section accent #823542)
    // Used for buttons, lock pill, primary CTAs, focus rings.
    static let dkPrimary = Color(light: "823542", dark: "B86D7E")

    // Accent: Olive (lambsdorff.law section accent #5D683E)
    // Used for "Analysis ready" pill, secondary CTAs, highlights.
    static let dkAccent = Color(light: "5D683E", dark: "9CAB72")

    // Background: Pure white / pure black
    static let dkBackground = Color(light: "FFFFFF", dark: "000000")

    // Surface: Light neutral gray (lambsdorff section bg #F0F0F0) /
    // standard iOS dark surface
    static let dkSurface = Color(light: "F0F0F0", dark: "1C1C1E")

    // Secondary: Slightly darker surface variant
    static let dkSecondary = Color(light: "E6E6E6", dark: "2C2C2E")

    // Elevated surface (modals, sheets)
    static let dkElevated = Color(light: "FFFFFF", dark: "2C2C2E")

    // Text — pure black/white primary, warm gray secondary (#635B5B)
    static let dkTextPrimary = Color(light: "000000", dark: "FFFFFF")
    static let dkTextSecondary = Color(light: "635B5B", dark: "9C9290")

    // Feedback (kept consistent with iOS conventions; warning shifted
    // slightly warmer to sit better next to the burgundy primary)
    static let dkError = Color(hex: "EF4444")
    static let dkSuccess = Color(hex: "22C55E")
    static let dkWarning = Color(light: "D9A300", dark: "FBBF24")

    // MARK: - Hex Initializer (static, non-adaptive)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: - Adaptive Initializer

    init(light lightHex: String, dark darkHex: String) {
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(Color(hex: darkHex))
                : UIColor(Color(hex: lightHex))
        })
    }
}

// MARK: - Layout Constants

enum DKLayout {
    static let gridSpacing: CGFloat = 8
    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let subSectionSpacing: CGFloat = 12
    static let itemSpacing: CGFloat = 8
    static let buttonHeight: CGFloat = 52

    // MARK: - Drawer row (bias selector + Fixes button)

    /// Uniform height for every interactive element in the drawer row
    /// (bias-selector pills and the Fixes button). Matches the
    /// `compact: true` HeatSelector minHeight so all controls in the row
    /// align visually.
    static let drawerRowHeight: CGFloat = 40

    /// Full capsule corner radius (height / 2). Applied to the Fixes
    /// button to match the bias-selector pill capsule.
    static let drawerRowCornerRadius: CGFloat = 20

    /// SF symbol size for the `wand.and.stars` icon on the Fixes button.
    /// Tuned so the icon reads at parity with a 14pt label without
    /// dominating the row.
    static let fixesIconSize: CGFloat = 14
}

// MARK: - Font Extensions

extension Font {
    // Headlines use the system serif design to mirror the firm's
    // serif headline typography (lambsdorff.law). Body, captions,
    // labels and monospace stay sans-serif so the dense drafting
    // surface remains comfortable to edit in.

    /// Large title for splash/onboarding
    static let dkLargeTitle = Font.system(.largeTitle, design: .serif, weight: .bold)

    /// Screen titles
    static let dkHeadline = Font.system(.title2, design: .serif, weight: .bold)

    /// Section headers
    static let dkSubheadline = Font.system(.headline, design: .serif, weight: .semibold)

    /// Body text
    static let dkBody = Font.system(size: 17, weight: .regular, design: .default)

    /// Captions and secondary text
    static let dkCaption = Font.system(size: 15, weight: .regular, design: .default)

    /// Small labels (selectors, counters)
    static let dkLabel = Font.system(size: 14, weight: .medium, design: .default)

    /// Monospaced (character counts, codes)
    static let dkMono = Font.system(size: 15, weight: .regular, design: .monospaced)
}

// MARK: - View Modifiers

struct DKCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DKLayout.cardPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius))
    }
}

extension View {
    func dkCard() -> some View {
        modifier(DKCardModifier())
    }
}

// MARK: - Button Styles

struct DKPrimaryButtonStyle: ButtonStyle {
    let isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dkBody.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: DKLayout.buttonHeight)
            .background(
                isEnabled
                    ? Color.dkPrimary
                    : Color.dkPrimary.opacity(0.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct DKSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dkBody.weight(.medium))
            .foregroundColor(.dkPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: DKLayout.buttonHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Rounded Corner Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
