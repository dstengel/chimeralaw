// FixesSheetView.swift
// Chimera Law
// Container for the Revise sheet. Renders up to three labelled groups of
// revision cards: Risk Flags, Absent Components, Typical Deviations. Empty
// state delegated to FixesEmptyView; single revision card delegated to
// FixCardView.
//
// Detents: .large default, .medium also enabled (drag-down to half-
// height view). Reduce-transparency fallback: opaque dkSurface in place
// of any Liquid Glass / .thinMaterial background.

import SwiftUI

struct FixesSheetView: View {

    @ObservedObject var viewModel: DraftingViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            Group {
                if let groups = currentGroups, !groups.isEmpty {
                    resultsView(groups)
                } else {
                    FixesEmptyView { dismiss() }
                }
            }
            .background(sheetBackground)
            .navigationTitle("Revise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dkBody)
                        .accessibilityLabel("Done. Close Revise sheet.")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sheet contents

    private func resultsView(_ groups: FixesGroups) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DKLayout.sectionSpacing) {

                // Group: Risk Flags
                if !groups.riskFlags.isEmpty {
                    groupSection(title: "Risk Flags", items: groups.riskFlags)
                }

                // Group: Absent Components
                if !groups.absentComponents.isEmpty {
                    groupSection(title: "Absent Components", items: groups.absentComponents)
                }

                // Group: Typical Deviations
                if !groups.typicalDeviations.isEmpty {
                    groupSection(title: "Typical Deviations", items: groups.typicalDeviations)
                }

                // Footer disclaimer.
                footerDisclaimer
                    .padding(.top, 8)
            }
            .padding(.horizontal, DKLayout.cardPadding)
            .padding(.vertical, DKLayout.cardPadding)
        }
    }

    private func groupSection(title: String, items: [FixItem]) -> some View {
        VStack(alignment: .leading, spacing: DKLayout.itemSpacing) {
            Text(title)
                .font(.dkSubheadline)
                .foregroundColor(.dkTextPrimary)
                .padding(.bottom, 2)

            ForEach(items, id: \.instructionHash) { item in
                FixCardView(
                    item: item,
                    isApplied: viewModel.isFixApplied(item)
                ) {
                    viewModel.applyFix(item)
                }
            }
        }
    }

    private var footerDisclaimer: some View {
        Text("Tapping a revision sends it through Additional Instructions. Anything you have typed in that field will be replaced. The bias selection will reset and the redraft will chain from the current Output.")
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(.dkTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var currentGroups: FixesGroups? {
        guard let key = viewModel.currentFixesCacheKey else { return nil }
        return viewModel.fixesCache[key]
    }

    private var sheetBackground: Color {
        // Cards already use opaque dkSurface; the sheet container uses
        // dkBackground. Under reduce-transparency, fall back to dkSurface
        // (slightly off-white / off-black) to drop any system material.
        reduceTransparency ? Color.dkSurface : Color.dkBackground
    }
}
