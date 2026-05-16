// FixCardView.swift
// Chimera Law
// Single fix card for the Fixes sheet. Top half: the `finding` (verbatim
// or near-verbatim from the Tell Me analysis, with Markdown bold/italic
// preserved via MarkdownText). Bottom half: the `instruction` (short
// imperative drafting directive that will be sent through Additional
// Instructions on tap).
//
// Tap on the card writes the instruction into the Additional
// Instructions field and fires the existing single-variant rephrase
// path. Already-applied state: 50% opacity card with a small "Already
// applied" caption; still tappable so the user can re-apply.

import SwiftUI

struct FixCardView: View {

    let item: FixItem
    let isApplied: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {

                // Top half — finding
                MarkdownText(item.finding)
                    .padding(DKLayout.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Divider
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 1)

                // Bottom half — instruction
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.dkPrimary)
                        .padding(.top, 1)

                    Text(item.instruction)
                        .font(.dkMono)
                        .foregroundColor(.dkTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(DKLayout.cardPadding)
                .background(Color.dkPrimary.opacity(0.06))

                if isApplied {
                    HStack {
                        Spacer()
                        Text("Already applied")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.dkTextSecondary)
                    }
                    .padding(.horizontal, DKLayout.cardPadding)
                    .padding(.bottom, 8)
                }
            }
            .background(Color.dkSurface)
            .cornerRadius(DKLayout.cardCornerRadius)
            .opacity(isApplied ? 0.5 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Sends this instruction through Additional Instructions.")
    }

    private var accessibilityLabel: String {
        let base = "Revision. \(item.finding). Tap to apply: \(item.instruction)."
        return isApplied ? base + " Already applied." : base
    }
}
