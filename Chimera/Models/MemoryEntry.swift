// MemoryEntry.swift
// Chimera Law
// SwiftData model for the on-device Memory feature
// (3 manual slots + 1 auto slot). Plus the MemorySnapshot
// data carrier that mediates between the view-model and the entry.
//
// Privacy posture: this file declares the persistent shape only.
// All data is held in a device-protected store (file protection
// class .completeUntilFirstUserAuthentication, no CloudKit). The
// store is owned by `MemoryStore`. See `Services/MemoryStore.swift`.

import Foundation
import SwiftData

// MARK: - Slot identity

/// Stable string keys used to address the four memory slots. Kept as
/// String constants (not an enum) so the @Attribute(.unique) constraint
/// on `MemoryEntry.slotKey` indexes a primitive type. The plus-sheet
/// load row and the Save sheet both reference these constants by name.
enum MemorySlot {
    static let slot1 = "slot1"
    static let slot2 = "slot2"
    static let slot3 = "slot3"
    static let auto  = "auto"

    /// The three manual slots, in display order.
    static let manualSlots: [String] = [slot1, slot2, slot3]

    /// All four slot keys, manual first then auto.
    static let allSlots: [String] = manualSlots + [auto]

    /// Human-facing label for a slot key. Falls back to the raw key
    /// if a future caller passes an unknown value.
    static func displayName(for slotKey: String) -> String {
        switch slotKey {
        case slot1: return "Memory 1"
        case slot2: return "Memory 2"
        case slot3: return "Memory 3"
        case auto:  return "Auto"
        default:    return slotKey
        }
    }

    /// Position 1/2/3 used in the "Saved to Memory N" toast.
    /// Returns nil for the Auto slot.
    static func manualIndex(for slotKey: String) -> Int? {
        switch slotKey {
        case slot1: return 1
        case slot2: return 2
        case slot3: return 3
        default:    return nil
        }
    }
}

// MARK: - SwiftData model

@Model
final class MemoryEntry {
    /// Stable slot identity. Unique per entry — at most one row per slot.
    @Attribute(.unique) var slotKey: String

    /// Wall-clock save time. Drives the "Saved 2 hours ago" subtitle.
    var savedAt: Date

    /// First ~40 chars of `originalText` (or `clauseText` if pre-lock).
    /// Shown in the Save sheet rows.
    var titlePreview: String

    // Working text
    var originalText: String?
    var aiOutputText: String?
    var currentText: String
    var clauseText: String
    var additionalInstruction: String

    // Mode flags
    var hasGeneratedOutput: Bool
    var hasManualEdits: Bool
    var isEditOnTheGo: Bool
    var isTrackChangesRedlineMode: Bool
    var activeTabRaw: String

    // Style / heat
    var activeStyleRaw: String?
    var selectedHeatRaw: Int?
    var selectedLanguage: String

    // Tell Me cache
    var analysisResult: String?
    var analysisStyleKey: String?
    var analysisOriginalText: String?

    // Bias / Revise caches as JSON blobs
    var rephraseCacheJSON: Data?
    var fixesCacheJSON: Data?
    var fixesAppliedFlagsJSON: Data?

    init(
        slotKey: String,
        savedAt: Date,
        titlePreview: String,
        originalText: String?,
        aiOutputText: String?,
        currentText: String,
        clauseText: String,
        additionalInstruction: String,
        hasGeneratedOutput: Bool,
        hasManualEdits: Bool,
        isEditOnTheGo: Bool,
        isTrackChangesRedlineMode: Bool,
        activeTabRaw: String,
        activeStyleRaw: String?,
        selectedHeatRaw: Int?,
        selectedLanguage: String,
        analysisResult: String?,
        analysisStyleKey: String?,
        analysisOriginalText: String?,
        rephraseCacheJSON: Data?,
        fixesCacheJSON: Data?,
        fixesAppliedFlagsJSON: Data?
    ) {
        self.slotKey = slotKey
        self.savedAt = savedAt
        self.titlePreview = titlePreview
        self.originalText = originalText
        self.aiOutputText = aiOutputText
        self.currentText = currentText
        self.clauseText = clauseText
        self.additionalInstruction = additionalInstruction
        self.hasGeneratedOutput = hasGeneratedOutput
        self.hasManualEdits = hasManualEdits
        self.isEditOnTheGo = isEditOnTheGo
        self.isTrackChangesRedlineMode = isTrackChangesRedlineMode
        self.activeTabRaw = activeTabRaw
        self.activeStyleRaw = activeStyleRaw
        self.selectedHeatRaw = selectedHeatRaw
        self.selectedLanguage = selectedLanguage
        self.analysisResult = analysisResult
        self.analysisStyleKey = analysisStyleKey
        self.analysisOriginalText = analysisOriginalText
        self.rephraseCacheJSON = rephraseCacheJSON
        self.fixesCacheJSON = fixesCacheJSON
        self.fixesAppliedFlagsJSON = fixesAppliedFlagsJSON
    }
}

