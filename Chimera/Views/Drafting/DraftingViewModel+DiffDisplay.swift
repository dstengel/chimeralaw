// DraftingViewModel+DiffDisplay.swift
// Chimera Law
// Simple two-way diff computation for exports and the default Simple view.
// The ViewModel extension contains only recomputeExportTokens().
// displayTokens selection (simple vs complex) lives in DiffView using @AppStorage.

import Foundation

extension DraftingViewModel {

    /// Recomputes `exportTokens` from a plain two-way diff of the original vs current text.
    /// Guards on cache equality — skips recomputation when source texts are unchanged.
    /// Called at every site where `recomputeDiffTokens()` is called, and directly from ExportService.
    func recomputeExportTokens() {
        guard let original = originalText else {
            exportTokens = []
            lastExportOriginal = ""
            lastExportCurrent = ""
            return
        }

        let current = currentText

        // Cache guard: skip when nothing has changed.
        if original == lastExportOriginal,
           current == lastExportCurrent,
           !exportTokens.isEmpty {
            return
        }

        lastExportOriginal = original
        lastExportCurrent = current
        exportTokens = WordDiff.simpleDiff(original: original, current: current)
        objectWillChange.send()
    }
}
