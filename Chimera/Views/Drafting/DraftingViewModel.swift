// DraftingViewModel.swift
// Chimera Law
// View model for the main drafting screen

import SwiftUI
import Combine
@preconcurrency import Vision
import os

@MainActor
final class DraftingViewModel: ObservableObject {

    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: - Published Properties

    var clauseText: String = "" {
        willSet { objectWillChange.send() }
        didSet {
            // Auto-save coalescing tick. The MemoryStore debounces by 2s,
            // so a keystroke does not write immediately; only the last
            // edit in a 2s window triggers a disk write. No-op when the
            // dk_autoSaveMemory toggle is off.
            scheduleMemoryAutoSaveIfPossible()
        }
    }

    var additionalInstruction: String = "" {
        willSet { objectWillChange.send() }
    }

    var selectedLanguage: String = "en" {
        willSet { objectWillChange.send() }
    }

    /// The active drafting style. Initialised from the persisted setting
    /// (defaults to LDN). Updated when the user changes the setting.
    var activeStyle: DraftingStyle? = {
        let raw = UserDefaults.standard.string(forKey: "dk_draftingStyle") ?? DraftingStyle.aplus.rawValue
        return DraftingStyle(rawValue: raw) ?? .aplus
    }() {
        willSet { objectWillChange.send() }
    }

    var selectedHeat: HeatLevel? = nil {
        willSet { objectWillChange.send() }
    }

    var isLoading: Bool = false {
        willSet { objectWillChange.send() }
    }

    var rephraseJustCompleted: Bool = false {
        willSet { objectWillChange.send() }
    }

    var errorMessage: String? {
        willSet { objectWillChange.send() }
    }

    /// The structured error that produced `errorMessage`, when available.
    /// Used by the view to decide whether to surface a "Try again" button.
    /// Non-`DraftingError` failures (generic `localizedDescription`) leave
    /// this nil so the banner falls back to a plain, non-retryable message.
    var errorKind: DraftingError? {
        willSet { objectWillChange.send() }
    }

    /// The action to invoke when the user taps "Try again" on the error
    /// banner. Captured by `setError(_:retry:)` at each failure site so the
    /// banner can restart the appropriate in-flight path (rephrase,
    /// instruction rephrase, photo clean-up, …). Cleared whenever an error
    /// is dismissed or a new one is set without a retry.
    private var lastRetryAction: (() -> Void)?

    /// True when the last error is retryable AND a retry closure was
    /// captured for it. Drives the visibility of the "Try again" button.
    var canRetryLastAction: Bool {
        (errorKind?.isRetryable ?? false) && lastRetryAction != nil
    }

    /// Set a structured error plus (optionally) a closure to retry the
    /// path that produced it. All error-handling sites should prefer this
    /// over assigning `errorMessage` directly so that retry affordances
    /// work consistently across paths.
    func setError(_ error: DraftingError, retry: (() -> Void)? = nil) {
        errorKind = error
        errorMessage = error.errorDescription
        lastRetryAction = (retry != nil && error.isRetryable) ? retry : nil
    }

    /// Clear any visible error and discard the captured retry closure.
    func clearError() {
        errorKind = nil
        errorMessage = nil
        lastRetryAction = nil
    }

    /// Invoked by the error banner's "Try again" button.
    func retryLastRephrase() {
        guard let retry = lastRetryAction else { return }
        clearError()
        retry()
    }

    // MARK: - Additional-Instruction Rejection (out-of-scope alert)

    /// Payload for the out-of-scope alert surfaced when the AI flow
    /// returns a `rejected` envelope. Identifiable so the alert modifier
    /// can use `presenting:` to re-render when a new rejection lands.
    struct InstructionRejection: Identifiable, Equatable {
        let id = UUID()
        let category: AdditionalInstructionRejectionCategory
        let reason: String
    }

    /// Set when an AI-flow call lands a `rejected` outcome. Drives the
    /// `Additional instructions are out of scope.` alert in `DraftingView`.
    /// `nil` when no rejection is being shown.
    var instructionRejection: InstructionRejection? {
        willSet { objectWillChange.send() }
    }