// MARK: - Snapshot (data carrier)

/// Plain value type that travels between the view-model and the
/// SwiftData store. Holds exactly the fields persisted by §1.1 of
/// the Local Persistence Plan.
///
/// Construction: the view-model has a `func memorySnapshot()` that
/// builds this; restore reads the values back into the view-model
/// via `restore(from:)`. Keeping the cross-cutting data on this
/// struct (and not on `MemoryEntry`) makes the persisted-shape vs
/// in-memory-shape boundary explicit.
struct MemorySnapshot {
    let originalText: String?
    let aiOutputText: String?
    let currentText: String
    let clauseText: String
    let additionalInstruction: String

    let hasGeneratedOutput: Bool
    let hasManualEdits: Bool
    let isEditOnTheGo: Bool
    let isTrackChangesRedlineMode: Bool
    let activeTabRaw: String

    let activeStyleRaw: String?
    let selectedHeatRaw: Int?
    let selectedLanguage: String

    let analysisResult: String?
    let analysisStyleKey: String?
    let analysisOriginalText: String?

    let rephraseCacheJSON: Data?
    let fixesCacheJSON: Data?
    let fixesAppliedFlagsJSON: Data?

    /// Title preview = first 40 chars of `originalText` (or `clauseText`
    /// if pre-lock), trimmed to a single line.
    var titlePreview: String {
        let source = (originalText?.isEmpty == false ? originalText : clauseText) ?? ""
        let trimmed = source
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 40 { return trimmed }
        return String(trimmed.prefix(40)) + "…"
    }

    /// Apply the snapshot to a fresh `MemoryEntry` (used by the upsert
    /// path in `MemoryStore.save(_:to:)`).
    func writeFields(into entry: MemoryEntry, savedAt: Date) {
        entry.savedAt = savedAt
        entry.titlePreview = titlePreview
        entry.originalText = originalText
        entry.aiOutputText = aiOutputText
        entry.currentText = currentText
        entry.clauseText = clauseText
        entry.additionalInstruction = additionalInstruction
        entry.hasGeneratedOutput = hasGeneratedOutput
        entry.hasManualEdits = hasManualEdits
        entry.isEditOnTheGo = isEditOnTheGo
        entry.isTrackChangesRedlineMode = isTrackChangesRedlineMode
        entry.activeTabRaw = activeTabRaw
        entry.activeStyleRaw = activeStyleRaw
        entry.selectedHeatRaw = selectedHeatRaw
        entry.selectedLanguage = selectedLanguage
        entry.analysisResult = analysisResult
        entry.analysisStyleKey = analysisStyleKey
        entry.analysisOriginalText = analysisOriginalText
        entry.rephraseCacheJSON = rephraseCacheJSON
        entry.fixesCacheJSON = fixesCacheJSON
        entry.fixesAppliedFlagsJSON = fixesAppliedFlagsJSON
    }

    /// Build a brand-new `MemoryEntry` from this snapshot. Used when
    /// upserting into a slot that does not yet exist.
    func makeEntry(slotKey: String, savedAt: Date) -> MemoryEntry {
        MemoryEntry(
            slotKey: slotKey,
            savedAt: savedAt,
            titlePreview: titlePreview,
            originalText: originalText,
            aiOutputText: aiOutputText,
            currentText: currentText,
            clauseText: clauseText,
            additionalInstruction: additionalInstruction,
            hasGeneratedOutput: hasGeneratedOutput,
            hasManualEdits: hasManualEdits,
            isEditOnTheGo: isEditOnTheGo,
            isTrackChangesRedlineMode: isTrackChangesRedlineMode,
            activeTabRaw: activeTabRaw,
            activeStyleRaw: activeStyleRaw,
            selectedHeatRaw: selectedHeatRaw,
            selectedLanguage: selectedLanguage,
            analysisResult: analysisResult,
            analysisStyleKey: analysisStyleKey,
            analysisOriginalText: analysisOriginalText,
            rephraseCacheJSON: rephraseCacheJSON,
            fixesCacheJSON: fixesCacheJSON,
            fixesAppliedFlagsJSON: fixesAppliedFlagsJSON
        )
    }
}
