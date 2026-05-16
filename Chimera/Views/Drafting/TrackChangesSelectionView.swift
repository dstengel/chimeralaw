// TrackChangesSelectionView.swift
// Chimera Law
// Selection screen for track changes import: info note, four options,
// loading indicator, and confirm button.

import SwiftUI

struct TrackChangesSelectionView: View {

    @ObservedObject var viewModel: DraftingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: TrackChangesImportOption?
    @State private var showNoMarkupAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DKLayout.sectionSpacing) {

                        // MARK: - Info Note
                        Text("Chimera Law reads track changes based on Microsoft Word conventions (red strikethrough for deletions, coloured underline for insertions). Results may vary with other applications. Please review the imported text carefully.")
                            .font(.dkCaption)
                            .foregroundColor(.dkTextSecondary)
                            .padding(.top, 8)

                        // MARK: - Four Import Options
                        VStack(spacing: 10) {
                            ForEach(TrackChangesImportOption.allCases) { option in
                                optionRow(option)
                            }
                        }

                        // MARK: - Loading / Status
                        statusIndicator
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .padding(.horizontal, DKLayout.screenPadding)
                }

                // MARK: - Confirm Button
                Button {
                    handleConfirm()
                } label: {
                    Text("Import")
                        .font(.dkBody.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: DKLayout.buttonHeight)
                        .background(canConfirm ? Color.dkAccent : Color.dkAccent.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius))
                }
                .disabled(!canConfirm)
                .padding(.horizontal, DKLayout.screenPadding)
                .padding(.bottom, 16)
                .padding(.top, 8)
            }
            .navigationTitle("Import Track Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.cancelTrackChangesImport()
                        dismiss()
                    }
                    .font(.dkBody)
                }
            }
            .onAppear {
                if let image = viewModel.pendingTrackChangeImage {
                    viewModel.analyzeTrackChanges(image: image)
                }
            }
            .alert("No track changes detected",
                   isPresented: $showNoMarkupAlert) {
                Button("Yes") {
                    viewModel.importTrackChanges(option: .acceptAll)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelTrackChangesImport()
                    dismiss()
                }
            } message: {
                Text("No track changes were detected in this screenshot. Import anyway as the Accept-all result (identical to plain text when there are no deletions)?")
            }
        }
    }

    // MARK: - Option Row

    private func optionRow(_ option: TrackChangesImportOption) -> some View {
        let isSelected = selectedOption == option
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedOption = option
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .dkAccent : .dkTextSecondary)
                    .frame(width: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.dkBody)
                        .foregroundColor(.dkTextPrimary)
                    Text(option.description)
                        .font(.dkCaption)
                        .foregroundColor(.dkTextSecondary)
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(isSelected ? Color.dkAccent.opacity(0.08) : Color.dkSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.dkAccent : Color(.systemGray4), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if viewModel.isAnalyzingTrackChanges {
            HStack(spacing: 10) {
                ProgressView()
                TrackChangesLoadingLabel()
            }
        } else if let error = viewModel.trackChangesError {
            VStack(spacing: 10) {
                Text(error)
                    .font(.dkCaption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    if let image = viewModel.pendingTrackChangeImage {
                        viewModel.analyzeTrackChanges(image: image)
                    }
                }
                .font(.dkBody.weight(.medium))
                .foregroundColor(.dkAccent)
            }
        } else if viewModel.trackChangesResult != nil {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Ready")
                    .font(.dkCaption)
                    .foregroundColor(.dkTextSecondary)
            }
        }
    }

    // MARK: - Logic

    private var canConfirm: Bool {
        selectedOption != nil
        && viewModel.trackChangesResult != nil
        && !viewModel.isAnalyzingTrackChanges
    }

    private func handleConfirm() {
        guard let option = selectedOption,
              let result = viewModel.trackChangesResult else { return }

        // If no markup was detected, prompt the user before falling back to Accept-all.
        if !result.markupDetected {
            showNoMarkupAlert = true
            return
        }

        viewModel.importTrackChanges(option: option)
        dismiss()
    }
}

// MARK: - Loading Label (Timed Phases)

/// Cycles through descriptive labels while Claude processes the screenshot.
private struct TrackChangesLoadingLabel: View {

    @State private var phase = 0

    private let labels = [
        "Reading the screenshot...",
        "Identifying changes...",
        "Parsing markup..."
    ]

    var body: some View {
        Text(labels[min(phase, labels.count - 1)])
            .font(.dkCaption)
            .foregroundColor(.dkTextSecondary)
            .onAppear { startTimer() }
    }

    private func startTimer() {
        phase = 0
        Task {
            try? await Task.sleep(for: .seconds(3))
            phase = 1
            try? await Task.sleep(for: .seconds(4))
            phase = 2
        }
    }
}
