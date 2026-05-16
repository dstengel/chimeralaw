// DiffFlowLayout.swift
// Chimera Law
// Pure layout and bridge-rendering primitives for the diff word-flow view.
// Extracted from DiffView.swift to keep that file focused on token rendering.
// No ViewModel dependency — these are display-only structs.

import SwiftUI
import CoreText
import UIKit

// MARK: - Color Constants

extension Color {
    // AI changes
    static let aiInserted = Color.blue
    static let aiDeleted = Color.red

    // User changes (distinct variants)
    static let userInserted = Color(red: 0.43, green: 0.54, blue: 0.98)
    static let userDeleted = Color(red: 0.6, green: 0.0, blue: 0.0)

    // AI-inserted then user-deleted (orange)
    static let aiThenUserDeleted = Color.orange
}

// MARK: - Flow Layout (iOS 16+)

/// Custom Layout that flows child views like wrapped text.
/// Newline sentinel tokens trigger a paragraph break (line reset).
struct DiffFlowContainer: Layout {

    let wordSpacing: CGFloat = 5
    let lineSpacing: CGFloat = 4
    let paragraphSpacing: CGFloat = 12

    /// Layout values attached to each subview to signal whether it is a
    /// newline sentinel. Set via `DiffTokenView.layoutNewline`.
    struct IsNewlineKey: LayoutValueKey {
        static let defaultValue: Bool = false
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return computeLayout(maxWidth: maxWidth, subviews: subviews).totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(maxWidth: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x,
                             y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(maxWidth: CGFloat, subviews: Subviews)
        -> (positions: [CGPoint], totalSize: CGSize)
    {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let isNewline = subview[IsNewlineKey.self]

            if isNewline {
                // Paragraph break: reset to start of next line with extra spacing.
                if lineHeight > 0 {
                    y += lineHeight + paragraphSpacing
                } else {
                    y += paragraphSpacing
                }
                x = 0
                lineHeight = 0
                // Place the sentinel off-screen (zero size, invisible).
                positions.append(CGPoint(x: 0, y: y))
                continue
            }

            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + wordSpacing
        }

        return (positions, CGSize(width: maxWidth, height: y + lineHeight))
    }
}

// MARK: - Bridge Preference Plumbing

/// One changed token's frame (in the `diffFlow` coordinate space) plus the
/// metadata the overlay needs to decide whether to bridge it to a neighbour.
struct DiffBridgeItem {
    let tokenId: UUID
    let tokenIndex: Int
    let groupId: UUID
    let type: DiffTokenType
    let source: DiffTokenSource?
    let frame: CGRect
}

struct DiffBridgePreferenceKey: PreferenceKey {
    static var defaultValue: [DiffBridgeItem] = []
    static func reduce(value: inout [DiffBridgeItem], nextValue: () -> [DiffBridgeItem]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Bridge Overlay

/// Draws a thin rectangle across the inter-word gap between two same-group,
/// same-line tokens. Colour and thickness mirror the native SwiftUI
/// decoration painted on the words themselves.
struct DiffBridgeOverlay: View {

    let items: [DiffBridgeItem]

    var body: some View {
        let bridges = computeBridges(from: items)
        ZStack(alignment: .topLeading) {
            // A zero-size anchor so the ZStack establishes a top-leading
            // origin even when there are no bridges.
            Color.clear.frame(width: 0, height: 0)
            ForEach(bridges) { bridge in
                Rectangle()
                    .fill(bridge.color)
                    .frame(width: bridge.rect.width, height: bridge.rect.height)
                    .offset(x: bridge.rect.minX, y: bridge.rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Bridge computation

    private func computeBridges(from items: [DiffBridgeItem]) -> [DiffBridge] {
        guard !items.isEmpty else { return [] }

        // Font metrics. `.dkBody` resolves to system size 17 regular. Use
        // toll-free bridging (`uiFont as CTFont`) rather than
        // CTFontCreateWithName, so the underline/x-height values match the
        // actual SF optical variant SwiftUI is rendering.
        let uiFont = UIFont.systemFont(ofSize: 17, weight: .regular)
        let ctFont = uiFont as CTFont
        let ascent = CTFontGetAscent(ctFont)
        let underlinePosition = CTFontGetUnderlinePosition(ctFont) // typically negative (below baseline)
        let rawThickness = CTFontGetUnderlineThickness(ctFont)
        let thickness = max(rawThickness, 1)
        let xHeight = CTFontGetXHeight(ctFont)

        // Empirical vertical nudge for the UNDERLINE bridge only.
        let underlineBaselineNudge: CGFloat = 3.0

        // Two frames are "on the same line" if their vertical centres are
        // within this tolerance (absorbs subpixel layout rounding).
        let lineTolerance: CGFloat = 1.5

        var bridges: [DiffBridge] = []

        let groups = Dictionary(grouping: items, by: { $0.groupId })
        for (_, groupItems) in groups {
            let ordered = groupItems.sorted { $0.tokenIndex < $1.tokenIndex }
            guard ordered.count >= 2 else { continue }

            for i in 0..<(ordered.count - 1) {
                let a = ordered[i]
                let b = ordered[i + 1]

                guard abs(a.frame.midY - b.frame.midY) < lineTolerance else { continue }

                let left = a.frame.maxX
                let right = b.frame.minX
                guard right > left else { continue }

                let baseline = a.frame.minY + ascent
                let rect: CGRect
                switch a.type {
                case .inserted:
                    let strokeTop = baseline - underlinePosition + underlineBaselineNudge
                    let centerY = strokeTop + thickness / 2
                    rect = CGRect(
                        x: left,
                        y: centerY - thickness / 2,
                        width: right - left,
                        height: thickness
                    )
                case .deleted:
                    let centerY = baseline - xHeight / 2
                    rect = CGRect(
                        x: left,
                        y: centerY - thickness / 2,
                        width: right - left,
                        height: thickness
                    )
                case .equal:
                    continue
                }

                bridges.append(DiffBridge(
                    id: "\(a.tokenId.uuidString)->\(b.tokenId.uuidString)",
                    rect: rect,
                    color: bridgeColor(type: a.type, source: a.source)
                ))
            }
        }
        return bridges
    }

    private func bridgeColor(type: DiffTokenType, source: DiffTokenSource?) -> Color {
        switch type {
        case .inserted:
            return source == .user ? Color.userInserted : Color.aiInserted
        case .deleted:
            switch source {
            case .aiThenUser: return Color.aiThenUserDeleted
            case .user:       return Color.userDeleted
            default:          return Color.aiDeleted
            }
        case .equal:
            return .clear
        }
    }
}

struct DiffBridge: Identifiable {
    let id: String
    let rect: CGRect
    let color: Color
}