    /// Sanitises the model's `reason` (length cap, fallback for empty) and
    /// publishes a new rejection. Called from the `.rejected` branch of
    /// `executeInstructionRephrase` and the AI-instruction branch of
    /// `retryWithSystemKey`.
    func presentInstructionRejection(
        category: AdditionalInstructionRejectionCategory,
        reason: String
    ) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeReason: String
        if trimmed.isEmpty {
            safeReason = category.fallbackCopy
        } else if trimmed.count > 280 {
            safeReason = String(trimmed.prefix(280)) + "…"
        } else {
            safeReason = trimmed
        }
        instructionRejection = InstructionRejection(
            category: category,
            reason: safeReason
        )
    }

    /// Dismiss handler for the out-of-scope alert.
    func dismissInstructionRejection() {
        instructionRejection = nil
    }

    /// Which clause tab is currently displayed.
    enum ClauseTab { case current, showChanges, original }

    var activeTab: ClauseTab = .current {
        willSet { objectWillChange.send() }
    }

    /// True once the user has manually reverted a change via the diff view.
    /// Causes the style/heat selectors to appear visually deselected.
    var hasManualEdits: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Identifies which Memory slot the live state was last loaded from
    /// (one of `MemorySlot.slot1` / `slot2` / `slot3` / `auto`), or nil
    /// if the live state did not come from a slot. Drives the unsaved-
    /// changes confirmation alert in the plus-sheet load row: tapping
    /// the slot whose key matches `loadedFromSlotKey` is a no-op rather
    /// than a destructive overwrite. Cleared on `resetAll()` and on
    /// `confirmImportReplaceOriginal()`.
    var loadedFromSlotKey: String? {
        willSet { objectWillChange.send() }
    }

    /// Backwards-compat shim used by background colour logic etc.
    var showingOriginal: Bool { activeTab == .original }

    // MARK: - Budget

    var monthlyUsage: MonthlyUsage? {
        willSet { objectWillChange.send() }
    }

    // MARK: - Camera Capture

    var showCameraPicker: Bool = false {
        willSet { objectWillChange.send() }
    }

    var isTrimming: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Tracks whether the "+" (attachment) button has been "used" — i.e.,
    /// one of the four options in the attachment sheet has been tapped.
    /// Drives the +-button tint: false → .dkPrimary (call-to-action),
    /// true → .dkTextSecondary (dimmed). Reset to false by `resetAll()`.
    /// In-memory only; resets on fresh app launch.
    var plusUsed: Bool = false {
        willSet { objectWillChange.send() }
    }

    // MARK: - Edit On the Go

    /// True when any text was added via the photo/camera function.
    /// Controls whether the clean-up prompt appears when activating Edit On the Go.
    var textAddedViaPhoto: Bool = false

    /// True when the camera text was too fragmentary and had to be
    /// reconstructed by AI. Shows a warning banner to the user.
    var textWasReconstructed: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Controls the "Clean up via AI?" prompt shown immediately after photo/camera import.
    var showPhotoCleanUpPrompt: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Controls the secondary prompt asking whether the user wants to review the
    /// AI clean-up result (raw OCR vs cleaned text) in the redline engine.
    /// Presented in parallel with the background clean-up API call.
    var showReviewPrompt: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Controls the OCR cleanup review sheet. Set by acceptReview() when the
    /// user taps "Yes" on the review prompt. The sheet shows inline diff chips
    /// and handles commit/discard itself via commitOCRCleanupFromSheet / discardOCRCleanupFromSheet.
    var showOCRCleanupReviewSheet: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// User's choice on the review prompt. Nil while the prompt is still open.
    private var pendingReviewChoice: ReviewChoice? = nil

    /// Cleanup entry point that is currently in flight. Determines commit behaviour
    /// (in-place replacement vs. Edit On the Go activation).
    private var pendingCleanUpMode: CleanUpMode? = nil

    /// API result captured while the user was still answering the review prompt.
    /// Stored until both inputs are available, then committed via commitCleanUpIfReady().
    /// Property observer fires objectWillChange so OCRCleanupReviewSheet reacts
    /// when the API result arrives while the sheet is already open.
    private var pendingCleanUp: PendingCleanUp? = nil {
        willSet { objectWillChange.send() }
    }

    /// Raw OCR text captured before the clean-up API call, preserved so the redline
    /// engine can show a raw-vs-cleaned diff when the user opts into review.
    private var rawOCRText: String = ""

    // MARK: Accessors for OCRCleanupReviewSheet

    /// Raw OCR text exposed for OCRCleanupReviewSheet (read-only).
    var ocrReviewRawText: String { rawOCRText }

    /// Cleaned text exposed for OCRCleanupReviewSheet; nil while the API is still in flight.
    var ocrReviewCleanedText: String? { pendingCleanUp?.cleaned }

    enum ReviewChoice { case review, skip }
    enum CleanUpMode { case inPlace }

    struct PendingCleanUp {
        let apiResult: DraftingService.RephraseResult
        let cleaned: String
        let rawText: String
        let generation: Int
    }

    /// True while the user is locked-in and has access to the three tabs
    /// (tabs are visible, but no style/heat rephrase has yet been triggered).
    private(set) var isEditOnTheGo: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// True while the user is editing the locked Original (post-lock
    /// re-edit, reached via the long-press → "Edit Original…" path on
    /// the Original tab). Mutually exclusive with `isEditOnTheGo`.
    /// Drives:
    /// - the editor's read-only state on the Original tab,
    /// - suppression of the locked-state indigo wash (the card returns
    ///   to its pre-lock `dkSurface` appearance during edit),
    /// - the `LockPill`'s visibility,
    /// - the disabled state on the Changes / Output segments and the
    ///   horizontal swipe-to-tab gesture,
    /// - hiding of the `AnalysePill`,
    /// - disabling of all rephrase entry points via the
    ///   `canTriggerRephrase` gate.
    private(set) var isEditingOriginal: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Controls whether the bias selector drawer is expanded.
    var isDrawerExpanded: Bool = false {
        willSet { objectWillChange.send() }
    }

    // MARK: - Fallback

    var showFallbackAlert: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Shown when the user tries to import new text while Original exists.
    var showImportOverwriteWarning: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Stores the pending import action (photo/camera/paste) to execute
    /// after the user confirms the import-overwrite warning.
    var pendingImportAction: (() -> Void)?

    /// Shown when the user changes style/heat while having unsaved manual edits.
    var showOverwriteConfirmation: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Stores the pending rephrase action to execute after user confirms overwrite.
    private var pendingRephraseAction: (() -> Void)?
    /// Saved state to restore on cancel.
    private var savedStyle: DraftingStyle?
    private var savedHeat: HeatLevel?
    /// Guard to prevent onChange re-triggering during cancel restore.
    private(set) var isRestoringSelection = false

    /// Identifies which flow stashed the pending request so that
    /// `retryWithSystemKey` can route the BYOK retry through the right
    /// post-processing path. Replaces the legacy `pendingIsMultiVariant`
    /// boolean which collapsed three distinct flows into two cases.
    enum PendingFlowKind {
        case multiVariant
        case aiInstruction
        case analysis
    }

    /// Snapshot of the AI-flow inputs needed to re-run the call against the
    /// system key. Carried through `retryWithSystemKey` so the BYOK retry
    /// uses the same prompt/source/style/language/EditOnTheGo state.
    struct PendingAdditionalInstructionContext {
        let style: DraftingStyle
        let language: String
        let sourceText: String
        let instruction: String
        let wasEditOnTheGo: Bool
    }

    /// Stores the last request context so we can retry with system key.
    /// `pendingFlowKind` discriminates the three flows (multi-variant,
    /// AI-instruction, Tell Me analysis); `pendingMaxTokens` is preserved
    /// because the analysis flow uses 4000 tokens vs. the 1500 default.
    private var pendingSystemPrompt: String?
    private var pendingUserMessage: String?
    private var pendingFlowKind: PendingFlowKind = .multiVariant
    private var pendingMaxTokens: Int = 1500
    private var pendingAdditionalInstructionContext: PendingAdditionalInstructionContext?

    // MARK: - Analysis

    /// Cached raw analysis response.
    var analysisResult: String? {
        willSet { objectWillChange.send() }
    }

    /// The style that produced the cached analysis (for invalidation).
    var analysisStyleKey: String?

    /// The exact `originalText` that produced the cached analysis. Used to
    /// invalidate the cache when the user edits the Original (revert a
    /// token, adjust text, etc.) without going through the explicit
    /// "Use as new original" flow.
    var analysisOriginalText: String?

    /// True while the analysis API call is in flight.
    var isAnalysing: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Controls presentation of the analysis sheet.
    var showAnalysisSheet: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Error message displayed inside the analysis sheet.
    var analysisError: String? {
        willSet { objectWillChange.send() }
    }

    /// Controls the SIMPLE style fallback alert.
    var showSimpleFallbackAlert: Bool = false {
        willSet { objectWillChange.send() }
    }

    // MARK: - Scroll-to-change (undo/redo)

    /// The token id to scroll into view after an undo or redo.
    /// DiffView observes this and calls ScrollViewReader.scrollTo.
    var scrollTargetTokenId: UUID? {
        willSet { objectWillChange.send() }
    }

    /// Counter bumped every time scrollTargetTokenId is set, so the view
    /// re-triggers the scroll even if the same token id is chosen twice
    /// in a row.
    var scrollTargetBump: Int = 0 {
        willSet { objectWillChange.send() }
    }

    // MARK: - Track Changes Import

    /// The image selected for track changes analysis.
    var pendingTrackChangeImage: UIImage? {
        willSet { objectWillChange.send() }
    }

    /// Controls presentation of the track changes selection screen.
    var showTrackChangesSheet: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// True while Claude is analysing the screenshot.
    var isAnalyzingTrackChanges: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// The parsed result from Claude, available once analysis completes.
    var trackChangesResult: DraftingService.TrackChangesResult? {
        willSet { objectWillChange.send() }
    }

    /// Error from the track changes analysis, if any.
    var trackChangesError: String? {
        willSet { objectWillChange.send() }
    }

    /// In-flight task for the track changes API call (for cancellation).
    var trackChangesTask: Task<Void, Never>?

    /// In-flight task for the Tell Me analysis API call. Serves as the
    /// in-flight dedup flag: while non-nil, `analyseOriginal()` returns
    /// early and does not fire a second request. Cleared at the end of
    /// each terminal branch inside the Task body, and cancelled +
    /// cleared by `clearAnalysisCache()`.
    private var analysisTask: Task<Void, Never>?

    /// True while the current session was imported via Track Changes → Show as Redline.
    /// Cleared when the user confirms a rephrase, makes edits, performs a new import, or resets.
    var isTrackChangesRedlineMode: Bool = false {
        willSet { objectWillChange.send() }
    }

    var canAnalyse: Bool {
        hasGeneratedOutput
        && originalText != nil
        && !isLoading
        && !isAnalysing
        && !isBudgetExhausted
        && wordCount(originalText ?? "") >= 20
    }

    var hasAnalysisCache: Bool {
        analysisResult != nil
        && analysisStyleKey == activeStyle?.rawValue
        && analysisOriginalText == originalText
    }

    func clearAnalysisCache() {
        analysisTask?.cancel()
        analysisTask = nil
        // Reset the in-flight flag synchronously. `analysisTask.cancel()`
        // only signals cancellation; the task's catch block resets
        // `isAnalysing = false` later, after the cancelled URL request
        // unwinds (which can take seconds). On any user-initiated reset
        // path — "New", Edit Original, Use Output as Original, the
        // four-choice rephrase dialog — we want the grabber's in-flight
        // pulse to stop immediately, not a few seconds later. Setting
        // the flag here mirrors `clearFixesCache`'s synchronous reset of
        // `isFixesInFlight` and keeps the pulse-driving binding
        // `isAnyTellMeWorkInFlight = isAnalysing || isFixesInFlight`
        // collapsing to false the moment the cache is cleared.
        isAnalysing = false
        analysisResult = nil
        analysisStyleKey = nil
        analysisOriginalText = nil
        analysisError = nil
        // The Fixes cache is always invalidated alongside the Tell Me
        // cache: every site that mutates `originalText` or `activeStyle`
        // clears Tell Me, and the Fixes cache must follow because both
        // its key components have potentially changed.
        clearFixesCache()
    }

    /// Called when the user taps the analyse button.
    func onAnalyseButtonTapped() {
        if activeStyle == .plain {
            showSimpleFallbackAlert = true
            return
        }
        if hasAnalysisCache {
            showAnalysisSheet = true
            return
        }
        showAnalysisSheet = true
        analyseOriginal()
    }

    /// Called when user confirms SIMPLE fallback to LDN.
    func confirmSimpleFallbackToLDN() {
        showAnalysisSheet = true
        analyseOriginal(styleOverride: .aplus)
    }

    /// Runs the clause analysis API call.
    ///
    /// In-flight dedup: if a previous call is still awaiting a response,
    /// this returns early without firing a second request. The re-opened
    /// sheet will bind to the existing `isAnalysing` / `analysisResult`
    /// and display the same spinner / result.
    ///
    /// Cache invalidation on `originalText` change is handled by
    /// `hasAnalysisCache`, which keys on both `activeStyle` and the
    /// `originalText` snapshot from when the cache was written.
    func analyseOriginal(styleOverride: DraftingStyle? = nil) {
        // Dedup: skip if a previous request is still in flight.
        if analysisTask != nil { return }

        guard let clause = originalText,
              !clause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let style = styleOverride ?? activeStyle ?? .aplus

        if wordCount(clause) < 20 {
            analysisError = "The clause is too short for Tell Me. At least 20 words are required."
            return
        }

        if !NetworkMonitor.shared.isConnected {
            analysisError = DraftingError.offline.errorDescription
            return
        }

        if isBudgetExhausted {
            analysisError = DraftingError.budgetExhausted.errorDescription
            return
        }

        isAnalysing = true
        analysisError = nil

        let sysPrompt = AnalysisPrompts.buildSystemPrompt(style: style)
        let usrMsg = AnalysisPrompts.buildUserMessage(clause: clause)
        let clauseSnapshot = clause
        let effectiveStyleKey = (styleOverride ?? activeStyle)?.rawValue

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DraftingService.shared.rephraseRaw(
                    systemPrompt: sysPrompt,
                    userMessage: usrMsg,
                    maxTokens: 4000
                )

                guard !Task.isCancelled else {
                    self.isAnalysing = false
                    self.analysisTask = nil
                    return
                }

                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                if text == "[NOT_A_VC_CLAUSE]" {
                    self.analysisError = "This does not appear to be a venture-capital contract clause. Tell Me is only available for VC documentation (term sheets, investment agreements, shareholders' agreements, Satzung extracts, side letters, and Wandeldarlehen)."
                    self.isAnalysing = false
                    self.analysisTask = nil
                    return
                }

                self.analysisResult = text
                self.analysisStyleKey = effectiveStyleKey
                self.analysisOriginalText = clauseSnapshot
                self.isAnalysing = false
                self.analysisTask = nil

                await self.recordUsage(result)
            } catch let error as DraftingError where error == .userKeyInvalidFallbackAvailable {
                self.isAnalysing = false
                self.pendingSystemPrompt = sysPrompt
                self.pendingUserMessage = usrMsg
                self.pendingFlowKind = .analysis
                self.pendingMaxTokens = 4000
                self.showFallbackAlert = true
                self.analysisTask = nil
            } catch {
                self.isAnalysing = false
                self.analysisError = error.localizedDescription
                self.analysisTask = nil
            }
        }
    }

    // MARK: - Original Baseline (rebaseline helper)

    // ------------------------------------------------------------------
    // `rebaselineOriginal(to:)` is the SINGLE chokepoint for mutating
    // the locked Original. Every explicit promotion path
    // (`lockAsOriginal`, `commitEditingOriginal`, `useOutputAsOriginal`,
    // `confirmUseAsNewOriginal`, `confirmImportReplaceOriginal`,
    // `resetAll`, and the three Track Changes import branches) routes
    // through here so that the originalText assignment, cache
    // invalidation, undo-stack hygiene, bias-pill reset, and the
    // auto-Tell-Me hook all fire in a single canonical sequence.
    //
    // The helper owns ONLY the originalText-and-cache transition. It
    // does NOT touch `aiOutputText`, `currentText`, `clauseText`,
    // `isEditOnTheGo`, `hasGeneratedOutput`, `activeTab`,
    // `preEditClauseText`, `lastSnapshotWordCount`, `isDrawerExpanded`,
    // `isEditingOriginal`, `isTrackChangesRedlineMode`, `diffTokens`,
    // `lastDiff*`, `pendingRephraseAction`, or `pendingImportAction`.
    // Each promotion site retains its own writes for those fields
    // because every site has its own post-state shape.
    //
    // Implicit-write removal (Layer 1 of the AI-Flow Original Hygiene
    // plan) makes this helper the only writer of `originalText`. The
    // four AI-flow sites that previously mutated `originalText` as a
    // side-effect of an Output rephrase (`executeInstructionRephrase`'s
    // `.ok` EditOnTheGo branch, `executeRephrase`'s EditOnTheGo branch,
    // `executeRephrase`'s pre-lock fallback, and the BYOK retry mirror
    // in `retryWithSystemKey`) no longer write `originalText` at all.
    // ------------------------------------------------------------------

    /// Centralised mutation of the locked Original. See the section
    /// header above for the full contract.
    ///
    /// - Parameter newText:
    ///   - non-nil → promote `newText` to the locked Original.
    ///   - nil     → clear the Original (the resetAll / fresh-import
    ///     path).
    ///
    /// Access: `internal` (the default), not `private`, because the
    /// Track Changes import path lives in `DraftingViewModel+TrackChanges.swift`
    /// — a separate file extension that cannot see `private`/`fileprivate`
    /// members of this type. Mirrors the access of the existing
    /// `setAiOutputText` / `setCurrentText` cross-file setters.
    func rebaselineOriginal(to newText: String?, suppressAutoTellMe: Bool = false) {
        // 1. Mutate the baseline.
        originalText = newText

        // 2. Cancel and clear Tell Me / Revise tasks and caches.
        //    `clearAnalysisCache` transitively calls `clearFixesCache`,
        //    so both pulse-driving flags collapse on this same UI tick.
        clearAnalysisCache()

        // 3. Drop the bias-pill cache. Variants were keyed against the
        //    old Original; under the new baseline they are stale.
        rephraseCache.removeAll()

        // 4. Clear the bias-pill selection so the indicator does not
        //    visually point at a heat that is no longer cached.
        selectedHeat = nil

        // 5. Wipe all undo/redo stacks. The new baseline is a clean
        //    boundary; pre-baseline undos would replay across an
        //    invariant the user just changed.
        clearAllUndoStacks()

        // 6. Honour the auto-Tell-Me setting. `maybeAutoTriggerTellMe`
        //    is internally guarded by `originalText != nil`, so the
        //    nil-clear path short-circuits here. Skip the call
        //    explicitly anyway to avoid an unnecessary UserDefaults
        //    read on every clear.
        //
        //    `suppressAutoTellMe`: passed `true` only by the Memory
        //    restore path (`restore(from:)`). The persisted Tell Me
        //    cache is restored a few lines after this call returns;
        //    triggering an automatic fresh analysis here would throw
        //    that cache away on the next render.
        if newText != nil && !suppressAutoTellMe {
            maybeAutoTriggerTellMe()
        }

        // 7. Coalesce the change for SwiftUI observers. Each step above
        //    already fires its own willSet/objectWillChange; this final
        //    send is defensive — it ensures observers that key on
        //    (originalText, cache state) together see the post-state in
        //    a single render pass.
        objectWillChange.send()
    }

    // MARK: - Fixes

    // ------------------------------------------------------------------
    // The "Revise" feature surfaces concrete drafting revisions derived
    // from the Tell Me analysis. The user opens it from the drawer (the
    // "Revise" button replaces the former active-style pill). On tap, the
    // view-model checks the local Fixes cache; on miss it fires the
    // Fixes API call (and, if no Tell Me cache exists, fires Tell Me
    // first via the existing `analyseOriginal(styleOverride:)` path).
    // Tapping a card writes the instruction into the Additional
    // Instructions field and triggers the existing single-variant
    // rephrase. The Fixes feature owns nothing about redrafting — it
    // only owns the moment of "user picked a fix".
    //
    // Cache key: (originalText, activeStyle) — the user-facing active
    // style. Under SIMPLE-fallback the key is (Original, .plain)
    // even though the underlying analysis runs under .aplus.
    // ------------------------------------------------------------------

    /// Per-(originalText, activeStyle) cache of validated, deduped Fixes
    /// groups. Populated by `triggerFixesFlow` after pre-validation runs.
    /// Memory-only (matches the Tell Me cache lifetime).
    var fixesCache: [FixesCacheKey: FixesGroups] = [:] {
        willSet { objectWillChange.send() }
    }

    /// Applied-flag dictionary keyed by `instructionHash`. Survives
    /// re-fetches because the same instruction text always hashes to the
    /// same key. Reset to empty whenever clause text or active style
    /// changes (see `clearFixesCache`).
    var fixesAppliedFlags: [String: Bool] = [:] {
        willSet { objectWillChange.send() }
    }

    /// True while the Fixes API call is in flight. Combined with
    /// `isAnalysing` via `isAnyTellMeWorkInFlight` to drive the grabber's
    /// in-flight pulse.
    var isFixesInFlight: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// True when the user is currently typing in a text field at the
    /// moment Revise results land. Drives the "Revise — ready" banner above
    /// the bottom input section. Cleared on banner dismiss, cache
    /// invalidation, and sheet open.
    var showFixesReadyBanner: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Controls presentation of the Fixes sheet.
    var showFixesSheet: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Controls presentation of the pre-Tell-Me informational alert. Only
    /// shown on the auto-fire path (no Tell Me cache exists). The Tell Me
    /// API call fires in parallel with the alert; dismissal is purely
    /// informational.
    var showFixesPreTellMeAlert: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// True when the pre-Tell-Me alert is the SIMPLE merged variant
    /// (covers both the SIMPLE-fallback notice and the Tell-Me-running
    /// notice in a single alert).
    var fixesPreTellMeAlertIsSIMPLE: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Phase-tagged error message for the Fixes feature, distinct from
    /// the global `errorMessage` so a Fixes failure does not erase a
    /// pre-existing error from another flow. Composed at the call site
    /// per plan §7.5: "<phase prefix> <existing errorDescription>".
    var fixesError: String? {
        willSet { objectWillChange.send() }
    }

    /// In-flight task for the Fixes API call. Used for cancellation only
    /// — the cache-key check inside the task body discards stale results
    /// so cancellation is rarely needed. Cleared at the end of every
    /// terminal branch.
    private var fixesTask: Task<Void, Never>?

    /// True if the current `(Original, activeStyle)` pair has a Fixes
    /// cache entry.
    var hasFixesCacheForCurrent: Bool {
        guard let key = currentFixesCacheKey else { return false }
        return fixesCache[key] != nil
    }

    /// True if the cached entry for the current key is the empty
    /// three-array result (the model ran but returned no fixes, or all
    /// items were dropped by pre-validation/dedupe).
    var fixesCacheForCurrentIsEmpty: Bool {
        guard let key = currentFixesCacheKey,
              let groups = fixesCache[key] else { return false }
        return groups.isEmpty
    }

    /// **Style-agnostic** counterpart to `hasAnalysisCache`. Drives the
    /// grabber bar colour. Returns true whenever an analysis exists for
    /// the current Original under any style — so under SIMPLE-fallback
    /// (analysis stored under `.aplus`, `activeStyle == .plain`) the
    /// grabber stays indigo. `hasAnalysisCache` itself remains the gate
    /// for the Tell Me sheet's existing cache logic and is untouched.
    var hasAnalysisForCurrentOriginal: Bool {
        analysisResult != nil
        && analysisOriginalText == originalText
    }

    /// Single binding for the grabber's in-flight pulse and the Revise
    /// button's disabled-but-no-spinner state. Pulses while EITHER the
    /// Tell Me analysis OR the Revise generation is in flight, including
    /// the Revise auto-fire path where Tell Me runs first followed by
    /// the Revise call.
    var isAnyTellMeWorkInFlight: Bool {
        isAnalysing || isFixesInFlight
    }

    /// Returns the cache key for the current `(originalText, activeStyle)`
    /// pair, or nil when either is missing.
    var currentFixesCacheKey: FixesCacheKey? {
        guard let original = originalText,
              !original.isEmpty,
              let style = activeStyle else { return nil }
        return FixesCacheKey(originalText: original, style: style)
    }

    /// True iff every gate in the §4.2 disabled-state table allows the
    /// Fixes button to be tapped (other than the cached / no-cached
    /// variants which only affect appearance, not enabled-ness).
    var canTriggerFixes: Bool {
        guard !isLoading,
              !isAnalysing,
              !isFixesInFlight,
              hasGeneratedOutput,
              let original = originalText,
              wordCount(original) >= 20 else {
            return false
        }
        if isBudgetExhausted { return false }
        if !NetworkMonitor.shared.isConnected && !hasFixesCacheForCurrent {
            return false
        }
        return true
    }

    // MARK: Triggers

    /// Entry point invoked by the "Revise" button. Decides between four
    /// paths in priority order:
    /// 1. Cache hit → open the sheet directly (no API call).
    /// 2. Tell Me already in flight → await it, then fire Fixes if cache
    ///    key still matches.
    /// 3. Tell Me cache present but no Fixes cache → fire Fixes only.
    /// 4. Neither cache present → fire Tell Me + Fixes (the auto-fire
    ///    path), with the pre-Tell-Me informational alert in parallel.
    func triggerFixesFlow() {
        guard canTriggerFixes else { return }

        // Path 1: cache hit.
        if hasFixesCacheForCurrent {
            showFixesSheet = true
            return
        }

        // Path 2: Tell Me already in flight (user tapped the Tell Me
        // pill seconds earlier). Do not fire a parallel Tell Me; do not
        // show the pre-Tell-Me alert (its "Tell Me hasn't been run yet"
        // copy would be misleading). Wait for the existing task and
        // fire Fixes if the cache key still matches.
        if let inflight = analysisTask {
            isFixesInFlight = true
            fixesTask = Task { @MainActor [weak self] in
                _ = await inflight.value
                guard let self else { return }
                self.fireFixesCallIfCacheStillValid(initialKey: self.currentFixesCacheKey)
            }
            return
        }

        // Path 3: an analysis exists for the current Original (any
        // style), Fixes cache absent. Use the style-agnostic property
        // so the SIMPLE-fallback case works too — the analysis was
        // stored under .aplus but is still usable for Fixes generation.
        if hasAnalysisForCurrentOriginal {
            isFixesInFlight = true
            fireFixesCallIfCacheStillValid(initialKey: currentFixesCacheKey)
            return
        }

        // Path 4: auto-fire path. Show the pre-Tell-Me alert (SIMPLE
        // merged variant or non-SIMPLE single-button variant) AND fire
        // Tell Me in parallel — the alert is informational only and
        // does not gate the call. Fire Fixes when Tell Me returns.
        let isSIMPLE = (activeStyle == .plain)
        fixesPreTellMeAlertIsSIMPLE = isSIMPLE
        showFixesPreTellMeAlert = true

        // Use the existing analyseOriginal path so the analysisTask
        // dedup guard is honoured. Under SIMPLE we override to .aplus.
        let styleOverride: DraftingStyle? = isSIMPLE ? .aplus : nil
        analyseOriginal(styleOverride: styleOverride)

        // Once Tell Me returns, fire Fixes against the cache key the
        // user saw at tap-time (not the runtime style override — Fixes
        // is keyed on the user-facing style per §8.1). If the user
        // edits the clause during the wait, the cache-key check inside
        // fireFixesCallIfCacheStillValid silently discards the result.
        let initialKey = currentFixesCacheKey
        isFixesInFlight = true
        fixesTask = Task { @MainActor [weak self] in
            // Spin until isAnalysing returns to false. Tell Me's task
            // body sets isAnalysing = false on every terminal branch
            // (success, NOT_A_FINANCE, fallback, error), so this is a
            // bounded wait.
            while self?.isAnalysing == true {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                if Task.isCancelled { return }
            }
            guard let self else { return }
            // If Tell Me failed (no analysis populated), surface a
            // phase-tagged error and abort. We check
            // `hasAnalysisForCurrentOriginal` rather than
            // `hasAnalysisCache`: under SIMPLE-fallback the analysis
            // is stored under .aplus while activeStyle is .plain, so
            // `hasAnalysisCache` returns false even on success.
            guard self.hasAnalysisForCurrentOriginal else {
                self.isFixesInFlight = false
                self.fixesTask = nil
                if let analysisErr = self.analysisError {
                    self.fixesError = "Couldn't analyse the clause. \(analysisErr)"
                } else {
                    self.fixesError = "Couldn't analyse the clause."
                }
                return
            }
            self.fireFixesCallIfCacheStillValid(initialKey: initialKey)
        }
    }

    /// Sends the Fixes API call against the current cached Tell Me
    /// result. Pre-condition: `hasAnalysisCache == true`. The
    /// `initialKey` argument is the cache key the user saw at tap-time
    /// — if it has changed by the time the call returns (e.g. clause
    /// edited mid-flight), the result is discarded silently.
    private func fireFixesCallIfCacheStillValid(initialKey: FixesCacheKey?) {
        guard let style = activeStyle,
              let original = originalText,
              let analysis = analysisResult else {
            isFixesInFlight = false
            fixesTask = nil
            return
        }
        // Re-check cache key.
        guard let currentKey = currentFixesCacheKey,
              currentKey == initialKey else {
            isFixesInFlight = false
            fixesTask = nil
            return
        }

        // Pre-flight network and budget checks (mirror Tell Me).
        if !NetworkMonitor.shared.isConnected {
            isFixesInFlight = false
            fixesTask = nil
            fixesError = "Couldn't generate revisions. \(DraftingError.offline.errorDescription ?? "")"
            return
        }
        if isBudgetExhausted {
            isFixesInFlight = false
            fixesTask = nil
            fixesError = "Couldn't generate revisions. \(DraftingError.budgetExhausted.errorDescription ?? "")"
            return
        }

        isFixesInFlight = true
        let langSnapshot = selectedLanguage
        // Under SIMPLE-fallback, Tell Me ran under .aplus so the analysis
        // text is LDN-flavoured. Pass .aplus explicitly to the Fixes call
        // so the persona aligns with the analysis the model is
        // reasoning over. The cache key, however, is keyed on the
        // user-facing active style (`.plain` here) per §8.1.
        let promptStyle: DraftingStyle = (style == .plain) ? .aplus : style

        fixesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await DraftingService.shared.generateFixes(
                    style: promptStyle,
                    originalText: original,
                    tellMeResult: analysis,
                    language: langSnapshot
                )
                // Cache-key re-check after await.
                guard let nowKey = self.currentFixesCacheKey,
                      nowKey == currentKey else {
                    self.isFixesInFlight = false
                    self.fixesTask = nil
                    return
                }

                // Pre-validation + cross-group dedupe.
                let validated = FixesPrompt.validateAndDedup(result.groups)
                self.fixesCache[currentKey] = validated
                self.isFixesInFlight = false
                self.fixesTask = nil

                await self.recordUsage(DraftingService.RephraseResult(
                    text: "",
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens
                ))

                // Hybrid open rule per §3.6 — the view layer evaluates
                // focus state via the bound flags. Default: try to
                // auto-open. Views set showFixesReadyBanner instead
                // when a text field is focused.
                self.presentFixesResultArrival()
            } catch {
                self.isFixesInFlight = false
                self.fixesTask = nil
                if let de = error as? DraftingError {
                    self.fixesError = "Couldn't generate revisions. \(de.errorDescription ?? "")"
                } else {
                    self.fixesError = "Couldn't generate revisions. \(error.localizedDescription)"
                }
            }
        }
    }

    /// Set true by the Fixes-completion path the moment results land.
    /// The view layer observes this flag, reads its own focus state
    /// (clause editor / additional instructions field), and decides
    /// whether to auto-open the sheet (`showFixesSheet = true`) or to
    /// show the "Revise — ready" banner instead
    /// (`showFixesReadyBanner = true`). The view clears this flag
    /// immediately after dispatching, so it only ever drives a single
    /// presentation event per Fixes call.
    var fixesResultsAwaitingPresentation: Bool = false {
        willSet { objectWillChange.send() }
    }

    /// Hybrid open rule per §3.6. Default behaviour at the view-model
    /// layer: signal the view that results are ready. The view layer
    /// then evaluates focus state and routes to either the sheet or the
    /// banner. Keeping the focus check in the view layer avoids
    /// leaking SwiftUI `@FocusState` into the view-model.
    func presentFixesResultArrival() {
        fixesResultsAwaitingPresentation = true
    }

    // MARK: Card tap

    /// Apply a fix: write the instruction into the Additional
    /// Instructions field, dismiss the sheet, mark applied, and fire
    /// the existing single-variant rephrase entry point.
    func applyFix(_ item: FixItem) {
        fixesAppliedFlags[item.instructionHash] = true
        showFixesSheet = false
        showFixesReadyBanner = false
        additionalInstruction = item.instruction
        triggerInstructionRephrase()
    }

    // MARK: Lifecycle helpers

    /// Returns true if the given fix has been applied previously in this
    /// session (independent of cache key — instruction-hash-keyed).
    func isFixApplied(_ item: FixItem) -> Bool {
        fixesAppliedFlags[item.instructionHash] == true
    }

    /// Dismiss the "Revise — ready" banner explicitly (X tap or swipe-down).
    func dismissFixesReadyBanner() {
        showFixesReadyBanner = false
    }

    /// Clear the Fixes cache and applied-flag dictionary. Called from
    /// every site that invalidates the Tell Me cache (clause edits,
    /// "Use as New Original", `resetAll()`).
    func clearFixesCache() {
        fixesTask?.cancel()
        fixesTask = nil
        isFixesInFlight = false
        fixesCache.removeAll()
        fixesAppliedFlags.removeAll()
        showFixesReadyBanner = false
        showFixesSheet = false
        showFixesPreTellMeAlert = false
        fixesError = nil
    }

    // MARK: - Private

    /// The locked original text. Mutated only via `rebaselineOriginal(to:)`
    /// — the single chokepoint for every explicit promotion path
    /// (Lock pill, Edit Original commit, Use Output as Original, the
    /// overwrite dialogs, New, and the three Track Changes import
    /// branches). The legacy `setOriginalText(_:)` cross-file setter
    /// was removed alongside Layer 2 of the AI-Flow Original Hygiene
    /// migration; Track Changes now calls `rebaselineOriginal` directly.
    private(set) var originalText: String?
    /// Snapshot of the AI output, frozen when rephrase completes.
    /// Used as the middle layer for three-layer diff.
    private(set) var aiOutputText: String?
    /// The current output text (synced with clauseText on the Output tab).
    private(set) var currentText: String = ""

    /// Internal setters for use by extensions in separate files.
    func setAiOutputText(_ text: String?) { aiOutputText = text }
    func setCurrentText(_ text: String) { currentText = text }
    private let service: DraftingService
    private var rephrasTask: Task<Void, Never>?
    /// Monotonically increasing identifier for the active rephrase task.
    /// Each `executeRephrase` / `executeInstructionRephrase` / `retryWithSystemKey`
    /// / `performPhotoCleanUp` call increments this value and
    /// captures the current value locally. Before any awaited task writes back
    /// to UI state (isLoading, errorMessage, clauseText, caches, ...) it
    /// compares its captured value against `rephraseGeneration`. If they differ,
    /// a newer task has superseded this one and all state writes must be
    /// skipped. This prevents stale completions from trampling fresh state
    /// (e.g. a slow N rephrase overwriting an already-completed L1 rephrase).
    private var rephraseGeneration: Int = 0
    /// Starts a new rephrase generation. Call immediately before kicking off a
    /// `rephrasTask`. Returns the new generation id for the caller to capture.
    private func nextRephraseGeneration() -> Int {
        rephraseGeneration &+= 1
        return rephraseGeneration
    }
    /// True if the given generation is still the active one and the task was
    /// not cancelled. All post-await state writes should be gated on this.
    private func isGenerationCurrent(_ gen: Int) -> Bool {
        return gen == rephraseGeneration && !Task.isCancelled
    }
    private let maxInputLength = 5000
    private let logger = Logger(subsystem: "com.daimos.chimera", category: "DraftingVM")

    /// Cache of rephrase results keyed by style+heat. The bias-tap flow
    /// no longer reads the AI instruction (full-independence model — see
    /// AdditionalInstructionPrompt and the redesign plan §2.0 / §6.6), so
    /// the cache key reduces from `(style, heat, instruction)` to
    /// `(style, heat)`. Enables deterministic output when toggling back
    /// and forth between two style/heat combinations.
    var rephraseCache: [String: String] = [:]

    // MARK: - Undo / Redo (unified back chain)
    //
    // One shared back chain across the Output and Show Changes tabs.
    // Every text-changing event — manual word edit on Output,
    // tap-to-revert on Show Changes, founder/investor bias tap, stage
    // tap, Additional Instruction rephrase, Revise card tap, "My
    // current draft" rephrase — pushes one `UndoSnapshot` of
    // `(currentText, aiOutputText, hasManualEdits)`.
    //
    // The chain is wiped only at deliberate fresh-start boundaries
    // (lock, "Use Output as Original", "Make my draft the new
    // Original", import-overwrite both branches, Show-as-Redline
    // import, "Discard & Rephrase" overwrite confirmation, Edit
    // Original entry and commit, Memory slot load, and Reset). Tab
    // switching does not wipe the chain — only flushes a pending
    // word-boundary snapshot. Pre-lock typing and any typing on the
    // Original tab do not push.

    /// One back-step in the unified undo/redo chain.
    ///
    /// Carries only the fields needed to rewind the visible wording
    /// and keep the four-choice ("Discard / My current draft / Use as
    /// new Original") dialog gating correct after a rewind:
    /// - `currentText`: the post-AI / post-edit editor wording.
    /// - `aiOutputText`: the most recent AI variant the Show Changes
    ///   tab diffs against; nil during pre-AI Edit-On-The-Go.
    /// - `hasManualEdits`: whether the user had unsaved manual edits
    ///   at the moment of capture, so the four-choice dialog gate
    ///   stays correct after an undo into a manual-edits state.
    ///
    /// Bias selection, Additional Instruction text, Revise "applied"
    /// badges, the Tell Me / Revise caches, and `hasGeneratedOutput`
    /// are intentionally NOT snapshotted — see `restoreFromUndoSnapshot`
    /// for the rationale.
    struct UndoSnapshot: Equatable {
        let currentText: String
        let aiOutputText: String?
        let hasManualEdits: Bool
    }

    private static let maxUndoStackSize = 50

    /// Unified back chain. Visible to the view as a non-empty/empty
    /// signal via `showUndoRedoPill`, `canUndo`, `canRedo`.
    private(set) var undoStack: [UndoSnapshot] = []
    private(set) var redoStack: [UndoSnapshot] = []

    /// Guard flag: suppresses snapshot recording during programmatic
    /// changes to clauseText (undo/redo replay, tab switch, rephrase
    /// result land, memory restore). Read by the view's `onChange`
    /// block to skip the word-boundary push during programmatic writes.
    var isSuppressingSnapshot: Bool = false

    /// The `clauseText` value at the start of the current Output-tab
    /// editing burst. Pushed onto `undoStack` when a word boundary is
    /// crossed (see `pushOutputWordBoundarySnapshot`).
    var preEditClauseText: String = ""

    /// Word count at the time of the last Output-tab snapshot, used by
    /// the view's `onChange` block to detect word-boundary crossings.
    var lastSnapshotWordCount: Int = 0

    /// Pill visible on Output and Show Changes whenever the unified
    /// chain has at least one entry and an Original is locked. Hidden
    /// on the Original tab and pre-lock (where the chain is empty by
    /// invariant anyway).
    var showUndoRedoPill: Bool {
        activeTab != .original
            && originalText != nil
            && (!undoStack.isEmpty || !redoStack.isEmpty)
    }

    var canUndo: Bool { activeTab != .original && !undoStack.isEmpty }
    var canRedo: Bool { activeTab != .original && !redoStack.isEmpty }

    /// Wipes both stacks. Called by every fresh-start boundary listed
    /// in the section header above.
    func clearAllUndoStacks() {
        undoStack.removeAll()
        redoStack.removeAll()
        objectWillChange.send()
    }

    /// Compose a snapshot of the current live state.
    private func currentSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            currentText: currentText,
            aiOutputText: aiOutputText,
            hasManualEdits: hasManualEdits
        )
    }

    /// Push a snapshot onto the unified back chain. Used by every
    /// AI-rephrase completion path (cache hit, multi-variant `.ok`,
    /// instruction `.ok`, BYOK retries), the "My current draft"
    /// rephrase confirmation, and the Show Changes tap-to-revert
    /// path. Callers MUST invoke this BEFORE the visible-text writes
    /// so the *pre*-mutation state is what gets recorded.
    func pushSnapshot() {
        guard !isSuppressingSnapshot else { return }
        // Defensive sync: on the Output tab the editor binding
        // (`clauseText`) leads `currentText` between word-boundary
        // pushes. Without this line, a snapshot taken in the middle
        // of an editing burst (e.g. user types three words then
        // taps a bias before the next word boundary lands) would
        // record a stale `currentText`.
        if activeTab == .current { currentText = clauseText }
        let snap = currentSnapshot()
        if undoStack.last == snap { return }
        undoStack.append(snap)
        if undoStack.count > Self.maxUndoStackSize { undoStack.removeFirst() }
        redoStack.removeAll()
        objectWillChange.send()
    }

    /// Output-tab word-boundary push. Called from `DraftingView`'s
    /// `onChange(of: clauseText)` when the word count changes.
    /// Records the *pre*-edit clauseText so undo walks back to the
    /// start of the current word, not into its middle. Pre-lock
    /// typing (no Original) and any typing on the non-Output tab do
    /// not push.
    func pushOutputWordBoundarySnapshot() {
        guard !isSuppressingSnapshot else { return }
        guard activeTab == .current else { return }
        guard originalText != nil else { return }
        guard preEditClauseText != clauseText else { return }
        let snap = UndoSnapshot(
            currentText: preEditClauseText,
            aiOutputText: aiOutputText,
            hasManualEdits: hasManualEdits
        )
        if undoStack.last != snap {
            undoStack.append(snap)
            if undoStack.count > Self.maxUndoStackSize {
                undoStack.removeFirst()
            }
            redoStack.removeAll()
        }
        preEditClauseText = clauseText
        lastSnapshotWordCount = wordCount(clauseText)
        objectWillChange.send()
    }

    /// Flush a pending word-boundary edit into the chain. Used by
    /// `switchTab` so an in-progress burst is not lost when the user
    /// navigates away from Output.
    func flushPendingOutputSnapshot() {
        pushOutputWordBoundarySnapshot()
    }

    /// Walk the chain back one step. Cancels any in-flight rephrase
    /// so a late completion cannot land on top of the restored
    /// state. Pushes the pre-undo state onto `redoStack` for symmetry.
    /// Re-triggers the Memory auto-save so the persisted state matches
    /// what the user sees after the rewind.
    func undo() {
        guard let snap = undoStack.popLast() else { return }
        rephrasTask?.cancel()
        isLoading = false
        clearError()
        let oldDiff = diffTokens
        redoStack.append(currentSnapshot())
        restoreFromUndoSnapshot(snap)
        if activeTab == .showChanges {
            setScrollTargetAtFirstDifference(from: oldDiff, to: diffTokens)
        }
        scheduleMemoryAutoSaveIfPossible()
    }

    /// Walk the chain forward one step. Mirror of `undo()`.
    func redo() {
        guard let snap = redoStack.popLast() else { return }
        rephrasTask?.cancel()
        isLoading = false
        clearError()
        let oldDiff = diffTokens
        undoStack.append(currentSnapshot())
        restoreFromUndoSnapshot(snap)
        if activeTab == .showChanges {
            setScrollTargetAtFirstDifference(from: oldDiff, to: diffTokens)
        }
        scheduleMemoryAutoSaveIfPossible()
    }

    /// Apply a snapshot to the live state.
    ///
    /// `isEditOnTheGo` is re-derived from the restored text; this is
    /// correct ONLY because every Edit-Original entry/commit is itself
    /// a wipe boundary, so an undo cannot cross into Edit-Original
    /// territory.
    ///
    /// `selectedHeat = nil` is a visual reset so the bias capsule does
    /// not point at a heat that may no longer match the restored text.
    /// `rephraseCache` is left intact, so re-tapping the same bias is
    /// still a cache hit. The view's `.onChange(of: selectedHeat)` bails
    /// on `newHeat != nil`, so the nil assignment does not re-enter
    /// `triggerRephrase`.
    ///
    /// `hasGeneratedOutput` is NOT re-derived because Lock is a wipe
    /// boundary, so it is stable (true post-lock) across the chain.
    private func restoreFromUndoSnapshot(_ snap: UndoSnapshot) {
        isSuppressingSnapshot = true
        currentText           = snap.currentText
        clauseText            = snap.currentText
        aiOutputText          = snap.aiOutputText
        preEditClauseText     = snap.currentText
        lastSnapshotWordCount = wordCount(snap.currentText)
        hasManualEdits        = snap.hasManualEdits
        isEditOnTheGo        = (snap.aiOutputText == nil) && (originalText != nil)
        selectedHeat = nil
        if activeTab == .showChanges { recomputeDiffTokens() }
        recomputeExportTokens()
        isSuppressingSnapshot = false
        objectWillChange.send()
    }

    /// Computes which token to scroll to after an undo/redo on the
    /// Show Changes tab by finding the first index where the
    /// before/after diff arrays differ, and exposes the UUID via
    /// `scrollTargetTokenId` for the view to consume.
    private func setScrollTargetAtFirstDifference(from before: [DiffToken], to after: [DiffToken]) {
        let count = min(before.count, after.count)
        for i in 0..<count {
            if before[i].type != after[i].type
                || before[i].text != after[i].text
                || before[i].source != after[i].source {
                scrollTargetTokenId = after[i].id
                scrollTargetBump &+= 1
                return
            }
        }
        // One array is a prefix of the other — scroll to the shorter-end token.
        if after.count > before.count {
            scrollTargetTokenId = after[count].id
            scrollTargetBump &+= 1
        } else if before.count > after.count, count > 0 {
            scrollTargetTokenId = after[count - 1].id
            scrollTargetBump &+= 1
        }
    }

    /// Counts words in a string (matches WordDiff.tokenize logic).
    func wordCount(_ text: String) -> Int {
        text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace }).count
    }

    // MARK: - Init

    init(service: DraftingService? = nil) {
        self.service = service ?? DraftingService.shared
    }

    // MARK: - Budget Helpers

    var budgetProgress: Double {
        guard !service.isUsingUserKey else { return 0 }
        return monthlyUsage?.budgetProgress(budget: service.monthlyBudgetUSD) ?? 0
    }

    var isBudgetExhausted: Bool {
        guard !service.isUsingUserKey else { return false }
        return monthlyUsage?.isBudgetExhausted(budget: service.monthlyBudgetUSD) ?? false
    }

    var budgetBarColor: Color {
        if budgetProgress >= 1.0 { return .dkError }
        if budgetProgress >= 0.75 { return .dkWarning }
        return .dkSuccess
    }

    // MARK: - Load Usage

    func loadMonthlyUsage() async {
        do {
            monthlyUsage = try await CloudKitService.shared.fetchOrCreateMonthlyUsage()
        } catch {
            logger.error("Failed to load monthly usage: \(error.localizedDescription)")
        }
    }

    // MARK: - Style & Heat Changes

    func onStyleChanged(to style: DraftingStyle) {
        // Suppress re-trigger when we're restoring a previous selection
        // (e.g. after the user cancelled the overwrite warning).
        if isRestoringSelection { return }
        activeStyle = style
        triggerRephrase()
    }

    func onHeatChanged(to heat: HeatLevel) {
        // Suppress re-trigger when we're restoring a previous selection
        // (e.g. after the user cancelled the overwrite warning). Without
        // this guard, cancelling the warning restores the heat, which
        // re-enters triggerRephrase and shows the warning again, looping.
        if isRestoringSelection { return }
        selectedHeat = heat
        triggerRephrase()
    }

    /// Reverts `selectedHeat` to a prior value without re-entering the bias
    /// `onChange` handler. Used when a bias tap must be rejected (e.g. while
    /// another rephrase is in flight) so the capsule animates back to what
    /// was actually selected.
    func revertHeatSelection(to heat: HeatLevel?) {
        isRestoringSelection = true
        selectedHeat = heat
        isRestoringSelection = false
    }

    // MARK: - Instruction-Only Rephrase

    /// Called from the send button / onSubmit. The Send button is disabled
    /// when the trimmed instruction is empty (see DraftingView's Send-button
    /// gating), so the empty case is structurally unreachable from the UI.
    /// Resets the bias indicator to no-selection (full-independence model
    /// — the AI flow does not consume the bias slider) and runs a
    /// single-variant rephrase against the dedicated AI-flow prompt.
    func triggerInstructionRephrase() {
        let instruction = additionalInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            // Defensive: the Send button's disable binding gates this on a
            // non-empty trimmed instruction, so reaching here means a stale
            // call site. Make it loud rather than silent.
            assertionFailure("AI flow invoked with empty instruction")
            return
        }

        // Deselect heat without triggering onChange. Style is intentionally
        // preserved — the AI flow consumes the active style persona via
        // AdditionalInstructionPrompt's Rule 1, so resetting it would erase
        // a real input. The asymmetric reset is deliberate.
        isRestoringSelection = true
        selectedHeat = nil
        isRestoringSelection = false

        // Cache and undo wipes are deferred to the OK branch of
        // executeInstructionRephrase(). Pre-committing them here would mean
        // a rejected or failed call still destroys prior state, breaking
        // the "rejection preserves prior state" invariant.

        executeInstructionRephrase()
    }

    private func executeInstructionRephrase() {
        guard let style = activeStyle else { return }

        if !NetworkMonitor.shared.isConnected {
            setError(.offline)
            return
        }
        if isBudgetExhausted {
            setError(.budgetExhausted)
            return
        }

        // PRE-AWAIT: capture only what we need for the call. Do NOT mutate
        // originalText, aiOutputText, isEditOnTheGo, hasGeneratedOutput,
        // hasManualEdits, rephraseCache, or any undo stack. The mutations
        // move to the .ok branch so a rejected / failed / cancelled call
        // leaves the user's prior state intact.
        let source: String = {
            if isEditOnTheGo {
                return currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if hasGeneratedOutput,
               !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return currentText
            }
            if let original = originalText { return original }
            return clauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        guard !source.isEmpty else { return }

        let wasEditOnTheGo = isEditOnTheGo

        let instruction = additionalInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        // Defensive: triggerInstructionRephrase already asserts non-empty,
        // and the Send-button gating prevents an over-the-cap payload, but
        // re-check here so any future programmatic caller is also safe.
        guard !instruction.isEmpty else { return }
        let language = selectedLanguage

        rephrasTask?.cancel()
        isLoading = true
        clearError()
        let gen = nextRephraseGeneration()

        rephrasTask = Task {
            do {
                let result = try await self.service.rephraseAdditionalInstruction(
                    style: style,
                    language: language,
                    sourceText: source,
                    instruction: instruction
                )

                // A newer task (e.g. the user tapped a different bias while
                // we were awaiting the API) has superseded us. Drop the
                // result so a stale completion cannot land on top of fresh
                // state.
                guard self.isGenerationCurrent(gen) else { return }

                switch result.outcome {
                case .ok(let text):
                    // EditOnTheGo transition is committed only now, after a
                    // confirmed-OK rephrase. Rejection / failure / cancel
                    // leave the user in EditOnTheGo with their current text
                    // untouched.
                    //
                    // Rule C (Output text changes are agnostic to Tell Me /
                    // Revise state): do NOT promote `source` to
                    // `originalText` here. The user did not ask to change
                    // the baseline; they asked for a rephrase. Tell Me /
                    // Revise caches keyed on the (unchanged) `originalText`
                    // therefore remain valid, so the next Revise tap is a
                    // cache hit. `hasGeneratedOutput` is left untouched —
                    // post-lock it is already true and `signalRephraseCompleted`
                    // (called below) re-asserts true on success.
                    if wasEditOnTheGo {
                        self.isEditOnTheGo = false
                    }

                    // Unified undo: record the pre-rephrase state so undo
                    // walks back to the wording the user had before this
                    // Additional-Instruction rephrase landed. Must run
                    // BEFORE the visible-text writes below. Under full
                    // independence the bias-tap cache key is (style, heat)
                    // only, so a successful AI rephrase does not invalidate
                    // `rephraseCache` — it is intentionally NOT cleared.
                    self.pushSnapshot()

                    self.isSuppressingSnapshot = true
                    self.aiOutputText = text
                    self.currentText = text
                    self.clauseText = text
                    self.isLoading = false
                    self.hasManualEdits = true
                    // Q2 resolution: clear the AI field on success so the
                    // next run requires fresh intent.
                    self.additionalInstruction = ""
                    self.signalRephraseCompleted(showDiff: true,
                                                 preserveTab: false)
                    self.isSuppressingSnapshot = false

                case .rejected(let category, let reason):
                    // Do NOT touch originalText, aiOutputText, currentText,
                    // clauseText, isEditOnTheGo, hasGeneratedOutput,
                    // rephraseCache, or any undo stack. The pre-await block
                    // also did not mutate them, so the user's prior state
                    // is intact. additionalInstruction is preserved so the
                    // user can edit two words and retry.
                    self.isLoading = false
                    self.presentInstructionRejection(
                        category: category,
                        reason: reason
                    )
                }

                await self.recordUsage(DraftingService.RephraseResult(
                    text: "",
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens
                ))
            } catch is CancellationError {
                // Same invariant as the rejected branch: no state was
                // mutated pre-await, so cancellation needs no rollback.
                return
            } catch let error as DraftingError where error == .userKeyInvalidFallbackAvailable {
                guard self.isGenerationCurrent(gen) else { return }
                self.isLoading = false
                // Stash the AI-flow context so retryWithSystemKey routes
                // through the parsing-aware path
                // (rephraseAdditionalInstructionWithSystemKey).
                self.pendingFlowKind = .aiInstruction
                self.pendingAdditionalInstructionContext = .init(
                    style: style,
                    language: language,
                    sourceText: source,
                    instruction: instruction,
                    wasEditOnTheGo: wasEditOnTheGo
                )
                self.showFallbackAlert = true
            } catch {
                guard self.isGenerationCurrent(gen) else { return }
                self.isLoading = false
                // Same as the rejected branch: prior state was not mutated
                // pre-await, so the user's editor and locked Original are
                // preserved automatically.
                if let de = error as? DraftingError {
                    self.setError(de, retry: { [weak self] in
                        self?.executeInstructionRephrase()
                    })
                } else {
                    self.errorMessage = error.localizedDescription
                    self.errorKind = nil
                }
            }
        }
    }

    // MARK: - Rephrase (Multi-Variant: generates all 5 heat levels in one call)

    func triggerRephrase(previousStyle: DraftingStyle? = nil, previousHeat: HeatLevel? = nil) {
        // If an overwrite confirmation is already showing, ignore repeat taps.
        // Without this guard, stacked taps would overwrite savedStyle/savedHeat
        // with intermediate values, so cancelling the warning would restore the
        // wrong selection (see bias-selector edge case audit, item 7).
        if showOverwriteConfirmation { return }

        // Bias/heat taps with no text anywhere are a no-op today: the drawer
        // can be opened via the grabber before any clause has been imported,
        // so the user may tap a bias level that silently does nothing. Deselect
        // the heat and surface a short hint instead of leaving the UI in an
        // inconsistent state where a pill is highlighted but nothing happened.
        let hasAnyText = (originalText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            || !clauseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasAnyText {
            if selectedHeat != nil {
                isRestoringSelection = true
                selectedHeat = nil
                isRestoringSelection = false
            }
            errorMessage = "Add a clause first, then choose a bias level."
            errorKind = nil
            lastRetryAction = nil
            return
        }

        // If the current session was imported via Track Changes → Show as Redline,
        // a heat/style trigger would silently discard the markup and rephrase from
        // the original (pre-changes) text. Intercept and reuse the overwrite alert.
        if isTrackChangesRedlineMode {
            savedStyle = previousStyle
            savedHeat = previousHeat
            hasSavedHeat = true
            pendingRephraseAction = { [weak self] in
                self?.executeRephrase()
            }
            showOverwriteConfirmation = true
            return
        }

        // Defensive sync: if the user is on the Output tab, the clauseText
        // may have unsynced edits that were suppressed (e.g. during undo/redo)
        // or bypassed the onChange handler. Bring currentText in line.
        if activeTab == .current {
            currentText = clauseText
        }

        // Detect edits during Edit On the Go (checkForUserEdits misses these
        // because aiOutputText is nil, so hasManualEdits is never set).
        if isEditOnTheGo, let original = originalText {
            let edited = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if edited != original.trimmingCharacters(in: .whitespacesAndNewlines) {
                hasManualEdits = true
            }
        }

        // Defensive re-check: compare the current output to the AI baseline.
        // Covers cases where checkForUserEdits was suppressed (undo/redo) or
        // where the edit happened through a path that didn't call it.
        if let aiOutput = aiOutputText {
            let current = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            let ai = aiOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if current != ai {
                hasManualEdits = true
            }
        }

        // If the user has manual edits, ask for confirmation before overwriting.
        if hasManualEdits {
            // Save the PREVIOUS values so cancel can truly revert the selection.
            savedStyle = previousStyle
            savedHeat = previousHeat
            hasSavedHeat = true
            pendingRephraseAction = { [weak self] in
                self?.executeRephrase()
            }
            showOverwriteConfirmation = true
            return
        }
        executeRephrase()
    }

    /// Called after user confirms "Discard & Rephrase".
    func confirmOverwrite() {
        showOverwriteConfirmation = false
        hasManualEdits = false
        isTrackChangesRedlineMode = false
        clearAllUndoStacks()
        // If in Edit On the Go, exit the mode but keep originalText as-is
        // (the user chose to discard their edits, so rephrase from the
        // untouched original).
        if isEditOnTheGo {
            isEditOnTheGo = false
            aiOutputText = nil
            hasGeneratedOutput = false
            rephraseCache.removeAll()
        }
        pendingRephraseAction?()
        pendingRephraseAction = nil
        savedStyle = nil
        savedHeat = nil
        hasSavedHeat = false
    }

    /// Called after user confirms "My current draft" (button 1 in the
    /// overwrite-confirmation dialog). Rephrases using the current draft as
    /// the source while leaving `originalText` (and therefore the locked
    /// Original / Show Changes baseline) untouched. The current draft is
    /// replaced with the new variant. `hasManualEdits` is intentionally not
    /// reset — the current draft's edits are being honoured, not discarded.
    /// Cache invalidation happens inside `executeRephrase` when a
    /// `sourceOverride` is supplied.
    func confirmRephraseFromCurrentDraft() {
        showOverwriteConfirmation = false
        let draftSource = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draftSource.isEmpty else { return }
        // Unified undo: record the pre-rephrase state so the user can
        // walk back to "My current draft" wording before the AI variant
        // landed. Replaces the prior wipe.
        pushSnapshot()
        pendingRephraseAction = { [weak self] in
            self?.executeRephrase(sourceOverride: draftSource)
        }
        pendingRephraseAction?()
        pendingRephraseAction = nil
        savedStyle = nil
        savedHeat = nil
        hasSavedHeat = false
    }

    /// Called after user confirms "Use as New Original".
    /// Promotes the current Output to originalText, then rephrases from there.
    func confirmUseAsNewOriginal() {
        showOverwriteConfirmation = false
        let editedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !editedText.isEmpty else { return }
        aiOutputText = nil
        hasManualEdits = false
        isEditOnTheGo = false        // exit Edit On the Go before rephrase
        isTrackChangesRedlineMode = false
        hasGeneratedOutput = false

        // Single chokepoint owns originalText assignment, cache wipes,
        // undo-stack hygiene, and the auto-Tell-Me hook. Runs BEFORE
        // `pendingRephraseAction?()` so the queued rephrase executes
        // against the freshly-rebaselined Original and the now-empty
        // `rephraseCache`.
        rebaselineOriginal(to: editedText)
        scheduleMemoryAutoSaveIfPossible()

        pendingRephraseAction?()
        pendingRephraseAction = nil
        savedStyle = nil
        savedHeat = nil
        hasSavedHeat = false
    }

    /// Whether savedHeat has been explicitly set (even to nil) for cancel restore.
    private var hasSavedHeat = false

    /// Called when user cancels -- restore previous style/heat selection.
    func cancelOverwrite() {
        showOverwriteConfirmation = false
        pendingRephraseAction = nil
        isRestoringSelection = true
        if let style = savedStyle {
            activeStyle = style
        }
        if hasSavedHeat {
            selectedHeat = savedHeat
        }
        savedStyle = nil
        savedHeat = nil
        hasSavedHeat = false
        isRestoringSelection = false
    }

    private func executeRephrase(sourceOverride: String? = nil) {
        guard let style = activeStyle else { return }

        // Remember which tab the user was on before we touch anything.
        let tabBeforeRephrase = activeTab

        // Source-override path: when the caller supplied an explicit source
        // (used by "My current draft" in the overwrite dialog), the cached
        // variants — which were generated from a different source — are
        // stale and must be discarded so the multi-variant API call below
        // re-populates the cache for the new source.
        if sourceOverride != nil {
            rephraseCache.removeAll()
        }

        // Cache-first: if a cached variant exists for the selected style+heat,
        // serve it without hitting the network. This lets the user browse the
        // five cached heat variants while offline or over budget. Under the
        // full-independence model the bias-tap flow no longer reads the AI
        // instruction, so the cache key is (style, heat) only.
        let heat = selectedHeat ?? .neutral
        let cacheKey = "\(style.rawValue)_\(heat.rawValue)"
        if let cached = rephraseCache[cacheKey] {
            if activeTab != .current {
                clauseText = currentText
                activeTab = .current
            }
            // Unified undo: record the pre-cache-hit state so the user
            // can walk back through bias toggles. Replaces the prior wipe.
            pushSnapshot()
            isSuppressingSnapshot = true
            aiOutputText = cached
            hasManualEdits = false
            clauseText = cached
            currentText = cached
            signalRephraseCompleted(showDiff: true, preserveTab: true)
            isSuppressingSnapshot = false
            if tabBeforeRephrase == .showChanges {
                switchTab(to: .showChanges)
            }
            return
        }

        // Check offline (only for uncached requests).
        if !NetworkMonitor.shared.isConnected {
            setError(.offline)
            return
        }

        // Check budget
        if isBudgetExhausted {
            setError(.budgetExhausted)
            return
        }

        if activeTab != .current {
            clauseText = currentText
            activeTab = .current
        }

        // Transition from Edit On the Go for a bias-pill rephrase.
        //
        // Rule C (Output text changes are agnostic to Tell Me / Revise
        // state): a bias-pill rephrase mid-EditOnTheGo no longer
        // silently promotes the user's edits to the locked Original.
        // The rephrase runs against the locked Original (per the
        // source-resolution block below); the user's pre-tap edits are
        // superseded by the AI variant. To commit those edits as the
        // new Original they use the explicit promotion paths
        // (Use Output as Original from the plus-sheet, or
        // "Make my draft the new Original" in the overwrite dialog).
        //
        // `rephraseCache.removeAll()` is also dropped: the cache key is
        // (style, heat) only and `originalText` no longer changes here,
        // so the cache stays correct.
        if isEditOnTheGo {
            guard !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            aiOutputText = nil
            isEditOnTheGo = false
            hasManualEdits = false
            hasGeneratedOutput = false
        }

        // Source resolution:
        //   1. If the caller supplied a sourceOverride, use it directly
        //      (the "My current draft" path — leaves originalText untouched).
        //   2. Otherwise rephrase from the locked Original when it exists.
        //   3. Otherwise (pre-lock state) bail out silently. Rule D
        //      (Original is mutated only at user-named promotion sites)
        //      removed the legacy soft-lock fallback that used to
        //      promote the clause as Original on first bias tap.
        //      `canTriggerRephrase` now requires `originalText != nil`,
        //      so the bias pills are visually disabled before reaching
        //      this block; the `return` here is defensive in case a
        //      programmatic caller bypasses the gate.
        let source: String
        if let override = sourceOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            source = override
        } else if let original = originalText {
            source = original
        } else {
            return
        }

        guard !source.isEmpty else { return }

        // Legacy path (kept for backward compatibility — the cache-first
        // block above handles the common case). Fall through to the API call
        // if no cached variant matched.
        if let cached = rephraseCache[cacheKey] {
            // Unified undo: record the pre-cache-hit state. Mirror of the
            // primary cache-hit block above.
            pushSnapshot()
            isSuppressingSnapshot = true
            aiOutputText = cached
            hasManualEdits = false
            clauseText = cached
            currentText = cached
            signalRephraseCompleted(showDiff: true, preserveTab: true)
            isSuppressingSnapshot = false
            // Restore to the tab the user was on (unless it was Original,
            // in which case Show Changes is more useful).
            if tabBeforeRephrase == .showChanges {
                switchTab(to: .showChanges)
            }
            return
        }

        // Need to call API — generate all 5 variants at once
        rephrasTask?.cancel()
        isLoading = true
        hasManualEdits = false
        clearError()
        let gen = nextRephraseGeneration()

        let sysPrompt = DraftingPrompts.buildMultiVariantSystemPrompt(
            style: style, language: selectedLanguage
        )
        // Full-independence model: the bias-tap flow does not read or
        // transmit the AI instruction field — see plan §2.0 / §5.3.
        let usrMsg = DraftingPrompts.buildMultiVariantUserMessage(
            clause: source
        )

        rephrasTask = Task {
            do {
                let result = try await self.service.rephraseAllVariants(
                    systemPrompt: sysPrompt,
                    userMessage: usrMsg
                )

                // Guard against stale completion. If the user has tapped a
                // different bias / style / typed new instructions while we
                // were in flight, this result no longer represents what the
                // user is looking at — drop it entirely and let the newer
                // task own the UI. This fixes the class of bug where a slow
                // response for bias N would land on top of a completed L1.
                guard self.isGenerationCurrent(gen) else { return }

                // Cache all 5 variants
                for (heatKey, text) in result.variants {
                    if let heatLevel = HeatLevel.fromShortLabel(heatKey) {
                        self.rephraseCache["\(style.rawValue)_\(heatLevel.rawValue)"] = text
                    }
                }

                // Unified undo: record the pre-rephrase state so undo
                // walks back to the wording the user had before this
                // bias / stage rephrase landed. Must run AFTER the cache
                // fill (so the cache for re-tap is ready) and BEFORE
                // the visible-text writes below.
                self.pushSnapshot()
                self.isSuppressingSnapshot = true
                let currentCacheKey = "\(style.rawValue)_\(heat.rawValue)"
                if let text = self.rephraseCache[currentCacheKey] {
                    self.aiOutputText = text
                    self.currentText = text
                    self.clauseText = text
                }

                self.isLoading = false
                self.signalRephraseCompleted(showDiff: true, preserveTab: false)
                self.isSuppressingSnapshot = false

                // Record usage (aggregate tokens for the multi-variant call)
                await self.recordUsage(DraftingService.RephraseResult(
                    text: "",
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens
                ))
            } catch is CancellationError {
                // Newer task took over; silently exit.
                return
            } catch let error as DraftingError where error == .userKeyInvalidFallbackAvailable {
                guard self.isGenerationCurrent(gen) else { return }
                self.isLoading = false
                self.pendingSystemPrompt = sysPrompt
                self.pendingUserMessage = usrMsg
                self.pendingFlowKind = .multiVariant
                self.showFallbackAlert = true
            } catch {
                guard self.isGenerationCurrent(gen) else { return }
                self.isLoading = false
                if let de = error as? DraftingError {
                    self.setError(de, retry: { [weak self] in
                        self?.executeRephrase()
                    })
                } else {
                    self.errorMessage = error.localizedDescription
                    self.errorKind = nil
                }
            }
        }
    }

    // MARK: - User Edit Detection

    /// Called when the user edits text on the Output tab.
    /// Compares against the AI output to detect manual changes.
    func checkForUserEdits() {
        guard activeTab == .current, let aiOutput = aiOutputText else { return }
        let edited = clauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let aiTrimmed = aiOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if edited != aiTrimmed {
            hasManualEdits = true
        }
    }

    // MARK: - Tab Switching

    func switchTab(to tab: ClauseTab) {
        guard originalText != nil else { return }

        // Unified back chain: tab switching does NOT wipe the chain.
        // Only flush an in-progress word-boundary edit so a partially
        // typed word lands as a snapshot before the user navigates
        // away from Output.
        if activeTab == .current {
            flushPendingOutputSnapshot()
            currentText = clauseText
        }

        activeTab = tab

        isSuppressingSnapshot = true
        switch tab {
        case .current:
            clauseText = currentText
            preEditClauseText = currentText
            lastSnapshotWordCount = wordCount(currentText)
        case .original:
            clauseText = originalText ?? ""
        case .showChanges:
            recomputeDiffTokens()
            recomputeExportTokens()
        }
        isSuppressingSnapshot = false
    }

    /// Legacy compatibility
    func toggleOriginal() {
        if activeTab == .original {
            switchTab(to: .current)
        } else {
            switchTab(to: .original)
        }
    }

    // MARK: - Diff & Revert

    /// Cached diff tokens, recomputed when switching to Show Changes tab.
    private(set) var diffTokens: [DiffToken] = []

    /// Cached simple two-way diff tokens used for all exports and the Simple view.
    /// Setter is internal (not private) so DraftingViewModel+DiffDisplay.swift can write it.
    var exportTokens: [DiffToken] = []

    /// Cache keys for exportTokens — skip recomputation when unchanged.
    var lastExportOriginal: String = ""
    var lastExportCurrent: String = ""

    /// True once the user has seen the Complex view warning for the current wipe cycle.
    /// Reset to false in resetAll() so the warning fires once per new session.
    var complexViewWarnedThisWipe: Bool = false

    /// Snapshot of the texts used for the last diff computation.
    /// When these haven't changed, recomputation is skipped so that
    /// in-memory reverts survive tab round-trips (Output ↔ Show Changes).
    private var lastDiffOriginal: String?
    private var lastDiffAiOutput: String?
    private var lastDiffCurrent: String?

    /// Forces the next `recomputeDiffTokens` call to actually recompute,
    /// even if the source texts haven't changed. Used after a fresh rephrase.
    var diffNeedsForceRecompute: Bool = false

    /// Recomputes the diff tokens and stores them.
    /// Uses three-layer diff when an AI output snapshot exists,
    /// falling back to two-layer diff otherwise.
    /// Skips recomputation when source texts haven't changed, preserving
    /// user reverts made in the Show Changes view.
    func recomputeDiffTokens() {
        guard let original = originalText else {
            diffTokens = []
            lastDiffOriginal = nil
            lastDiffAiOutput = nil
            lastDiffCurrent = nil
            return
        }

        let currentSnapshot = currentText

        // Skip if nothing changed — preserves in-memory revert state.
        if !diffNeedsForceRecompute,
           original == lastDiffOriginal,
           aiOutputText == lastDiffAiOutput,
           currentSnapshot == lastDiffCurrent,
           !diffTokens.isEmpty {
            return
        }

        diffNeedsForceRecompute = false
        lastDiffOriginal = original
        lastDiffAiOutput = aiOutputText
        lastDiffCurrent = currentSnapshot

        if let aiOutput = aiOutputText {
            diffTokens = WordDiff.threeLayerDiff(
                original: original,
                aiOutput: aiOutput,
                current: currentText
            )
        } else {
            diffTokens = WordDiff.diff(old: original, new: currentText)
        }
        objectWillChange.send()
    }

    /// Reverts an entire contiguous group of changes.
    /// Deletions: re-inserted (become equal) — except "AI-inserted-then-
    /// user-deleted" tokens, which revert to their AI-inserted state first
    /// (tap once to restore as AI insertion, tap again to remove entirely).
    /// Insertions: removed.
    /// Updates `currentText`, `diffTokens`, and marks the clause as manually edited.
    func revertDiffToken(_ token: DiffToken) {
        guard token.type != .equal else { return }
        guard let groupId = token.groupId else { return }

        // Unified undo: record the pre-revert state. Replaces the
        // former Changes-only snapshot — the back chain is now shared
        // across tabs.
        pushSnapshot()

        switch token.type {
        case .deleted:
            // Two-stage revert for aiThenUser: first tap restores as AI
            // insertion (blue underline), second tap (now an .inserted token)
            // removes it entirely via the .inserted branch below.
            if token.source == .aiThenUser {
                diffTokens = diffTokens.map { t in
                    if t.groupId == groupId && t.type == .deleted && t.source == .aiThenUser {
                        return DiffToken(text: t.text, type: .inserted, groupId: groupId, source: .ai)
                    }
                    return t
                }
            } else {
                diffTokens = diffTokens.map { t in
                    if t.groupId == groupId && t.type == .deleted {
                        return DiffToken(text: t.text, type: .equal)
                    }
                    return t
                }
            }
        case .inserted:
            diffTokens.removeAll { $0.groupId == groupId && $0.type == .inserted }
        case .equal:
            return
        }

        // Rebuild current text from the mutated token list.
        currentText = WordDiff.currentText(from: diffTokens)

        // Bake reverts into the AI output layer so that future recomputes
        // (e.g. after user edits on the Output tab) don't resurrect
        // already-reverted AI changes.
        if aiOutputText != nil {
            aiOutputText = WordDiff.effectiveAiOutput(from: diffTokens)
            lastDiffAiOutput = aiOutputText
        }

        // Sync snapshot so tab round-trips don't trigger a recompute.
        lastDiffCurrent = currentText
        hasManualEdits = true
        objectWillChange.send()
    }

    /// Reverts a Simple-mode (export) change. Tokens in `exportTokens` carry
    /// no AI/user attribution — they are a clean two-way Original→current diff
    /// — so the semantic is simply: undo this delta, treating the result as a
    /// manual edit. Insertions are removed; deletions become equal again.
    /// `currentText` is rebuilt from the mutated token list, and both token
    /// arrays are recomputed so a subsequent toggle to Complex view (or a tab
    /// round-trip) reflects the new baseline.
    func revertExportToken(_ token: DiffToken) {
        guard token.type != .equal else { return }
        guard let groupId = token.groupId else { return }

        pushSnapshot()

        switch token.type {
        case .deleted:
            exportTokens = exportTokens.map { t in
                if t.groupId == groupId && t.type == .deleted {
                    return DiffToken(text: t.text, type: .equal)
                }
                return t
            }
        case .inserted:
            exportTokens.removeAll { $0.groupId == groupId && $0.type == .inserted }
        case .equal:
            return
        }

        currentText = WordDiff.currentText(from: exportTokens)
        hasManualEdits = true

        // Invalidate caches so the next render rebuilds fresh tokens
        // (with merged groupIds where reverts made neighbours contiguous).
        lastExportCurrent = ""
        diffNeedsForceRecompute = true
        recomputeExportTokens()
        recomputeDiffTokens()
    }

    /// The text that should be exported / copied, depending on active tab.
    var exportableText: String {
        switch activeTab {
        case .current:
            return clauseText
        case .original:
            return originalText ?? ""
        case .showChanges:
            // Export the current (post-revert) text
            return currentText
        }
    }

    /// The output/current text regardless of active tab (for comprehensive PDF export).
    var exportableOutputText: String {
        currentText.isEmpty ? clauseText : currentText
    }

    // MARK: - Import Overwrite Handling

    /// "Yes" — full reset, then continue with the pending import.
    func confirmImportWithReset() {
        showImportOverwriteWarning = false
        resetAll()
        pendingImportAction?()
        pendingImportAction = nil
    }

    /// "No" — just replace originalText (keep settings), then continue import.
    func confirmImportReplaceOriginal() {
        showImportOverwriteWarning = false
        // Clear text state but keep style/heat/settings.
        aiOutputText = nil
        currentText = ""
        clauseText = ""
        hasManualEdits = false
        hasGeneratedOutput = false
        isEditOnTheGo = false
        // Drop edit-original mode if the import landed mid-edit so
        // the new pre-lock state is consistent.
        isEditingOriginal = false
        isTrackChangesRedlineMode = false
        diffTokens = []
        lastDiffOriginal = nil
        lastDiffAiOutput = nil
        lastDiffCurrent = nil
        activeTab = .current

        // The previously-loaded slot (if any) is no longer the source
        // of truth — a fresh import is about to overwrite the Original.
        loadedFromSlotKey = nil

        // Single chokepoint owns originalText = nil, cache wipes,
        // undo-stack hygiene, and the (no-op-when-nil) auto-Tell-Me
        // hook. The subsequent `pendingImportAction?()` will re-lock
        // via the import path, which itself routes through the helper.
        rebaselineOriginal(to: nil)

        pendingImportAction?()
        pendingImportAction = nil
    }

    /// "Cancel" — abort the import, do nothing.
    func cancelImport() {
        showImportOverwriteWarning = false
        pendingImportAction = nil
    }

    // MARK: - Reset

    func resetAll() {
        rephrasTask?.cancel()
        clauseText = ""
        currentText = ""
        aiOutputText = nil
        additionalInstruction = ""
        selectedLanguage = "en"
        // activeStyle is persisted in Settings — not reset on "New".
        // Re-read from UserDefaults in case it was changed.
        let raw = UserDefaults.standard.string(forKey: "dk_draftingStyle") ?? DraftingStyle.aplus.rawValue
        activeStyle = DraftingStyle(rawValue: raw) ?? .aplus
        activeTab = .current
        hasManualEdits = false
        hasGeneratedOutput = false
        diffTokens = []
        lastDiffOriginal = nil
        lastDiffAiOutput = nil
        lastDiffCurrent = nil
        diffNeedsForceRecompute = false
        isLoading = false
        clearError()
        // Discard any stashed BYOK retry context so a stale prompt doesn't
        // re-surface after a "New" reset.
        pendingSystemPrompt = nil
        pendingUserMessage = nil
        pendingFlowKind = .multiVariant
        pendingMaxTokens = 1500
        pendingAdditionalInstructionContext = nil
        instructionRejection = nil
        textAddedViaPhoto = false
        textWasReconstructed = false
        showPhotoCleanUpPrompt = false
        showReviewPrompt = false
        showOCRCleanupReviewSheet = false
        pendingReviewChoice = nil
        pendingCleanUp = nil
        pendingCleanUpMode = nil
        rawOCRText = ""
        isEditOnTheGo = false
        isEditingOriginal = false
        isDrawerExpanded = false
        preEditClauseText = ""
        lastSnapshotWordCount = 0
        // Track changes state
        trackChangesTask?.cancel()
        trackChangesTask = nil
        pendingTrackChangeImage = nil
        trackChangesResult = nil
        trackChangesError = nil
        showTrackChangesSheet = false
        isAnalyzingTrackChanges = false
        isTrackChangesRedlineMode = false
        // Plus button returns to "call-to-action" tint
        plusUsed = false

        // The "New" reset is a fresh start — break any lingering
        // pointer back into a Memory slot so the next slot tap does
        // not raise a stale unsaved-changes alert.
        loadedFromSlotKey = nil

        // Reset Complex view warning so it fires again on the next wipe cycle.
        complexViewWarnedThisWipe = false

        // Single chokepoint owns originalText = nil, clearAnalysisCache,
        // rephraseCache.removeAll, selectedHeat = nil, clearAllUndoStacks,
        // and the (no-op-when-nil) maybeAutoTriggerTellMe.
        rebaselineOriginal(to: nil)
    }

    // MARK: - System Key Fallback (user confirmed)

    func retryWithSystemKey() {
        // The .multiVariant and .analysis flows route through pendingSystemPrompt /
        // pendingUserMessage. The .aiInstruction flow re-builds those from
        // pendingAdditionalInstructionContext so the JSON envelope is parsed
        // by AdditionalInstructionPrompt.parseOutcome.
        let flowKind = pendingFlowKind
        let context = pendingAdditionalInstructionContext
        let stashedSysPrompt = pendingSystemPrompt
        let stashedUsrMsg = pendingUserMessage
        let maxTokens = pendingMaxTokens

        pendingSystemPrompt = nil
        pendingUserMessage = nil
        pendingFlowKind = .multiVariant
        pendingMaxTokens = 1500
        pendingAdditionalInstructionContext = nil

        // Guard against an empty stash for the prompt-based flows.
        switch flowKind {
        case .multiVariant, .analysis:
            guard stashedSysPrompt != nil, stashedUsrMsg != nil else { return }
        case .aiInstruction:
            guard context != nil else { return }
        }

        isLoading = true
        clearError()
        let gen = nextRephraseGeneration()

        rephrasTask = Task {
            do {
                switch flowKind {

                case .multiVariant:
                    guard let sysPrompt = stashedSysPrompt,
                          let usrMsg = stashedUsrMsg else { return }
                    let result = try await self.service.rephraseAllVariantsWithSystemKey(
                        systemPrompt: sysPrompt,
                        userMessage: usrMsg
                    )

                    guard self.isGenerationCurrent(gen) else { return }

                    // Cache all 5 variants
                    if let style = self.activeStyle {
                        for (heatKey, text) in result.variants {
                            if let heatLevel = HeatLevel.fromShortLabel(heatKey) {
                                self.rephraseCache["\(style.rawValue)_\(heatLevel.rawValue)"] = text
                            }
                        }

                        let heat = self.selectedHeat ?? .neutral
                        let cacheKey = "\(style.rawValue)_\(heat.rawValue)"
                        // Unified undo: BYOK retry mirror of the
                        // multi-variant primary path above.
                        self.pushSnapshot()
                        self.isSuppressingSnapshot = true
                        if let text = self.rephraseCache[cacheKey] {
                            self.aiOutputText = text
                            self.currentText = text
                            self.clauseText = text
                        }
                    }

                    self.isLoading = false
                    self.signalRephraseCompleted(showDiff: true)
                    self.isSuppressingSnapshot = false
                    await self.recordUsage(DraftingService.RephraseResult(
                        text: "",
                        inputTokens: result.inputTokens,
                        outputTokens: result.outputTokens
                    ))

                case .aiInstruction:
                    guard let ctx = context else {
                        self.isLoading = false
                        self.setError(.invalidResponse, retry: nil)
                        return
                    }
                    let result = try await self.service.rephraseAdditionalInstructionWithSystemKey(
                        style: ctx.style,
                        language: ctx.language,
                        sourceText: ctx.sourceText,
                        instruction: ctx.instruction
                    )

                    guard self.isGenerationCurrent(gen) else { return }

                    switch result.outcome {
                    case .ok(let text):
                        // Mirror of `executeInstructionRephrase` `.ok`
                        // branch — Rule C: do NOT promote `ctx.sourceText`
                        // to `originalText` on the BYOK retry. Caches stay
                        // valid against the unchanged baseline.
                        if ctx.wasEditOnTheGo {
                            self.isEditOnTheGo = false
                        }
                        // Unified undo: BYOK retry mirror of the
                        // executeInstructionRephrase `.ok` path above.
                        self.pushSnapshot()
                        self.isSuppressingSnapshot = true
                        self.aiOutputText = text
                        self.currentText = text
                        self.clauseText = text
                        self.isLoading = false
                        self.hasManualEdits = true
                        self.additionalInstruction = ""
                        self.signalRephraseCompleted(showDiff: true,
                                                     preserveTab: false)
                        self.isSuppressingSnapshot = false
                    case .rejected(let category, let reason):
                        self.isLoading = false
                        self.presentInstructionRejection(
                            category: category,
                            reason: reason
                        )
                    }

                    await self.recordUsage(DraftingService.RephraseResult(
                        text: "",
                        inputTokens: result.inputTokens,
                        outputTokens: result.outputTokens
                    ))

                case .analysis:
                    // Tell Me BYOK retry — writes to analysisResult, NOT to
                    // clauseText. Fixes the pre-existing latent bug where the
                    // legacy non-multi-variant branch routed the analysis
                    // response into the editor.
                    guard let sysPrompt = stashedSysPrompt,
                          let usrMsg = stashedUsrMsg else { return }
                    let result = try await self.service.sendRequestWithSystemKey(
                        systemPrompt: sysPrompt,
                        userMessage: usrMsg,
                        maxTokens: maxTokens
                    )

                    guard self.isGenerationCurrent(gen) else { return }

                    self.analysisResult = result.text
                    self.isAnalysing = false
                    self.analysisTask = nil
                    self.isLoading = false
                    await self.recordUsage(result)
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.isGenerationCurrent(gen) else { return }
                self.isLoading = false
                // Retrying the system-key fallback is not meaningful once the
                // pending prompt/message have been consumed — surface the
                // error without a retry closure and let the user reinvoke
                // the original rephrase path explicitly.
                if let de = error as? DraftingError {
                    self.setError(de, retry: nil)
                } else {
                    self.errorMessage = error.localizedDescription
                    self.errorKind = nil
                }
            }
        }
    }

    func cancelFallback() {
        pendingSystemPrompt = nil
        pendingUserMessage = nil
        pendingFlowKind = .multiVariant
        pendingMaxTokens = 1500
        pendingAdditionalInstructionContext = nil
        setError(.invalidAPIKey)
    }

    // MARK: - Computed (OCR, clipboard, recordUsage in ViewModel+Helpers.swift)

    var characterCount: Int { clauseText.count }

    var canTriggerRephrase: Bool {
        let hasSource = !clauseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // `!isEditingOriginal` disables every rephrase entry point (bias
        // pills, Additional-Instruction Send, Fixes-card apply path)
        // while the user is editing the locked Original. Without this
        // gate, a tap would silently drop the in-progress edits and
        // fire an API call against the still-uncommitted Original.
        //
        // `originalText != nil` enforces Rule D (Original is mutated
        // only at user-named promotion sites): bias-pill taps and Send
        // are inert pre-lock. The Lock pill is the user's explicit
        // promotion path. The legacy soft-lock fallback inside
        // `executeRephrase` was removed alongside this gate.
        //
        // `!isAnalysing && !isFixesInFlight` enforces Rule B (once in
        // flight, neither Tell Me nor Revise can be re-triggered): bias
        // pills and Send are inert while a Tell Me / Revise call is in
        // flight. Mirrors `canTriggerFixes` and the grabber's pulse
        // binding (`isAnyTellMeWorkInFlight`).
        return hasSource
            && !isLoading
            && !isBudgetExhausted
            && !isEditingOriginal
            && originalText != nil
            && !isAnalysing
            && !isFixesInFlight
    }

    /// Plus-sheet "Edit Original" card. Enabled whenever a baseline
    /// exists and the user is not already editing it or in the middle
    /// of a rephrase. Tell Me / Fixes / Track Changes in flight do NOT
    /// grey the card -- `startEditingOriginal()` cancels those tasks
    /// defensively as part of its cache-clear sequence.
    var canEditOriginalFromPlusSheet: Bool {
        originalText != nil
            && !isEditingOriginal
            && !isLoading
    }

    /// Plus-sheet "Use Output as Original" card. Enabled whenever a
    /// baseline exists, the editor is non-empty, and no rephrase is in
    /// flight. Does not check whether the Output differs from the
    /// Original -- by directive, "if there is something to promote,
    /// the user can promote it," even if the visible outcome is a
    /// one-tap no-op. Tell Me / Fixes / Track Changes in flight do
    /// NOT grey the card -- `useOutputAsOriginal()` cancels those
    /// tasks defensively.
    var canUseOutputAsOriginalFromPlusSheet: Bool {
        originalText != nil
            && !clauseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isEditingOriginal
            && !isLoading
    }

    var canCopy: Bool { !exportableText.isEmpty }
    var hasOriginal: Bool { originalText != nil }

    /// True if a specific heat level is available to select right now.
    /// Available when online, or when a cached variant exists for the
    /// current style+heat combination. Under the full-independence model
    /// the offline cache hit no longer depends on instruction equality.
    func isHeatAvailable(_ heat: HeatLevel) -> Bool {
        if NetworkMonitor.shared.isConnected && !isBudgetExhausted {
            return true
        }
        guard let style = activeStyle else { return false }
        let cacheKey = "\(style.rawValue)_\(heat.rawValue)"
        return rephraseCache[cacheKey] != nil
    }

    var canReset: Bool {
        hasOriginal || !clauseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True once at least one rephrase has completed and output is available.
    var hasGeneratedOutput: Bool = false {
        willSet { objectWillChange.send() }
    }

    // MARK: - Lock as Original

    /// Can the current text be locked as Original? Mirrors Compalight's rule:
    /// at least 3 words of non-whitespace content.
    var canLockAsOriginal: Bool {
        wordCount(clauseText.trimmingCharacters(in: .whitespacesAndNewlines)) >= 3
    }

    /// Locks the current editor text as the Original baseline, opens the
    /// three tabs (Original / Show Changes / Output), and wipes all pre-lock
    /// undo/redo stacks so the lock is a clean boundary.
    ///
    /// Called by the Lock pill shown during the pre-lock phase as soon as
    /// the editor contains text (gated by the ≥3-word `canLockAsOriginal`
    /// rule).
    func lockAsOriginal() {
        let text = clauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(text) >= 3 else { return }

        isSuppressingSnapshot = true
        currentText = text
        clauseText = text
        preEditClauseText = text
        lastSnapshotWordCount = wordCount(text)
        isEditOnTheGo = true
        hasGeneratedOutput = true
        activeTab = .current
        isDrawerExpanded = false
        isSuppressingSnapshot = false

        // Single chokepoint owns originalText assignment, cache wipes,
        // undo-stack hygiene, and the auto-Tell-Me hook.
        // (`clearAnalysisCache` is a no-op at first lock — caches are
        // already empty — but harmless and keeps the call site canonical.)
        rebaselineOriginal(to: text)
        scheduleMemoryAutoSaveIfPossible()
    }

    // MARK: - Edit Original (post-lock re-edit)

    /// Enters edit-original mode after the user confirms the
    /// "Edit Original?" popup (reached via long-press on the Original
    /// tab text). Cancels every in-flight AI call and clears every
    /// AI-derived cache so the user starts from a clean slate, but
    /// preserves the existing Output (`aiOutputText`, `currentText`,
    /// `hasGeneratedOutput`) so the user can return to it after
    /// re-locking via `commitEditingOriginal()`.
    func startEditingOriginal() {
        // Mutual-exclusion invariant with `isEditOnTheGo`.
        assert(!(isEditOnTheGo && isEditingOriginal),
               "EOTG and isEditingOriginal must never both be true")
        guard originalText != nil else { return }

        // Cancel anything in flight that the user has just invalidated.
        // `clearAnalysisCache()` cancels `analysisTask` and transitively
        // calls `clearFixesCache()` (which cancels `fixesTask`).
        rephrasTask?.cancel()
        trackChangesTask?.cancel()

        // Clear caches.
        clearAnalysisCache()
        rephraseCache.removeAll()
        selectedHeat = nil
        clearAllUndoStacks()

        // Defensive presentation-state clears so a stale sheet/alert
        // does not survive the cache wipe.
        showAnalysisSheet = false
        instructionRejection = nil
        fixesResultsAwaitingPresentation = false

        // Mode flips. Mutual-exclusion: clear `isEditOnTheGo` first.
        if isEditOnTheGo { isEditOnTheGo = false }
        isEditingOriginal = true

        // Make sure the user is on the Original tab and that
        // `clauseText` mirrors the baseline they are about to edit.
        if activeTab != .original {
            activeTab = .original
        }
        isSuppressingSnapshot = true
        clauseText = originalText ?? ""
        isSuppressingSnapshot = false

        objectWillChange.send()
    }

    /// Commits the edited Original. Re-locks via the same baseline-
    /// mutation semantics as `lockAsOriginal()` but preserves the
    /// existing Output rather than re-seeding it.
    ///
    /// `aiOutputText` is intentionally NOT nilled here. Per the user's
    /// explicit directive, the Output stays as the AI generated it; the
    /// post-commit Changes diff will appear "reversed" (an AI insertion
    /// in the edited segment may now read as an Original deletion, and
    /// vice versa). This is a deliberate, user-accepted trade-off, not
    /// a bug.
    func commitEditingOriginal() {
        let text = clauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Mirrors the LockPill enable rule (`canLockAsOriginal`) — the
        // pill's gating already prevents reaching this with < 3 words,
        // but defensive in case a future call site bypasses the pill.
        guard wordCount(text) >= 3 else { return }

        isSuppressingSnapshot = true
        isEditingOriginal = false
        // hasGeneratedOutput, aiOutputText, currentText are left
        // untouched by deliberate design — the existing Output must
        // survive the re-lock so the user lands back on it.
        diffNeedsForceRecompute = true
        activeTab = .current
        clauseText = currentText
        preEditClauseText = currentText
        lastSnapshotWordCount = wordCount(currentText)
        isSuppressingSnapshot = false

        // Single chokepoint owns originalText assignment, cache wipes,
        // undo-stack hygiene, and the auto-Tell-Me hook.
        // (Caches were already cleared in `startEditingOriginal()`;
        // re-clearing inside the helper is harmless.)
        rebaselineOriginal(to: text)
        scheduleMemoryAutoSaveIfPossible()
    }

    // MARK: - Use Output as Original (post-lock baseline replacement)

    /// Promotes the current Output text to the new locked Original.
    /// Treats the promotion as a fresh import of `currentText`:
    /// post-state mirrors `lockAsOriginal()` (`aiOutputText = nil`,
    /// `hasGeneratedOutput = true`, `isEditOnTheGo = true`), so Show
    /// Changes is a clean baseline and the editor stays editable.
    /// Cancels any in-flight AI work (analysis, fixes, rephrase,
    /// track-changes) and clears every AI-derived cache.
    ///
    /// Distinct from `confirmUseAsNewOriginal()`: this method does NOT
    /// run a queued rephrase -- the user is committing, not redrafting.
    /// Called from the plus-sheet "Use Output as Original" card after
    /// the user confirms the popup.
    func useOutputAsOriginal() {
        guard canUseOutputAsOriginalFromPlusSheet else { return }
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Cancel anything in flight that the new baseline invalidates.
        // `rebaselineOriginal` cancels analysisTask + fixesTask via
        // `clearAnalysisCache`; rephrasTask + trackChangesTask are
        // cancelled here because the helper does not own them.
        rephrasTask?.cancel()
        trackChangesTask?.cancel()

        // Defensive presentation-state clears (mirror startEditingOriginal).
        showAnalysisSheet = false
        instructionRejection = nil
        fixesResultsAwaitingPresentation = false

        // Promote: mirror lockAsOriginal()'s post-state. Treat as a
        // fresh import -- `aiOutputText` is nil'ed, `hasGeneratedOutput
        // = true`, `isEditOnTheGo = true` so the user can keep editing
        // immediately and Show Changes renders a clean baseline.
        isSuppressingSnapshot = true
        aiOutputText = nil
        currentText = text
        clauseText = text
        preEditClauseText = text
        lastSnapshotWordCount = wordCount(text)
        isEditOnTheGo = true
        hasGeneratedOutput = true
        hasManualEdits = false
        activeTab = .current
        isSuppressingSnapshot = false

        // Single chokepoint owns originalText assignment, cache wipes,
        // undo-stack hygiene, and the auto-Tell-Me hook.
        rebaselineOriginal(to: text)
        scheduleMemoryAutoSaveIfPossible()
    }

    /// If the user has enabled "Run Tell Me automatically on lock" in
    /// Settings (`dk_autoTellMeOnLock`), kick off `analyseOriginal()` in
    /// the background after a fresh lock. Best-effort and single-shot:
    /// silently skips if any of the existing Tell Me preconditions are
    /// not met (offline, budget exhausted, clause under 20 words, or
    /// SIMPLE style). Does NOT open the analysis sheet — the user opens
    /// it on demand via the Tell Me pill, which already communicates
    /// the in-flight ("Analysing…") and ready ("Analysis ready") states.
    private func maybeAutoTriggerTellMe() {
        guard UserDefaults.standard.bool(forKey: "dk_autoTellMeOnLock") else { return }
        guard activeStyle != .plain else { return }
        guard let original = originalText, wordCount(original) >= 20 else { return }
        guard NetworkMonitor.shared.isConnected else { return }
        guard !isBudgetExhausted else { return }
        guard analysisTask == nil else { return }
        // Sheet stays closed — background mode.
        analyseOriginal()
    }

    /// Cleans up photo-imported text. Kicks off the AI clean-up in the background
    /// and immediately surfaces the review prompt so the user can decide whether
    /// the result should be committed in place or shown as a raw-vs-cleaned redline.
    /// Called when the user taps "Yes" on the post-import clean-up prompt.
    func performPhotoCleanUp() {
        startCleanUp(mode: .inPlace)
    }

    /// Unified clean-up launcher shared by the post-import path (in-place commit)
    /// and the Edit On the Go path (redline commit).
    private func startCleanUp(mode: CleanUpMode) {
        let rawText = clauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return }

        if !NetworkMonitor.shared.isConnected {
            setError(.offline)
            return
        }
        if isBudgetExhausted {
            setError(.budgetExhausted)
            return
        }

        rephrasTask?.cancel()
        isLoading = true
        clearError()
        let gen = nextRephraseGeneration()

        // Capture the raw OCR baseline before the API call. Preserved for the
        // redline engine if the user opts into review.
        rawOCRText = rawText
        pendingCleanUpMode = mode
        pendingReviewChoice = nil
        pendingCleanUp = nil
        // Present the review prompt on the next run loop to avoid an iOS
        // alert-presentation race when the first clean-up prompt is still
        // dismissing on the same view.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard self.pendingCleanUpMode != nil,
                  self.pendingReviewChoice == nil else { return }
            self.showReviewPrompt = true
        }

        let sysPrompt = DraftingPrompts.ocrCleanUpSystemPrompt
        let usrMsg = DraftingPrompts.buildOCRCleanUpUserMessage(rawText: rawText)

        rephrasTask = Task {
            do {
                let result = try await self.service.rephraseRaw(
                    systemPrompt: sysPrompt,
                    userMessage: usrMsg
                )

                guard self.isGenerationCurrent(gen) else { return }

                let cleaned = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.pendingCleanUp = PendingCleanUp(
                    apiResult: result,
                    cleaned: cleaned,
                    rawText: rawText,
                    generation: gen
                )
                self.commitCleanUpIfReady()
            } catch is CancellationError {
                return
            } catch {
                guard self.isGenerationCurrent(gen) else { return }
                self.isLoading = false
                // API failed — nothing to review. Dismiss any open prompts/sheets.
                self.showReviewPrompt = false
                self.showOCRCleanupReviewSheet = false
                self.pendingReviewChoice = nil
                self.pendingCleanUp = nil
                self.pendingCleanUpMode = nil
                if let de = error as? DraftingError {
                    self.setError(de, retry: { [weak self] in
                        self?.performPhotoCleanUp()
                    })
                } else {
                    self.errorMessage = error.localizedDescription
                    self.errorKind = nil
                }
            }
        }
    }

    /// User tapped "Yes" on the review prompt — opens the OCR cleanup review sheet.
    func acceptReview() {
        showReviewPrompt = false
        showOCRCleanupReviewSheet = true
        // pendingReviewChoice deliberately not set — sheet handles commit.
    }

    /// User tapped "No" on the review prompt — commit the cleaned text directly.
    func declineReview() {
        pendingReviewChoice = .skip
        showReviewPrompt = false
        commitCleanUpIfReady()
    }

    /// Called when the user taps "Accept" in the OCR cleanup review sheet.
    /// Lands the cleaned text in the editor as a pre-lock draft — same shape
    /// as the paste / typing import paths. The user reviews / edits and then
    /// taps the Lock pill to commit it as Original. We deliberately do NOT
    /// set `originalText`, `hasGeneratedOutput`, `isEditOnTheGo`, or clear
    /// `aiOutputText` here; `lockAsOriginal()` owns that transition.
    ///
    /// `userChoseEmpty` — pass `true` only when the empty `finalText` is the
    /// result of the user actively emptying the cleaned text in the review
    /// sheet (e.g., marking every word for deletion). When `false` (the
    /// default), an empty `finalText` falls back to the raw OCR text — the
    /// defensive path for "AI returned empty cleaning" or no review action.
    func commitOCRCleanupFromSheet(finalText: String, userChoseEmpty: Bool = false) {
        guard let pending = pendingCleanUp,
              pendingCleanUpMode != nil else {
            showOCRCleanupReviewSheet = false
            return
        }
        guard isGenerationCurrent(pending.generation) else {
            pendingCleanUp = nil
            pendingCleanUpMode = nil
            showOCRCleanupReviewSheet = false
            return
        }

        let rawText = pending.rawText
        // Honour an empty result only when it is a deliberate user choice;
        // otherwise fall back to raw OCR (defensive — covers AI-returned-empty
        // and the "no interaction" edge case).
        let cleaned: String
        if finalText.isEmpty && !userChoseEmpty {
            cleaned = rawText
        } else {
            cleaned = finalText
        }
        let apiResult = pending.apiResult

        // Consume pending state up front so re-entry is safe.
        pendingCleanUp = nil
        pendingCleanUpMode = nil
        showOCRCleanupReviewSheet = false

        isSuppressingSnapshot = true
        // Pre-lock draft state: the cleaned text lands in the editor only.
        // Lock is the user's call via the Lock pill.
        currentText = cleaned
        clauseText = cleaned
        preEditClauseText = cleaned
        lastSnapshotWordCount = wordCount(cleaned)
        // Current is the only meaningful tab pre-lock (no Original, no diff).
        activeTab = .current
        isSuppressingSnapshot = false
        clearAllUndoStacks()
        isLoading = false
        objectWillChange.send()

        Task { await recordUsage(apiResult) }
    }

    /// Called when the user taps "Discard" in the OCR cleanup review sheet.
    /// Keeps the raw OCR text in the editor; no tab activation.
    func discardOCRCleanupFromSheet() {
        rephrasTask?.cancel()
        pendingCleanUp = nil
        pendingCleanUpMode = nil
        showOCRCleanupReviewSheet = false
        isLoading = false
        textAddedViaPhoto = false
    }

    /// Commits the clean-up result once both the API response and the review choice
    /// are available. Only the .skip path remains; .review is now handled by the
    /// OCR cleanup review sheet (commitOCRCleanupFromSheet).
    /// Called from the API completion handler and declineReview(); does nothing
    /// until both inputs are present.
    private func commitCleanUpIfReady() {
        guard let pending = pendingCleanUp,
              let choice = pendingReviewChoice,
              let mode = pendingCleanUpMode else { return }
        guard isGenerationCurrent(pending.generation) else {
            pendingCleanUp = nil
            pendingReviewChoice = nil
            pendingCleanUpMode = nil
            return
        }

        let cleaned = pending.cleaned

        // Consume pending state up front so re-entry is safe.
        pendingCleanUp = nil
        pendingReviewChoice = nil
        pendingCleanUpMode = nil

        switch (mode, choice) {
        case (.inPlace, .skip):
            // Replace the editor text with the cleaned output, no tab activation.
            if !cleaned.isEmpty {
                isSuppressingSnapshot = true
                clauseText = cleaned
                isSuppressingSnapshot = false
            }
            isLoading = false
            textAddedViaPhoto = false

        default:
            // .review cases are no longer reachable; acceptReview() opens the
            // sheet instead of setting pendingReviewChoice. Guard here for safety.
            break
        }

        Task { [result = pending.apiResult] in
            await self.recordUsage(result)
        }
    }

    // MARK: - Helpers

    private func signalRephraseCompleted(showDiff: Bool = false, preserveTab: Bool = false) {
        hasGeneratedOutput = true
        diffNeedsForceRecompute = true
        recomputeDiffTokens()
        recomputeExportTokens()
        // Jump to Show Changes only when explicitly requested AND we are
        // not preserving the user's current tab (e.g. heat-level toggle).
        if showDiff && originalText != nil && !preserveTab {
            activeTab = .showChanges
        }
        // Initialize Output snapshot tracking for when the user switches to Output.
        preEditClauseText = clauseText
        lastSnapshotWordCount = wordCount(clauseText)
        rephraseJustCompleted = true
        // Auto-save tick: a fresh AI response just landed, so the
        // bias-pill cache and Output state are now part of what the
        // Auto slot should persist. Debounced 2s by `MemoryStore`.
        scheduleMemoryAutoSaveIfPossible()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            rephraseJustCompleted = false
        }
    }

    // MARK: - Memory: snapshot, restore, auto-save

    /// Build a `MemorySnapshot` from the current view-model state.
    /// Only the fields enumerated in the Local Persistence Plan §1.1
    /// are read; transient UI flags, in-flight markers, undo stacks,
    /// and sheet-presentation booleans are deliberately excluded.
    func memorySnapshot() -> MemorySnapshot {
        let rephraseJSON = (try? JSONEncoder().encode(rephraseCache)) ?? Data()
        let fixesPairs: [FixesCachePair] = fixesCache.map { (key, value) in
            FixesCachePair(key: key, value: value)
        }
        let fixesJSON = (try? JSONEncoder().encode(fixesPairs)) ?? Data()
        let appliedJSON = (try? JSONEncoder().encode(fixesAppliedFlags)) ?? Data()
        let activeTabRaw: String = {
            switch activeTab {
            case .current: return "current"
            case .showChanges: return "showChanges"
            case .original: return "original"
            }
        }()
        return MemorySnapshot(
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
            activeStyleRaw: activeStyle?.rawValue,
            selectedHeatRaw: selectedHeat?.rawValue,
            selectedLanguage: selectedLanguage,
            analysisResult: analysisResult,
            analysisStyleKey: analysisStyleKey,
            analysisOriginalText: analysisOriginalText,
            rephraseCacheJSON: rephraseJSON,
            fixesCacheJSON: fixesJSON,
            fixesAppliedFlagsJSON: appliedJSON
        )
    }

    /// Restore the live view-model from a saved `MemoryEntry`. Strict
    /// ordering: cancel in-flight tasks → wipe live caches → restore
    /// mode flags → route Original through `rebaselineOriginal(to:,
    /// suppressAutoTellMe: true)` → restore other texts → restore
    /// caches → force diff recompute → set `loadedFromSlotKey`.
    /// `isEditingOriginal` is forced to `false` (mid-edit-Original
    /// is not a stable resting point).
    func restore(from entry: MemoryEntry) {
        // 1. Cancel anything in flight.
        rephrasTask?.cancel()
        trackChangesTask?.cancel()

        // 2. Wipe the live caches BEFORE we restore the persisted ones.
        //    `clearAnalysisCache` transitively clears Fixes; calling
        //    `rebaselineOriginal` below repeats this — harmless.
        clearAnalysisCache()
        rephraseCache.removeAll()
        selectedHeat = nil
        clearAllUndoStacks()

        // 3. Restore mode flags.
        isSuppressingSnapshot = true
        if let raw = entry.activeStyleRaw, let style = DraftingStyle(rawValue: raw) {
            activeStyle = style
        } else {
            activeStyle = .aplus
        }
        // `selectedHeat` is intentionally restored AFTER `rebaselineOriginal`
        // in step 4b, because the chokepoint helper sets `selectedHeat = nil`
        // and would clobber any value written here.
        selectedLanguage = entry.selectedLanguage
        additionalInstruction = entry.additionalInstruction
        hasGeneratedOutput = entry.hasGeneratedOutput
        hasManualEdits = entry.hasManualEdits
        isEditOnTheGo = entry.isEditOnTheGo
        isTrackChangesRedlineMode = entry.isTrackChangesRedlineMode
        switch entry.activeTabRaw {
        case "current":     activeTab = .current
        case "showChanges": activeTab = .showChanges
        case "original":    activeTab = .original
        default:            activeTab = .current
        }
        isEditingOriginal = false   // never restore mid-edit

        // 4. Restore the texts. Route originalText through the
        //    chokepoint with `suppressAutoTellMe: true` so the
        //    persisted Tell Me cache survives the rebaseline call.
        //    NOTE: `rebaselineOriginal` also wipes `selectedHeat` —
        //    that field is restored in step 4b below.
        rebaselineOriginal(to: entry.originalText, suppressAutoTellMe: true)
        aiOutputText = entry.aiOutputText
        currentText = entry.currentText
        clauseText = entry.clauseText
        preEditClauseText = entry.clauseText
        lastSnapshotWordCount = wordCount(entry.clauseText)

        // 4b. Restore `selectedHeat` after `rebaselineOriginal` cleared it.
        //     `isRestoringSelection = true` blocks the SwiftUI onChange
        //     handler in `DraftingView` from interpreting this programmatic
        //     assignment as a user tap and firing a rephrase.
        if let raw = entry.selectedHeatRaw, let heat = HeatLevel(rawValue: raw) {
            isRestoringSelection = true
            selectedHeat = heat
            isRestoringSelection = false
        } else {
            selectedHeat = nil
        }

        // 5. Restore the caches (after rebaselineOriginal cleared them).
        if let json = entry.rephraseCacheJSON,
           let restored = try? JSONDecoder().decode([String: String].self, from: json) {
            rephraseCache = restored
        }
        analysisResult = entry.analysisResult
        analysisStyleKey = entry.analysisStyleKey
        analysisOriginalText = entry.analysisOriginalText
        if let json = entry.fixesCacheJSON,
           let restoredPairs = try? JSONDecoder().decode([FixesCachePair].self, from: json) {
            var rebuilt: [FixesCacheKey: FixesGroups] = [:]
            for pair in restoredPairs {
                rebuilt[pair.key] = pair.value
            }
            fixesCache = rebuilt
        }
        if let json = entry.fixesAppliedFlagsJSON,
           let restored = try? JSONDecoder().decode([String: Bool].self, from: json) {
            fixesAppliedFlags = restored
        }

        // 6. Force diff recompute. We do this eagerly (rather than
        //    deferring to the next `switchTab` call) because a snapshot
        //    saved on the Show Changes tab restores `activeTab =
        //    .showChanges` directly, bypassing `switchTab` — and the
        //    Changes pane reads `diffTokens` synchronously, so without
        //    this call it would render empty until the user navigated
        //    away and back. The recompute is cheap when source texts
        //    haven't changed (early-return inside the func) and runs
        //    unconditionally so any landing tab is correct.
        diffNeedsForceRecompute = true
        diffTokens = []
        lastDiffOriginal = nil
        lastDiffAiOutput = nil
        lastDiffCurrent = nil
        recomputeDiffTokens()
        recomputeExportTokens()

        isSuppressingSnapshot = false

        // 7. Track which slot is now loaded.
        loadedFromSlotKey = entry.slotKey

        objectWillChange.send()
    }

    /// Auto-save shim. Called from the `clauseText` `didSet` and from
    /// the major lifecycle milestones (lock, edit-original commit,
    /// use-output-as-original, confirm-use-as-new-original, rephrase
    /// completion). The underlying `MemoryStore` debounces these
    /// calls to a single 2s trailing write into the Auto slot, and
    /// no-ops when the user has not opted into auto-save.
    ///
    /// `isSuppressingSnapshot`: programmatic state changes (e.g. the
    /// multi-step `restore(from:)` flow, `lockAsOriginal()`'s setup
    /// block, `useOutputAsOriginal()`'s setup block) wrap themselves
    /// in this flag so individual property `didSet` ticks don't fire
    /// auto-save with mid-flight, partially-restored state. Without
    /// this guard, restoring a slot can persist a half-restored
    /// snapshot to the Auto slot, silently degrading it.
    func scheduleMemoryAutoSaveIfPossible() {
        guard !isSuppressingSnapshot else { return }
        // The Memory store is a `@MainActor` singleton; this method
        // is also `@MainActor` (the whole view-model is). Call site
        // is one Combine-free shim so future changes do not touch
        // every milestone individually.
        MemoryStore.shared.scheduleAutoSave(snapshot: memorySnapshot())
    }
}

// MARK: - Codable wrapper for the FixesCache

/// JSONEncoder serialises `[FixesCacheKey: FixesGroups]` as a flat
/// alternating array (the default for struct-keyed dictionaries),
/// which is hard to round-trip safely. We persist a plain
/// `[FixesCachePair]` instead, then rebuild the dictionary on restore.
private struct FixesCachePair: Codable {
    let key: FixesCacheKey
    let value: FixesGroups
}
