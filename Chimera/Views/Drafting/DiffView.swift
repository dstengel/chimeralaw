// DiffView.swift
// Chimera Law
// Renders the word-level diff between Original and current text.
//
// Default (Simple) mode: clean two-way diff, blue/red only, no attribution.
//   Tap-to-revert reverts the tapped change against the Original baseline
//   (delta is treated as a manual edit — see `revertExportToken`).
// Complex mode (opt-in via Settings): three-layer diff with AI/user colour
//   coding. Tap-to-revert respects the AI/user layer semantics.
//
// The mode is controlled by @AppStorage("dk_useComplexDiffView") declared here
// so that toggling in Settings triggers a reactive re-render without involving
// the ViewModel (which cannot own @AppStorage and drive objectWillChange).
//
// Layout and bridge primitives live in DiffFlowLayout.swift.

import SwiftUI
import CoreText
import UIKit

struct DiffView: View {

    @ObservedObject var viewModel: DraftingViewModel

    /// Controls which token set is displayed.
    /// Declared here (not in ViewModel) so @AppStorage change triggers re-render.
    @AppStorage("dk_useComplexDiffView") private var useComplexDiffView: Bool = false

    /// Extra bottom space so content can scroll above the floating pill.
    private let pillClearance: CGFloat = 60

    /// Coordinate space in which bridge frames are measured.
    private let diffCoordinateSpace = "diffFlow"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let tokens = useComplexDiffView ? viewModel.diffTokens : viewModel.exportTokens
                DiffFlowContainer {
                    ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
                        DiffTokenView(
                            token: token,
                            tokenIndex: index,
                            coordinateSpaceName: diffCoordinateSpace
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if useComplexDiffView {
                                    viewModel.revertDiffToken(token)
                                } else {
                                    viewModel.revertExportToken(token)
                                }
                            }
                        }
                        .id(token.id)
                    }
                }
                .coordinateSpace(name: diffCoordinateSpace)
                .overlayPreferenceValue(DiffBridgePreferenceKey.self) { items in
                    DiffBridgeOverlay(items: items)
                        .allowsHitTesting(false)
                }
                .padding(.vertical, 4)
                .padding(.bottom, pillClearance)
            }
            // Scroll to the token affected by undo/redo. Observes a
            // monotonic bump counter so even repeated targets re-trigger.
            .onChange(of: viewModel.scrollTargetBump) { _, _ in
                guard let id = viewModel.scrollTargetTokenId else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Single Diff Token (one word)

private struct DiffTokenView: View {

    let token: DiffToken
    let tokenIndex: Int
    let coordinateSpaceName: String
    let onTap: () -> Void

    /// Whether this token is a newline sentinel.
    private var isNewline: Bool {
        WordDiff.isNewline(token.text)
    }

    var body: some View {
        if isNewline {
            // Invisible zero-size view. The layout key tells DiffFlowContainer
            // to insert a paragraph break at this position.
            Color.clear
                .frame(width: 0, height: 0)
                .layoutValue(key: DiffFlowContainer.IsNewlineKey.self, value: true)
        } else {
            tokenContent
                .layoutValue(key: DiffFlowContainer.IsNewlineKey.self, value: false)
        }
    }

    @ViewBuilder
    private var tokenContent: some View {
        switch token.type {
        case .equal:
            Text(token.text)
                .foregroundColor(.primary)
                .font(.dkBody)
        case .inserted:
            // source == nil (simple mode) → aiInserted (blue), same as AI-inserted.
            let color = token.source == .user ? Color.userInserted : Color.aiInserted
            Text(token.text)
                .foregroundColor(color)
                .underline(true, color: color)
                .font(.dkBody)
                .onTapGesture(perform: onTap)
                .background(bridgeFrameReporter)
        case .deleted:
            // source == nil (simple mode) → aiDeleted (red), same as AI-deleted default.
            let color: Color = {
                switch token.source {
                case .aiThenUser: return .aiThenUserDeleted
                case .user:       return .userDeleted
                default:          return .aiDeleted
                }
            }()
            Text(token.text)
                .foregroundColor(color)
                .strikethrough(true, color: color)
                .font(.dkBody)
                .onTapGesture(perform: onTap)
                .background(bridgeFrameReporter)
        }
    }

    /// Publishes this token's frame + grouping metadata so the overlay can
    /// draw bridge rectangles between same-group neighbours on the same line.
    private var bridgeFrameReporter: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: DiffBridgePreferenceKey.self,
                    value: token.groupId.map { gid in
                        [DiffBridgeItem(
                            tokenId: token.id,
                            tokenIndex: tokenIndex,
                            groupId: gid,
                            type: token.type,
                            source: token.source,
                            frame: geo.frame(in: .named(coordinateSpaceName))
                        )]
                    } ?? []
                )
        }
    }
}
