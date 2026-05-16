// DraftingViewModel+TrackChanges.swift
// Chimera Law
// Track Changes Import: vision analysis, import options, cancellation.

import UIKit
import os

// MARK: - Track Changes Import Option

enum TrackChangesImportOption: String, CaseIterable, Identifiable {
    case acceptAll      = "accept_all"
    case rejectAll      = "reject_all"
    case showAsRedline  = "show_as_redline"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .acceptAll:     return "Accept all changes"
        case .rejectAll:     return "Reject all changes"
        case .showAsRedline: return "Show as redline"
        }
    }

    var description: String {
        switch self {
        case .acceptAll:     return "Imports the text with all proposed changes applied"
        case .rejectAll:     return "Imports the text with all proposed changes undone"
        case .showAsRedline: return "Sets the original and changed text so you can review them in the Changes tab"
        }
    }
}

// MARK: - ViewModel Extension

extension DraftingViewModel {

    // MARK: - Analyze

    /// Sends the screenshot to Claude vision for track changes analysis.
    /// Called when the selection screen appears.
    func analyzeTrackChanges(image: UIImage) {
        guard NetworkMonitor.shared.isConnected else {
            trackChangesError = DraftingError.offline.errorDescription
            return
        }
        if isBudgetExhausted {
            trackChangesError = DraftingError.budgetExhausted.errorDescription
            return
        }

        isAnalyzingTrackChanges = true
        trackChangesError = nil
        trackChangesResult = nil

        trackChangesTask = Task {
            do {
                let result = try await DraftingService.shared.analyzeTrackChanges(image: image)
                guard !Task.isCancelled else { return }
                trackChangesResult = result
                isAnalyzingTrackChanges = false

                // Record usage using the existing pattern
                await recordUsage(DraftingService.RephraseResult(
                    text: "",
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens
                ))
            } catch {
                guard !Task.isCancelled else { return }
                trackChangesError = error.localizedDescription
                isAnalyzingTrackChanges = false
            }
        }
    }

    // MARK: - Import

    /// Applies the parsed track changes result using the selected option.
    /// For Accept-all and Reject-all: sets `clauseText` and enters normal import flow.
    /// For Show-as-redline: sets original + output and switches to the Changes tab.
    func importTrackChanges(option: TrackChangesImportOption) {
        guard let result = trackChangesResult else { return }

        let maxLen = 5000

        switch option {
        case .acceptAll:
            let text = joinSpans(result.spans.filter { $0.status != .deleted })
            let truncated = truncateIfNeeded(text, limit: maxLen)

            isSuppressingSnapshot = true
            setAiOutputText(nil)
            setCurrentText(truncated)
            clauseText = truncated
            preEditClauseText = truncated
            lastSnapshotWordCount = wordCount(truncated)
            hasGeneratedOutput = true
            hasManualEdits = false
            isTrackChangesRedlineMode = false
            activeTab = .current
            isSuppressingSnapshot = false

            // Single chokepoint owns originalText assignment, cache wipes,
            // undo-stack hygiene, and the auto-Tell-Me hook. Track Changes
            // imports previously skipped Tell Me / Fixes cache invalidation —
            // the helper now inherits that hygiene automatically.
            rebaselineOriginal(to: truncated)
            recomputeDiffTokens()
            recomputeExportTokens()

        case .rejectAll:
            let text = joinSpans(result.spans.filter { $0.status != .inserted })
            let truncated = truncateIfNeeded(text, limit: maxLen)

            isSuppressingSnapshot = true
            setAiOutputText(nil)
            setCurrentText(truncated)
            clauseText = truncated
            preEditClauseText = truncated
            lastSnapshotWordCount = wordCount(truncated)
            hasGeneratedOutput = true
            hasManualEdits = false
            isTrackChangesRedlineMode = false
            activeTab = .current
            isSuppressingSnapshot = false

            // Single chokepoint owns originalText assignment, cache wipes,
            // undo-stack hygiene, and the auto-Tell-Me hook.
            rebaselineOriginal(to: truncated)
            recomputeDiffTokens()
            recomputeExportTokens()

        case .showAsRedline:
            let original = joinSpans(result.spans.filter { $0.status != .inserted })
            let output = joinSpans(result.spans.filter { $0.status != .deleted })
            let truncOriginal = truncateIfNeeded(original, limit: maxLen)
            let truncOutput = truncateIfNeeded(output, limit: maxLen)

            setAiOutputText(truncOutput)
            setCurrentText(truncOutput)
            clauseText = truncOutput
            hasGeneratedOutput = true
            hasManualEdits = false
            isTrackChangesRedlineMode = true
            activeTab = .showChanges

            // Single chokepoint owns originalText assignment, cache wipes,
            // undo-stack hygiene, and the auto-Tell-Me hook.
            rebaselineOriginal(to: truncOriginal)
            recomputeDiffTokens()
            recomputeExportTokens()
        }

        clearTrackChangesState()
    }

    // MARK: - Cancel

    /// Cancels any in-flight API task and clears all track changes state.
    func cancelTrackChangesImport() {
        trackChangesTask?.cancel()
        trackChangesTask = nil
        clearTrackChangesState()
    }

    // MARK: - Private Helpers

    private func clearTrackChangesState() {
        pendingTrackChangeImage = nil
        trackChangesResult = nil
        trackChangesError = nil
        showTrackChangesSheet = false
        isAnalyzingTrackChanges = false
        trackChangesTask = nil
    }

    /// Joins an array of spans into a single string.
    /// Break spans ("\n") produce newlines. Content spans are joined with spaces.
    private func joinSpans(_ spans: [DraftingService.TrackChangesSpan]) -> String {
        var parts: [String] = []
        for span in spans {
            let trimmed = span.text.trimmingCharacters(in: .whitespaces)
            if trimmed == "\n" {
                if let last = parts.last, !last.hasSuffix("\n") {
                    parts.append("\n")
                } else if parts.isEmpty {
                    continue
                }
            } else if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }
        var result = ""
        for (i, part) in parts.enumerated() {
            if part == "\n" {
                result += "\n"
            } else {
                if i > 0 && parts[i - 1] != "\n" {
                    result += " "
                }
                result += part
            }
        }
        return result
    }

    /// Truncates text to the character limit, posting a warning if needed.
    private func truncateIfNeeded(_ text: String, limit: Int) -> String {
        if text.count > limit {
            errorMessage = "Text truncated to \(limit) characters."
            return String(text.prefix(limit))
        }
        return text
    }
}
