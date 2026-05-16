// DrawerGrabber.swift
// Chimera Law
// The drawer grabber bar that sits above the bias-selector / Revise-button
// row. Carries two visual signals:
//   - Cache state (colour): grey when no analysis is cached for the
//     current Original; indigo when an analysis is cached.
//   - In-flight state (animation): COLOUR pulse between systemGray4 and
//     dkPrimary on a 1.6 s full cycle (0.8 s per half). Active while
//     EITHER a Tell Me analysis OR a Revise generation is in flight
//     (covers Tell Me pill tap, Revise auto-fire Tell Me phase, and
//     Revise call). Under reduce-motion, replaced by a static dkPrimary
//     fill at full strength so the in-flight semantic is still
//     communicated.
//
// Pulse driver: TimelineView(.animation). The colour is computed each
// frame from a sinusoidal function of the system clock — there is no
// `.repeatForever` animation attached to a CoreAnimation layer, no
// `@State` pulse value to toggle, and no `withAnimation` cancellation
// to coordinate. The moment `viewModel.isAnyTellMeWorkInFlight` flips
// to false, `body` re-renders and the TimelineView is removed from
// the tree, so the redraw loop stops by construction. This replaces
// the prior `withAnimation(...).repeatForever` approach, whose
// cancellation was unreliable on iOS 26 (the layer's repeating
// animation could outlive the SwiftUI state change and continue
// oscillating the fill).
//
// The cache-state binding uses `hasAnalysisForCurrentOriginal` (Original-
// only, style-agnostic) — distinct from `hasAnalysisCache` — so the
// indigo signal survives the SIMPLE-fallback asymmetry where Tell Me is
// generated under .aplus but the user's active style is .plain.

import SwiftUI

struct DrawerGrabber: View {

    @ObservedObject var viewModel: DraftingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tap action — flips the drawer's expanded state.
    var onTap: () -> Void

    /// Drag-end action with the vertical translation in points. The
    /// caller decides what threshold to apply.
    var onDrag: (CGFloat) -> Void

    var body: some View {
        bar
            .frame(maxWidth: .infinity) // center horizontally
            .contentShape(Rectangle().inset(by: -10)) // larger tap target
            .onTapGesture { onTap() }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        onDrag(value.translation.height)
                    }
            )
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Bar body

    /// The rendered bar. Branches on whether to drive the pulse from a
    /// TimelineView or to render a static idle colour. When
    /// `isAnyTellMeWorkInFlight` flips to false, the TimelineView is
    /// removed from the view tree on the next render — no residual
    /// animation can survive that transition because the animation
    /// state lives only inside the timeline closure.
    @ViewBuilder
    private var bar: some View {
        if viewModel.isAnyTellMeWorkInFlight && !reduceMotion {
            TimelineView(.animation) { context in
                shape(filledWith: pulseColor(at: context.date))
            }
        } else {
            shape(filledWith: idleColor)
        }
    }

    private func shape(filledWith color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(color)
            .frame(width: 36, height: 5)
    }

    // MARK: - Colour

    /// Colour to render when not driving the timeline-based pulse.
    /// Three branches:
    ///   - In flight + reduce-motion → static dkPrimary at full
    ///     strength. Preserves the in-flight semantic for users who
    ///     have animations disabled.
    ///   - Idle + cached analysis for the current Original → dkPrimary.
    ///   - Idle + no cached analysis → systemGray4.
    private var idleColor: Color {
        if viewModel.isAnyTellMeWorkInFlight && reduceMotion {
            return Color.dkPrimary
        }
        return viewModel.hasAnalysisForCurrentOriginal
            ? Color.dkPrimary
            : Color(.systemGray4)
    }

    /// Date-driven colour interpolation between systemGray4 and
    /// dkPrimary. Period 1.6 s (0.8 s per half). Easing curve is
    /// `(1 - cos(2π · phase)) / 2`, which gives a smooth sinusoidal
    /// pulse with zero-derivative endpoints (no visible step at the
    /// peaks of grey or indigo). The phase resets every 1.6 s; using
    /// `truncatingRemainder` against a long-running clock keeps the
    /// argument to `cos` bounded and numerically well-behaved.
    private func pulseColor(at date: Date) -> Color {
        let cyclePeriod: TimeInterval = 1.6
        let phase = date
            .timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cyclePeriod) / cyclePeriod
        let eased = (1 - cos(.pi * 2 * phase)) / 2
        return Color(.systemGray4).mix(with: Color.dkPrimary, by: eased)
    }

    // MARK: - Accessibility

    private var accessibilityLabelText: String {
        if viewModel.isAnyTellMeWorkInFlight {
            return "Drawer handle. Background work in progress."
        }
        if viewModel.hasAnalysisForCurrentOriginal {
            return "Drawer handle. Analysis cached."
        }
        return "Drawer handle. No analysis cached."
    }
}
