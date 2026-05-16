// FixesButton.swift
// Chimera Law
// The "Revise" button that lives in the drawer row, replacing the former
// active-style pill. Borderless text-only label. The only state cue beyond
// label colour is an indigo capsule ring drawn around the button when
// revisions are cached for the current clause.
//
// The in-flight signal lives on the grabber bar — not on this button —
// so that the user can see "background work in progress" while the
// drawer is collapsed. While in flight the button is disabled
// (non-tappable) but does not show a spinner.

import SwiftUI

struct FixesButton: View {

    @ObservedObject var viewModel: DraftingViewModel

    /// Closure fired on tap. Lives on the parent so the parent owns the
    /// post-tap navigation (sheet present, banner dismiss, etc.).
    var onTap: () -> Void

    var body: some View {
        Button(action: handleTap) {
            Text("Revise")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(state.labelColor)
                .padding(.horizontal, 14)
                .frame(height: DKLayout.drawerRowHeight)
                .background(
                    Capsule()
                        .fill(Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(state.ringColor, lineWidth: state.ringWidth)
                )
                .contentShape(Capsule())
        }
        .disabled(!state.isEnabled)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
    }

    // MARK: - Tap

    private func handleTap() {
        // Defensive: the button is disabled in this state but the
        // accessibility hit area can still fire. Guard with the
        // view-model's own gate so callers don't have to.
        guard state.isEnabled else { return }
        onTap()
    }

    // MARK: - State resolution

    /// Single source of truth for the button's appearance and
    /// enabled-ness. Mirrors the §4.2 state table from the design plan.
    private var state: ButtonState {
        if viewModel.isLoading {
            return .disabledRedraftInFlight
        }
        if viewModel.isAnyTellMeWorkInFlight {
            return .inFlight
        }
        if viewModel.isBudgetExhausted {
            return .disabledBudgetExhausted
        }
        if !viewModel.hasGeneratedOutput {
            return .disabledNoOutput
        }
        if let original = viewModel.originalText,
           viewModel.wordCount(original) < 20 {
            return .disabledTooShort
        }
        if viewModel.originalText == nil {
            return .disabledTooShort
        }
        if !NetworkMonitor.shared.isConnected && !viewModel.hasFixesCacheForCurrent {
            return .disabledOffline
        }
        if viewModel.hasFixesCacheForCurrent {
            if viewModel.fixesCacheForCurrentIsEmpty {
                return .emptyResultCached
            }
            return .cached
        }
        if viewModel.hasAnalysisCache {
            return .enabledTellMeCached
        }
        return .enabledNoCacheNoTellMe
    }
}

// MARK: - State enum

private enum ButtonState {
    case enabledNoCacheNoTellMe        // "Revise" — no ring, will analyse first
    case enabledTellMeCached           // "Revise" — Tell Me cached, no Fixes cache
    case cached                        // "Revise" + indigo ring
    case inFlight                      // disabled, no spinner — grabber pulses
    case disabledRedraftInFlight       // greyed, gated by isLoading
    case disabledBudgetExhausted       // greyed
    case disabledOffline               // greyed
    case disabledTooShort              // greyed
    case disabledNoOutput              // greyed — no Output generated yet
    case emptyResultCached             // "Revise" muted — no revisions found

    var isEnabled: Bool {
        switch self {
        case .enabledNoCacheNoTellMe,
             .enabledTellMeCached,
             .cached,
             .emptyResultCached:
            return true
        case .inFlight,
             .disabledRedraftInFlight,
             .disabledBudgetExhausted,
             .disabledOffline,
             .disabledTooShort,
             .disabledNoOutput:
            return false
        }
    }

    var labelColor: Color {
        switch self {
        case .enabledNoCacheNoTellMe, .enabledTellMeCached, .cached:
            return .dkPrimary
        case .emptyResultCached:
            return .dkTextSecondary
        case .inFlight, .disabledRedraftInFlight, .disabledBudgetExhausted,
             .disabledOffline, .disabledTooShort, .disabledNoOutput:
            return Color(.systemGray2)
        }
    }

    /// Indigo capsule ring drawn only when revisions are cached.
    /// All other states are borderless.
    var ringColor: Color {
        switch self {
        case .cached: return .dkPrimary
        default:      return .clear
        }
    }

    var ringWidth: CGFloat {
        switch self {
        case .cached: return 1.5
        default:      return 0
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .enabledNoCacheNoTellMe:    return "Revise. Will analyse the clause first."
        case .enabledTellMeCached:       return "Revise. Generate revisions from the analysis."
        case .cached:                    return "Revise. Open cached revisions."
        case .inFlight:                  return "Revise. Working in the background."
        case .disabledRedraftInFlight:   return "Revise. Disabled while a redraft is in progress."
        case .disabledBudgetExhausted:   return "Revise. Disabled. Budget exhausted."
        case .disabledOffline:           return "Revise. Disabled. Offline and no cached revisions."
        case .disabledTooShort:          return "Revise. Disabled. Clause too short."
        case .disabledNoOutput:          return "Revise. Disabled. Generate an output first."
        case .emptyResultCached:         return "Revise. No revisions were found for this clause."
        }
    }

    var accessibilityValue: String {
        switch self {
        case .cached: return "Cached"
        default:      return ""
        }
    }
}

// MARK: - Revise Ready Banner

/// Inline banner shown above the bottom input section when Revise results
/// arrive while a text field is focused. Tapping the banner opens the
/// Revise sheet; the X button or a swipe-down dismisses it.
struct FixesReadyBanner: View {

    @ObservedObject var viewModel: DraftingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.dkPrimary)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            Image(systemName: "wand.and.stars")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.dkPrimary)

            Text("Revise \u{2014} ready")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.dkTextPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.dkTextSecondary)

            Button {
                viewModel.dismissFixesReadyBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.dkTextSecondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss banner.")
        }
        .padding(.vertical, 6)
        .padding(.trailing, 4)
        .frame(height: 44)
        .background(Color.dkSurface)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.showFixesReadyBanner = false
            viewModel.showFixesSheet = true
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height > 20 {
                        viewModel.dismissFixesReadyBanner()
                    }
                }
        )
        .transition(reduceMotion
                    ? .opacity
                    : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Revise ready")
        .accessibilityHint("Tap to open the Revise sheet.")
    }
}
