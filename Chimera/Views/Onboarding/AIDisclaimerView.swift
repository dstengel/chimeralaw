// AIDisclaimerView.swift
// Chimera Law
//
// One-time AI disclaimer screen shown after the user has accepted the
// Terms of Use and Privacy Policy on `OnboardingView`, and before the
// main `DraftingView` is reached. Persists acknowledgement in
// UserDefaults under `dk_ai_disclaimer_acknowledged`. Not re-shown.
//
// Visual language matches `WalkthroughView`: centered illustration area
// (here, a large SF symbol in amber), headline, body, and a primary
// action button pinned to the bottom — no page dots, single screen.

import SwiftUI

struct AIDisclaimerView: View {

    /// Called when the user taps the acknowledgement button.
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            VStack(spacing: 32) {

                Spacer()

                // Symbol — sits in the same visual slot as the
                // walkthrough illustrations (frame ~280x260).
                Image(systemName: "exclamationmark.bubble")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.dkWarning)
                    .frame(maxWidth: 160, maxHeight: 160)
                    .accessibilityHidden(true)

                // Text block — same typography as walkthrough pages.
                VStack(spacing: 14) {
                    Text("Inspiration, not advice")
                        .font(.dkHeadline)
                        .foregroundColor(.dkTextPrimary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 10) {
                        Text("Chimera Law is a drafting aid for legal professionals.")
                        Text("It does not provide legal advice.")
                        Text("The AI generates language by predicting likely words. Output may be incomplete, inaccurate, or fabricated.")
                        Text("Review every result before relying on it.")
                    }
                    .font(.dkBody)
                    .foregroundColor(.dkTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, DKLayout.screenPadding)

            // Bottom action — same placement and style as walkthrough.
            VStack(spacing: 20) {
                Button(action: onAcknowledge) {
                    Text("I understand")
                }
                .buttonStyle(DKPrimaryButtonStyle(isEnabled: true))
                .padding(.horizontal, DKLayout.screenPadding)
                .accessibilityHint("Acknowledges the AI disclaimer and continues to the app.")
            }
            .padding(.vertical, 24)
        }
        .background(Color.dkBackground.ignoresSafeArea())
    }
}
