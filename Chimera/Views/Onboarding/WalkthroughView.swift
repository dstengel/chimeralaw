// WalkthroughView.swift
// Chimera Law
//
// Five-screen feature walkthrough shown once before onboarding,
// immediately after the splash screen on a first launch.
// Not dismissible — the user must progress through all pages
// before reaching the consent / onboarding screen.
//
// Sequence:
//   1. Negotiate or mark up a clause   (context)
//   2. Add the wording                 (import)
//   3. Analyse it                      (Tell Me)
//   4. Mark it up                      (rephrase + diff)
//   5. Send results                    (export)

import SwiftUI

// MARK: - Walkthrough View

struct WalkthroughView: View {

    /// Called when the user taps "Get Started" on the final page.
    let onComplete: () -> Void

    @State private var currentPage: Int = 0

    private let pages = WalkthroughPage.all

    var body: some View {
        VStack(spacing: 0) {

            // Paged content — swipe or tap Next to advance.
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomBar
        }
        .background(Color.dkBackground.ignoresSafeArea())
    }

    // MARK: - Page view

    private func pageView(_ page: WalkthroughPage) -> some View {
        VStack(spacing: 32) {

            Spacer()

            // Illustration
            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280, maxHeight: 260)
                .accessibilityHidden(true)

            // Text block
            VStack(spacing: 14) {
                Text(page.title)
                    .font(.dkHeadline)
                    .foregroundColor(.dkTextPrimary)
                    .multilineTextAlignment(.center)

                Text(page.body)
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
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 20) {

            // Animated page dots
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage
                              ? Color.dkPrimary
                              : Color.dkPrimary.opacity(0.22))
                        .frame(width: i == currentPage ? 22 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }

            // Primary action button
            Button(action: advance) {
                Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
            }
            .buttonStyle(DKPrimaryButtonStyle(isEnabled: true))
            .padding(.horizontal, DKLayout.screenPadding)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Advance

    private func advance() {
        if currentPage < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
        } else {
            onComplete()
        }
    }
}

// MARK: - Page model

struct WalkthroughPage {
    let imageName: String
    let title: String
    let body: String

    static let all: [WalkthroughPage] = [

        WalkthroughPage(
            imageName: "wt_negotiate",
            title: "Negotiate or mark up a clause",
            body: "When you receive a venture-capital clause that needs review, negotiation, or redlining, Chimera Law gives you the precision tools to do it fast."
        ),

        WalkthroughPage(
            imageName: "wt_add",
            title: "Add the wording",
            body: "Type or paste your clause, or import it from a photo or camera using built-in OCR. AI clean-up removes scan artefacts automatically."
        ),

        WalkthroughPage(
            imageName: "wt_analysis",
            title: "Analyse it",
            body: "Ask Chimera Law to explain the VC clause before you change anything — risks, obligations, and key terms, in plain language."
        ),

        WalkthroughPage(
            imageName: "wt_markitup",
            title: "Mark it up",
            body: "Rephrase at the right deal stage and shift toward founder or investor bias. Review every word-level change and revert anything you disagree with."
        ),

        WalkthroughPage(
            imageName: "wt_sendresults",
            title: "Send the result",
            body: "Export to Word or PDF with a full redline, or copy the result directly. Ready to send to the other side."
        ),
    ]
}
