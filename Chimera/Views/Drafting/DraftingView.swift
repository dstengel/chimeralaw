// DraftingView.swift
// Chimera Law
// Main drafting screen -- clause rephrasing with style and heat control

import SwiftUI
import Combine
import AVFoundation
import Speech

struct DraftingView: View {

    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = DraftingViewModel()
    @StateObject private var speechService = SpeechRecognitionService()
    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    @State private var showInfoSheet = false
    @State private var showSettings = false
    @State private var showAttachSheet = false
    @State private var showTrackChangesPicker = false
    /// Drives the "Edit Original?" confirmation alert presented after the
    /// user taps "Edit Original…" in the Original-tab long-press context
    /// menu, or the plus-sheet "Edit Original" card. Local view state —
    /// the alert is a thin gate in front of `viewModel.startEditingOriginal()`.
    @State private var showEditOriginalConfirmation = false
    /// Drives the "Use Output as Original?" confirmation alert presented
    /// after the user taps the plus-sheet "Use Output as Original" card.
    /// Local view state — the alert is a thin gate in front of
    /// `viewModel.useOutputAsOriginal()`.
    @State private var showUseOutputAsOriginalConfirmation = false
    @State private var clauseOpacity: Double = 1.0
    @State private var exportShareItem: ExportShareItem?
    /// Generalised toast message. Was a Bool driving a hard-coded
    /// "Copied" string; now carries any short transient message so the
    /// same overlay can be reused for "Saved to Memory N", the
    /// migration-fail notice, etc. Cleared via a cancellable
    /// DispatchWorkItem (see `presentToast(_:)`).
    @State private var toastMessage: String?
    @State private var toastDismissTask: DispatchWorkItem?
    @State private var tabBarPulse = false
    /// Drives presentation of the "Save to memory" sheet (`MemorySaveSheet`).
    /// Toggled by the toolbar Save button between New and Export.
    @State private var showMemorySaveSheet: Bool = false
    /// Snapshot captured when the Save button is tapped. Held here so
    /// the sheet writes the state at the moment of tap, not the state
    /// after the user has read the row previews.
    @State private var pendingMemorySnapshot: MemorySnapshot?
    /// Drives the unsaved-changes confirmation alert when the user
    /// taps a slot in the plus-sheet load row over a dirty editor.
    @State private var pendingMemoryRestoreSlot: String?
    @ObservedObject private var memoryStore = MemoryStore.shared
    @State private var showMicSettingsAlert = false
    @State private var showMicRestrictedAlert = false
    @FocusState private var isClauseFocused: Bool
    /// Focus state on the bottom Additional Instructions field. Used
    /// alongside `isClauseFocused` by the Revise hybrid open rule to
    /// decide between auto-opening the sheet and showing the
    /// "Revise — ready" banner.
    @FocusState private var isInstructionFocused: Bool
    @AppStorage("dk_draftingStyle") private var storedStyleRaw: String = DraftingStyle.aplus.rawValue
    @AppStorage("dk_useComplexDiffView") private var useComplexDiffView: Bool = false
    @State private var showComplexViewWarning: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    /// True iff there is content worth saving to a manual Memory slot.
    /// Mirrors the auto-save gate: an Original is locked or non-
    /// whitespace clauseText exists. Drives the toolbar Save button's
    /// enabled state.
    private var canSaveToMemory: Bool {
        if viewModel.hasOriginal { return true }
        let trimmed = viewModel.clauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    /// Border tint for the Additional-Instruction field. Always-on ambient
    /// signal — turns amber as the user approaches the 500-character cap
    /// and red once over. The cap itself is enforced by disabling Send,
    /// not by truncating the field's text.
    private var instructionBorderTint: Color {
        let count = viewModel.additionalInstruction.count
        let limit = AdditionalInstructionPrompt.characterLimit
        if count > limit       { return .dkError }
        if count >= limit - 50 { return .dkWarning }
        return Color(.systemGray4)
    }

    /// Background tint for the Additional-Instruction field. Layers on top
    /// of the existing `dkSurface` fill so the field's interior shifts
    /// colour at the same thresholds as `instructionBorderTint`. Pure
    /// ambient signal — there is no character counter; the combined
    /// border + background change tells the user how close they are to
    /// the 500-character cap.
    /// - count ≤ 449: clear (no change to existing surface).
    /// - count 450–500: faint amber wash (approaching the limit).
    /// - count > 500: stronger red wash (over the limit; Send disabled).
    private var instructionFieldBackground: Color {
        let count = viewModel.additionalInstruction.count
        let limit = AdditionalInstructionPrompt.characterLimit
        if count > limit       { return Color.dkError.opacity(0.10) }
        if count >= limit - 50 { return Color.dkWarning.opacity(0.06) }
        return Color.clear
    }

    var body: some View {
        NavigationStack {
            mainContent
                .onChange(of: viewModel.hasOriginal) { old, new in
                    if !old && new {
                        withAnimation(.easeInOut(duration: 0.25)) { tabBarPulse = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.25)) { tabBarPulse = false }
                        }
                    }
                }
                // Fixes hybrid open rule (§3.6). When results arrive,
                // the view-model flips this flag. We then read our own
                // focus state and route to either the sheet or the
                // banner. Cleared immediately so the next Fixes call
                // starts from a clean slate.
                .onChange(of: viewModel.fixesResultsAwaitingPresentation) { _, awaiting in
                    guard awaiting else { return }
                    viewModel.fixesResultsAwaitingPresentation = false
                    let anyFieldFocused = isClauseFocused || isInstructionFocused
                    if anyFieldFocused {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showFixesReadyBanner = true
                        }
                    } else {
                        viewModel.showFixesSheet = true
                    }
                }
                .applyChangeHandlers(
                    viewModel: viewModel,
                    appState: appState,
                    storedStyleRaw: $storedStyleRaw,
                    clauseOpacity: $clauseOpacity,
                    showCameraPicker: $showCameraPicker,
                    showImagePicker: $showImagePicker,
                    showTrackChangesPicker: $showTrackChangesPicker,
                    guardImport: guardImport
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .applySheetModifiers(
                    viewModel: viewModel,
                    appState: appState,
                    showImagePicker: $showImagePicker,
                    showCameraPicker: $showCameraPicker,
                    showInfoSheet: $showInfoSheet,
                    showSettings: $showSettings,
                    exportShareItem: $exportShareItem,
                    showAttachSheet: $showAttachSheet,
                    showTrackChangesPicker: $showTrackChangesPicker,
                    showAnalysisSheet: Binding(
                        get: { viewModel.showAnalysisSheet },
                        set: { viewModel.showAnalysisSheet = $0 }
                    ),
                    showEditOriginalConfirmation: $showEditOriginalConfirmation,
                    showUseOutputAsOriginalConfirmation: $showUseOutputAsOriginalConfirmation,
                    onLoadMemory: { slotKey in
                        handleMemoryLoadTap(slotKey: slotKey)
                    },
                    guardImport: guardImport
                )
                .applyAlertModifiers(
                    viewModel: viewModel,
                    showEditOriginalConfirmation: $showEditOriginalConfirmation,
                    showUseOutputAsOriginalConfirmation: $showUseOutputAsOriginalConfirmation
                )
                .onChange(of: useComplexDiffView) { _, isComplex in
                    if isComplex && !viewModel.complexViewWarnedThisWipe {
                        viewModel.complexViewWarnedThisWipe = true
                        showComplexViewWarning = true
                    }
                }
                .alert("Complex Changes View", isPresented: $showComplexViewWarning) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Complex view shows changes colour-coded by source: AI edits, your edits, and overlapping changes appear in separate colours. Your recipient never sees this. Word and PDF exports always show a clean redline — blue for additions, red for deletions — regardless of this setting.")
                }
        }
    }

    // MARK: - Main Content VStack

    private var mainContent: some View {
        VStack(spacing: 0) {

            // MARK: - Connectivity Warning
            ConnectivityBanner(serviceWarning: appState.serviceWarning)
                .padding(.horizontal, DKLayout.screenPadding)
                .padding(.top, 6)
                .animation(.easeInOut(duration: 0.3), value: NetworkMonitor.shared.isConnected)
                .animation(.easeInOut(duration: 0.3), value: appState.serviceWarning)

            // MARK: - Rephrase / Clean-up Error Banner
            // Shares location + appearance with ConnectivityBanner so all
            // user-facing failures surface in the same place. Suppressed
            // while the top ConnectivityBanner is already displaying the
            // offline state, to avoid duplicating the warning.
            if let error = viewModel.errorMessage,
               !(error == DraftingError.offline.errorDescription && !network.isConnected) {
                DraftingErrorBanner(
                    message: error,
                    canRetry: viewModel.canRetryLastAction,
                    onRetry: { viewModel.retryLastRephrase() }
                )
                .padding(.horizontal, DKLayout.screenPadding)
                .padding(.top, 6)
                .animation(.easeInOut(duration: 0.25), value: viewModel.errorMessage)
                .animation(.easeInOut(duration: 0.25), value: viewModel.canRetryLastAction)
            }

            // MARK: - Clause Card (heat + tabs + editor)

            clauseEditorWithTabs
                .padding(.horizontal, DKLayout.screenPadding)
                .padding(.top, 10)

            // Reconstruction warning
            if viewModel.textWasReconstructed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.dkWarning)
                        .font(.system(size: 13))
                    Text("Text was reconstructed from incomplete fragments. Additions are shown in [brackets].")
                        .font(.dkCaption)
                        .foregroundColor(.dkWarning)
                }
                .padding(.horizontal, DKLayout.screenPadding)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)

            // MARK: - Bottom Input Section (Claude-style)
            // When no original is locked: always visible (controls disabled).
            // This avoids the layout jump that occurs when the section
            // animates away at the same time as the keyboard appears.
            // When original IS locked: hidden when the clause editor is
            // focused to give more vertical space for output editing.

            // Fixes ready banner. Shown whenever the view-model has set
            // showFixesReadyBanner (results landed while a text field
            // was focused). Rendered outside the keyboard-hiding
            // bottomInputSection conditional so it remains visible
            // above the keyboard while the user finishes their thought.
            if viewModel.showFixesReadyBanner {
                FixesReadyBanner(viewModel: viewModel)
                    .padding(.horizontal, DKLayout.screenPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
            }

            if !isClauseFocused || !viewModel.hasOriginal {
                Divider()
                    .padding(.horizontal, DKLayout.screenPadding)

                bottomInputSection
                    .padding(.horizontal, DKLayout.screenPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isClauseFocused)
        .animation(.easeInOut(duration: 0.2), value: viewModel.hasOriginal)
        .background(Color.dkBackground)
        .background(KeyboardDismissOnTap())
        .overlay(alignment: .top) {
            if let message = toastMessage {
                Text(message)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showMemorySaveSheet) {
            if let snapshot = pendingMemorySnapshot {
                MemorySaveSheet(snapshot: snapshot) { slotLabel in
                    presentToast("Saved to \(slotLabel)")
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                .presentationDetents([.medium])
            }
        }
        .alert(
            unsavedChangesAlertTitle,
            isPresented: Binding(
                get: { pendingMemoryRestoreSlot != nil },
                set: { if !$0 { pendingMemoryRestoreSlot = nil } }
            ),
            actions: {
                Button("Open", role: .destructive) {
                    if let slotKey = pendingMemoryRestoreSlot {
                        performMemoryRestore(slotKey: slotKey)
                    }
                    pendingMemoryRestoreSlot = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingMemoryRestoreSlot = nil
                }
            },
            message: {
                Text(unsavedChangesAlertMessage)
            }
        )
        .task {
            // One-shot migration-failure notice. The MemoryStore sets
            // `didWipeOnMigration` if the previous session ended with
            // an incompatible store; surface it once and clear.
            if memoryStore.didWipeOnMigration {
                presentToast("Saved memory was cleared because the app was updated.")
                memoryStore.didWipeOnMigration = false
            }
        }
    }

    // MARK: - Toast

    /// Replaces the toast message and cancels any prior dismissal task,
    /// so a fresh toast does not get cleared by an older 1.5s timer.
    private func presentToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation { toastMessage = message }
        let task = DispatchWorkItem {
            withAnimation { toastMessage = nil }
        }
        toastDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }

    // MARK: - Memory restore plumbing

    private var isMemoryDirty: Bool {
        let trimmed = viewModel.clauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.hasOriginal || !trimmed.isEmpty
    }

    private var unsavedChangesAlertTitle: String {
        "Open this memory?"
    }

    private var unsavedChangesAlertMessage: String {
        let autoOn = UserDefaults.standard.bool(forKey: "dk_autoSaveMemory")
        if autoOn {
            return "Your current work will be replaced. It is currently in the Auto slot."
        }
        return "Your current work will be replaced."
    }

    /// Routes a tap on a plus-sheet memory button. If the live editor
    /// is dirty AND the tapped slot is not the one already loaded,
    /// raises the unsaved-changes alert; otherwise restores immediately.
    func handleMemoryLoadTap(slotKey: String) {
        // Same slot already loaded → no-op (live state matches the slot).
        if viewModel.loadedFromSlotKey == slotKey {
            return
        }
        if isMemoryDirty {
            pendingMemoryRestoreSlot = slotKey
        } else {
            performMemoryRestore(slotKey: slotKey)
        }
    }

    private func performMemoryRestore(slotKey: String) {
        guard let entry = memoryStore.entry(for: slotKey) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            clauseOpacity = 0.4
        }
        viewModel.restore(from: entry)
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.25)) {
            clauseOpacity = 1.0
        }
    }
}

// MARK: - Extracted Modifier Groups

/// Breaks the large modifier chain into distinct sub-expressions so the
/// Swift type-checker can handle them individually.

private extension View {

    // MARK: onChange / task handlers (delegates to two sub-methods)

    func applyChangeHandlers(
        viewModel: DraftingViewModel,
        appState: AppState,
        storedStyleRaw: Binding<String>,
        clauseOpacity: Binding<Double>,
        showCameraPicker: Binding<Bool>,
        showImagePicker: Binding<Bool>,
        showTrackChangesPicker: Binding<Bool>,
        guardImport: @escaping (@escaping () -> Void) -> Void
    ) -> some View {
        self
            .applyViewModelObservers(
                viewModel: viewModel,
                storedStyleRaw: storedStyleRaw,
                clauseOpacity: clauseOpacity
            )
            .applyQuickActionHandlers(
                viewModel: viewModel,
                appState: appState,
                showCameraPicker: showCameraPicker,
                showImagePicker: showImagePicker,
                showTrackChangesPicker: showTrackChangesPicker,
                guardImport: guardImport
            )
    }

    // MARK: ViewModel observers (style, heat, rephrase)

    private func applyViewModelObservers(
        viewModel: DraftingViewModel,
        storedStyleRaw: Binding<String>,
        clauseOpacity: Binding<Double>
    ) -> some View {
        self
            .onChange(of: storedStyleRaw.wrappedValue) { _, newRaw in
                let newStyle = DraftingStyle(rawValue: newRaw) ?? .aplus
                let oldStyle = viewModel.activeStyle
                guard newStyle != oldStyle else { return }
                guard !viewModel.isRestoringSelection else { return }
                viewModel.activeStyle = newStyle
                viewModel.rephraseCache.removeAll()
                viewModel.clearAnalysisCache()
                // Style change (from Settings) updates the preference for the
                // next explicit rephrase only — it does not automatically
                // re-run the current result. The user must request a new rephrase.
            }
            .onChange(of: viewModel.selectedHeat) { oldHeat, newHeat in
                // Ignore programmatic selection restores (cancel-overwrite etc.).
                guard newHeat != nil, !viewModel.isRestoringSelection else { return }
                // Ignore taps that arrive while a previous rephrase or OCR
                // trim is still running. Without this guard, the cascading
                // cancel/restart on top of an in-flight task was the primary
                // cause of spurious "Network error" banners.
                //
                // `!viewModel.isAnyTellMeWorkInFlight` enforces Rule B
                // (Tell Me / Revise cannot be re-triggered while one is in
                // flight) at the bias-pill entry point. The visual pill
                // disable below mirrors the same gate via `canTriggerRephrase`.
                guard !viewModel.isLoading,
                      !viewModel.isTrimming,
                      !viewModel.isAnyTellMeWorkInFlight else {
                    // Snap the selection back to what was actually active so
                    // the capsule doesn't give the impression the tap worked.
                    viewModel.revertHeatSelection(to: oldHeat)
                    return
                }
                viewModel.triggerRephrase(previousStyle: viewModel.activeStyle, previousHeat: oldHeat)
            }
            .onChange(of: viewModel.rephraseJustCompleted) { _, completed in
                if completed {
                    clauseOpacity.wrappedValue = 0.0
                    withAnimation(.easeIn(duration: 0.25)) { clauseOpacity.wrappedValue = 1.0 }
                    #if !targetEnvironment(simulator)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.selectedHeat)
            .animation(.easeInOut(duration: 0.2), value: viewModel.activeTab == .original)
    }

    // MARK: Quick-action task / onChange handlers

    private func applyQuickActionHandlers(
        viewModel: DraftingViewModel,
        appState: AppState,
        showCameraPicker: Binding<Bool>,
        showImagePicker: Binding<Bool>,
        showTrackChangesPicker: Binding<Bool>,
        guardImport: @escaping (@escaping () -> Void) -> Void
    ) -> some View {
        self
            .task { await viewModel.loadMonthlyUsage() }
            .task {
                if appState.pendingCameraQuickAction {
                    appState.pendingCameraQuickAction = false
                    viewModel.resetAll()
                    if viewModel.canOpenCamera() {
                        showCameraPicker.wrappedValue = true
                    }
                }
                if appState.pendingPhotoQuickAction {
                    appState.pendingPhotoQuickAction = false
                    viewModel.resetAll()
                    showImagePicker.wrappedValue = true
                }
                if appState.pendingTrackChangesQuickAction {
                    appState.pendingTrackChangesQuickAction = false
                    guardImport {
                        viewModel.resetAll()
                        showTrackChangesPicker.wrappedValue = true
                    }
                }
            }
            .onChange(of: appState.pendingCameraQuickAction) { _, pending in
                guard pending else { return }
                appState.pendingCameraQuickAction = false
                viewModel.resetAll()
                if viewModel.canOpenCamera() {
                    showCameraPicker.wrappedValue = true
                }
            }
            .onChange(of: appState.pendingPhotoQuickAction) { _, pending in
                guard pending else { return }
                appState.pendingPhotoQuickAction = false
                viewModel.resetAll()
                showImagePicker.wrappedValue = true
            }
            .onChange(of: appState.pendingTrackChangesQuickAction) { _, pending in
                guard pending else { return }
                appState.pendingTrackChangesQuickAction = false
                guardImport {
                    viewModel.resetAll()
                    showTrackChangesPicker.wrappedValue = true
                }
            }
    }

    // MARK: Sheets & full-screen covers

    func applySheetModifiers(
        viewModel: DraftingViewModel,
        appState: AppState,
        showImagePicker: Binding<Bool>,
        showCameraPicker: Binding<Bool>,
        showInfoSheet: Binding<Bool>,
        showSettings: Binding<Bool>,
        exportShareItem: Binding<ExportShareItem?>,
        showAttachSheet: Binding<Bool>,
        showTrackChangesPicker: Binding<Bool>,
        showAnalysisSheet: Binding<Bool>,
        showEditOriginalConfirmation: Binding<Bool>,
        showUseOutputAsOriginalConfirmation: Binding<Bool>,
        onLoadMemory: @escaping (String) -> Void,
        guardImport: @escaping (@escaping () -> Void) -> Void
    ) -> some View {
        self
            .sheet(isPresented: showImagePicker) {
                ImagePickerRepresentable { image in
                    viewModel.performOCR(on: image)
                }
            }
            .fullScreenCover(isPresented: showCameraPicker) {
                CameraPickerRepresentable { image in
                    viewModel.captureAndTrimClause(from: image)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: showInfoSheet) {
                DraftingInfoSheet()
            }
            .sheet(isPresented: showSettings) {
                SettingsView()
                    .environmentObject(appState)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: exportShareItem) { item in
                ActivityViewController(items: item.items)
            }
            .sheet(isPresented: showAttachSheet) {
                AttachmentSheet(
                    viewModel: viewModel,
                    onShowImagePicker: {
                        showAttachSheet.wrappedValue = false
                        viewModel.plusUsed = true
                        let action = {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showImagePicker.wrappedValue = true
                            }
                        }
                        guardImport(action)
                    },
                    onShowCamera: {
                        showAttachSheet.wrappedValue = false
                        viewModel.plusUsed = true
                        let action = {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                if viewModel.canOpenCamera() {
                                    showCameraPicker.wrappedValue = true
                                }
                            }
                        }
                        guardImport(action)
                    },
                    onPaste: {
                        showAttachSheet.wrappedValue = false
                        viewModel.plusUsed = true
                        let action = {
                            viewModel.pasteFromClipboard()
                        }
                        guardImport(action)
                    },
                    onTrackChanges: {
                        showAttachSheet.wrappedValue = false
                        viewModel.plusUsed = true
                        let action = {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showTrackChangesPicker.wrappedValue = true
                            }
                        }
                        guardImport(action)
                    },
                    onEditOriginal: {
                        // Dismiss the sheet first; defer raising the
                        // alert by 0.35s so the sheet's collapse
                        // animation does not eat the alert presentation
                        // (mirrors `onShowImagePicker`/`onShowCamera`/
                        // `onTrackChanges` sequencing). No `guardImport`
                        // — this is a manage-original action, not an
                        // import that would replace existing content.
                        showAttachSheet.wrappedValue = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showEditOriginalConfirmation.wrappedValue = true
                        }
                    },
                    onUseOutputAsOriginal: {
                        // Same dismiss-then-alert pattern as
                        // `onEditOriginal`. The alert body warns about
                        // cache clearing; the actual mutation runs
                        // inside `viewModel.useOutputAsOriginal()` from
                        // the alert's destructive button.
                        showAttachSheet.wrappedValue = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showUseOutputAsOriginalConfirmation.wrappedValue = true
                        }
                    },
                    onLoadMemory: { slotKey in
                        // Dismiss the plus-sheet first; defer the
                        // dirty-check + restore by 0.35s so the sheet's
                        // collapse animation does not eat the
                        // unsaved-changes alert presentation.
                        showAttachSheet.wrappedValue = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onLoadMemory(slotKey)
                        }
                    }
                )
                .presentationDetents([.height(580), .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: showTrackChangesPicker) {
                ImagePickerRepresentable { image in
                    viewModel.pendingTrackChangeImage = image
                    viewModel.showTrackChangesSheet = true
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { viewModel.showTrackChangesSheet },
                    set: { viewModel.showTrackChangesSheet = $0 }
                )
            ) {
                TrackChangesSelectionView(viewModel: viewModel)
            }
            .sheet(isPresented: showAnalysisSheet) { AnalysisSheetView(viewModel: viewModel) }
            .sheet(
                isPresented: Binding(
                    get: { viewModel.showOCRCleanupReviewSheet },
                    set: { viewModel.showOCRCleanupReviewSheet = $0 }
                )
            ) {
                OCRCleanupReviewSheet(viewModel: viewModel)
            }
            .sheet(
                isPresented: Binding(
                    get: { viewModel.showFixesSheet },
                    set: { viewModel.showFixesSheet = $0 }
                )
            ) {
                FixesSheetView(viewModel: viewModel)
            }
    }

    // MARK: Alert dialogs

    func applyAlertModifiers(
        viewModel: DraftingViewModel,
        showEditOriginalConfirmation: Binding<Bool>,
        showUseOutputAsOriginalConfirmation: Binding<Bool>
    ) -> some View {
        self
            .applyAlertGroupA(viewModel: viewModel)
            .applyAlertGroupB(
                viewModel: viewModel,
                showEditOriginalConfirmation: showEditOriginalConfirmation,
                showUseOutputAsOriginalConfirmation: showUseOutputAsOriginalConfirmation
            )
    }

    func applyAlertGroupA(viewModel: DraftingViewModel) -> some View {
        self
            .alert(
                "API Key Invalid",
                isPresented: Binding(
                    get: { viewModel.showFallbackAlert },
                    set: { viewModel.showFallbackAlert = $0 }
                )
            ) {
                Button("Use System Key") {
                    viewModel.retryWithSystemKey()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelFallback()
                }
            } message: {
                Text("Your API key is invalid or expired. Use the system key instead? You can update your key in Settings.")
            }
            .alert(
                "Clean Up Text?",
                isPresented: Binding(
                    get: { viewModel.showPhotoCleanUpPrompt },
                    set: { viewModel.showPhotoCleanUpPrompt = $0 }
                )
            ) {
                Button("Yes") {
                    viewModel.performPhotoCleanUp()
                }
                Button("No", role: .cancel) { }
            } message: {
                Text("The text was captured from a photo. Do you want AI to clean it up (remove page numbers, fix OCR errors, trim incomplete sentences)?")
            }
            .alert(
                "Rephrase from which version?",
                isPresented: Binding(
                    get: { viewModel.showOverwriteConfirmation },
                    set: { viewModel.showOverwriteConfirmation = $0 }
                )
            ) {
                Button("My current draft") {
                    viewModel.confirmRephraseFromCurrentDraft()
                }
                Button("The Original", role: .destructive) {
                    viewModel.confirmOverwrite()
                }
                Button("Make my draft the new Original") {
                    viewModel.confirmUseAsNewOriginal()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelOverwrite()
                }
            } message: {
                Text("You've changed the draft since the Original was locked.")
            }
            .alert(
                "Do you want to review the clean-up result first?",
                isPresented: Binding(
                    get: { viewModel.showReviewPrompt },
                    set: { viewModel.showReviewPrompt = $0 }
                )
            ) {
                Button("Yes") {
                    viewModel.acceptReview()
                }
                Button("No", role: .cancel) {
                    viewModel.declineReview()
                }
            } message: {
                Text("AI can make errors and may occasionally hallucinate.")
            }
    }

    func applyAlertGroupB(
        viewModel: DraftingViewModel,
        showEditOriginalConfirmation: Binding<Bool>,
        showUseOutputAsOriginalConfirmation: Binding<Bool>
    ) -> some View {
        self
            .alert(
                "Start anew?",
                isPresented: Binding(
                    get: { viewModel.showImportOverwriteWarning },
                    set: { viewModel.showImportOverwriteWarning = $0 }
                )
            ) {
                Button("Yes", role: .destructive) {
                    viewModel.confirmImportWithReset()
                }
                Button("No") {
                    viewModel.confirmImportReplaceOriginal()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelImport()
                }
            } message: {
                Text("You already have text. \"Yes\" resets everything and starts fresh. \"No\" replaces only the original text.")
            }
            // "Edit Original?" confirmation. Reached via either
            // (a) long-press on the Original-tab text body →
            // "Edit Original…" context-menu item, or (b) the plus-sheet
            // "Edit Original" card. Go enters edit-original mode (clears
            // the AI-derived caches, leaves the existing Output
            // untouched); Cancel is a no-op.
            .alert(
                "Edit Original?",
                isPresented: showEditOriginalConfirmation
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Go", role: .destructive) {
                    viewModel.startEditingOriginal()
                }
            } message: {
                Text("All AI-generated background knowledge \u{2014} Tell Me, bias variants, Revise \u{2014} will be cleared. The text currently shown in Output stays.")
            }
            // "Use Output as Original?" confirmation. Reached only via
            // the plus-sheet "Use Output as Original" card. The
            // destructive button promotes the current Output to the
            // new locked Original via `viewModel.useOutputAsOriginal()`,
            // which clears Tell Me / bias variants / Fixes and seeds a
            // clean Show-Changes baseline; the Output text itself
            // stays in place. Cancel is a no-op.
            .alert(
                "Use Output as Original?",
                isPresented: showUseOutputAsOriginalConfirmation
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Use as Original", role: .destructive) {
                    viewModel.useOutputAsOriginal()
                }
            } message: {
                Text("The current Output becomes your new locked Original. Tell Me, bias variants, and Revise are cleared. The Output text itself stays in place.")
            }
            .alert(
                "Style Not Supported",
                isPresented: Binding(
                    get: { viewModel.showSimpleFallbackAlert },
                    set: { viewModel.showSimpleFallbackAlert = $0 }
                )
            ) {
                Button("Continue") {
                    viewModel.confirmSimpleFallbackToLDN()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Tell Me is not available for the Simplified style. The analysis will use the London (LDN) style as a fallback.")
            }
            // Out-of-scope rejection from the Additional-Instruction (Send)
            // flow. Title is fixed; body is the model's `reason` (or the
            // per-category fallback). The user's typed instruction is left
            // untouched on rejection so they can edit and resend.
            .alert(
                "Additional instructions are out of scope.",
                isPresented: Binding(
                    get: { viewModel.instructionRejection != nil },
                    set: { if !$0 { viewModel.dismissInstructionRejection() } }
                ),
                presenting: viewModel.instructionRejection
            ) { _ in
                Button("OK", role: .cancel) {
                    viewModel.dismissInstructionRejection()
                }
            } message: { rejection in
                Text(rejection.reason)
            }
            // Pre-Tell-Me informational alert for the Fixes auto-fire
            // path. Single OK button — the Tell Me API call has already
            // fired in parallel, so dismissal is purely informational.
            // Two body variants: SIMPLE-merged (covers both the
            // SIMPLE-fallback notice and the Tell-Me-running notice in
            // a single alert) and standard.
            .alert(
                "Analysis required.",
                isPresented: Binding(
                    get: { viewModel.showFixesPreTellMeAlert },
                    set: { viewModel.showFixesPreTellMeAlert = $0 }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.fixesPreTellMeAlertIsSIMPLE
                    ? "Revise needs a Tell Me analysis first. Tell Me isn't available for Simplified style, so Chimera Law will analyse under the London style and prepare your revisions in the background. The revisions will open automatically when ready."
                    : "Tell Me hasn't been run on this clause yet. Chimera Law is analysing it in the background. The revisions will open automatically when ready.")
            }
            // Revise error alert. Phase-tagged copy is composed by the
            // view-model ("Couldn't analyse the clause." or
            // "Couldn't generate revisions." prefixed in front of the
            // existing DraftingError.errorDescription). Single OK
            // dismisses; user can re-tap Revise to retry.
            .alert(
                "Revise",
                isPresented: Binding(
                    get: { viewModel.fixesError != nil },
                    set: { if !$0 { viewModel.fixesError = nil } }
                ),
                presenting: viewModel.fixesError
            ) { _ in
                Button("OK", role: .cancel) {
                    viewModel.fixesError = nil
                }
            } message: { error in
                Text(error)
            }
    }
}

// MARK: - Keyboard Dismiss on Background Tap

/// Installs a UITapGestureRecognizer on the window that dismisses the
/// keyboard when tapping non-interactive areas. Uses a gesture delegate
/// to skip UITextField, UITextView, and UIControl so focus/keyboard
/// still work normally on those elements.
private struct KeyboardDismissOnTap: UIViewRepresentable {

    final class JsonDismissView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, let coordinator else { return }
            let tag = "KeyboardDismissGR"
            for gr in (window.gestureRecognizers ?? []) where gr.name == tag {
                return
            }
            let tap = UITapGestureRecognizer(
                target: coordinator,
                action: #selector(Coordinator.dismissKeyboard)
            )
            tap.name = tag
            tap.cancelsTouchesInView = false
            tap.delegate = coordinator
            window.addGestureRecognizer(tap)
        }
    }

    func makeUIView(context: Context) -> JsonDismissView {
        let v = JsonDismissView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ uiView: JsonDismissView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let view = touch.view else { return true }
            if view is UITextField || view is UITextView || view is UIControl {
                return false
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

// MARK: - Subviews

private extension DraftingView {

    // MARK: - Drawer Grabber

    /// Three-state grabber bar:
    ///   1. Idle, no analysis cached → systemGray4, static.
    ///   2. Idle, analysis cached for the current Original (any style) →
    ///      dkPrimary (indigo), static. Bound to the new
    ///      `hasAnalysisForCurrentOriginal` so the indigo signal survives
    ///      the SIMPLE-fallback asymmetry.
    ///   3. Any Tell Me-related call in flight → opacity-pulsed
    ///      (100% → 70% → 100% on a 1.4s ease-in-out loop). Under
    ///      `accessibilityReduceMotion`, the pulse is replaced by a
    ///      static 60% opacity rendering of the same colour.
    var drawerGrabber: some View {
        DrawerGrabber(viewModel: viewModel) {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.isDrawerExpanded.toggle()
            }
        } onDrag: { vertical in
            if vertical > 20 && !viewModel.isDrawerExpanded {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.isDrawerExpanded = true
                }
            } else if vertical < -20 && viewModel.isDrawerExpanded {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.isDrawerExpanded = false
                }
            }
        }
    }

    // MARK: - Swipe Navigation

    private func swipeToNextTab() {
        switch viewModel.activeTab {
        case .original:
            viewModel.switchTab(to: .showChanges)
        case .showChanges:
            viewModel.switchTab(to: .current)
        case .current:
            break // already at the end
        }
    }

    private func swipeToPreviousTab() {
        switch viewModel.activeTab {
        case .current:
            viewModel.switchTab(to: .showChanges)
        case .showChanges:
            viewModel.switchTab(to: .original)
        case .original:
            break // already at the start
        }
    }

    /// If originalText exists, defer the import action behind a warning popup.
    /// Otherwise execute immediately.
    private func guardImport(action: @escaping () -> Void) {
        if viewModel.originalText != nil {
            viewModel.pendingImportAction = action
            viewModel.showImportOverwriteWarning = true
        } else {
            action()
        }
    }


    // MARK: - Tab Riders + Clause Editor

    var clauseEditorWithTabs: some View {
        VStack(spacing: 0) {
            // Grabber bar
            drawerGrabber
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Bias selector + style pill (conditionally visible)
            if viewModel.isDrawerExpanded {
                HStack(spacing: 8) {
                    HeatSelector(selection: $viewModel.selectedHeat,
                                 appearDeselected: viewModel.hasManualEdits,
                                 compact: true,
                                 onReselect: {
                                     // Re-tapping the already selected bias
                                     // re-triggers a rephrase. Pass the current
                                     // style/heat as "previous" so that if the
                                     // overwrite warning fires and the user
                                     // cancels, cancelOverwrite restores the
                                     // real selection rather than clearing it.
                                     if viewModel.canTriggerRephrase {
                                         viewModel.triggerRephrase(
                                             previousStyle: viewModel.activeStyle,
                                             previousHeat: viewModel.selectedHeat
                                         )
                                     }
                                 },
                                 isAvailable: { heat in
                                     // A bias is tappable only when a rephrase
                                     // can actually run for it. We already
                                     // guard the onChange, but disabling the
                                     // button here gives immediate visual
                                     // feedback and stops the animation flicker.
                                     //
                                     // Tracks `canTriggerRephrase` so all the
                                     // Layer 3 gates (originalText != nil,
                                     // !isAnalysing, !isFixesInFlight) flow
                                     // through to the visual disabled state.
                                     // `!isTrimming` is preserved because the
                                     // OCR trim path is not part of
                                     // `canTriggerRephrase`.
                                     guard viewModel.canTriggerRephrase,
                                           !viewModel.isTrimming else { return false }
                                     return viewModel.isHeatAvailable(heat)
                                 })

                    Rectangle()
                        .fill(Color.dkTextSecondary.opacity(0.2))
                        .frame(width: 1, height: 24)

                    // Fixes button replaces the former active-style pill.
                    // The active style remains source-of-truth in Settings.
                    FixesButton(viewModel: viewModel) {
                        viewModel.triggerFixesFlow()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Divider between drawer area and tabs
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 2)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            // Segmented tab control
            if viewModel.hasOriginal {
                segmentedTabBar
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }

            // Content area
            if viewModel.activeTab == .showChanges && viewModel.hasOriginal {
                DiffView(viewModel: viewModel)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .opacity(clauseOpacity)
            } else {
                // Text editor (Output or Original)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.clauseText)
                        .font(.dkBody)
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .contentMargins(.bottom, 60, for: .scrollContent)
                        .focused($isClauseFocused)
                        // Editor is read-only on the Original tab unless
                        // the user has explicitly entered edit-original
                        // mode via long-press → "Edit Original…" → Go.
                        .disabled(viewModel.activeTab == .original
                                  && !viewModel.isEditingOriginal)
                        // Long-press surfaces the "Edit Original…" menu
                        // item only when (a) we are on the Original tab,
                        // (b) a baseline is locked, and (c) we are not
                        // already editing it. The .contextMenu is mounted
                        // on a transparent, hit-testable overlay rather
                        // than directly on the TextEditor, because on
                        // iOS 26 a .disabled(true) TextEditor swallows
                        // the long-press gesture so the menu never fires.
                        // The overlay is only present in the locked-not-
                        // editing state (a strict subset of the disabled
                        // state); the moment isEditingOriginal flips to
                        // true the overlay disappears and the editor is
                        // fully interactive (typing, scrolling,
                        // selection unaffected).
                        .overlay {
                            if viewModel.activeTab == .original
                                && viewModel.originalText != nil
                                && !viewModel.isEditingOriginal {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        Button {
                                            showEditOriginalConfirmation = true
                                        } label: {
                                            Label("Edit Original\u{2026}",
                                                  systemImage: "pencil")
                                        }
                                    }
                                    .accessibilityLabel("Original text")
                                    .accessibilityHint("Long-press for Edit Original option")
                            }
                        }
                        .onChange(of: viewModel.clauseText) { _, newValue in
                            if newValue.count > 5000 {
                                viewModel.clauseText = String(newValue.prefix(5000))
                            }
                            // Detect user edits on the Output tab
                            viewModel.checkForUserEdits()
                            // Word-boundary snapshot for the unified
                            // undo/redo chain. The view-model's push
                            // method internally enforces:
                            // (a) not currently replaying an undo,
                            // (b) on the Output tab,
                            // (c) Original is locked (pre-lock typing
                            //     does not push).
                            if !viewModel.isSuppressingSnapshot,
                               viewModel.activeTab == .current {
                                let newCount = viewModel.wordCount(newValue)
                                if newCount != viewModel.lastSnapshotWordCount {
                                    viewModel.pushOutputWordBoundarySnapshot()
                                }
                            }
                        }

                    if viewModel.clauseText.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "doc.text")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(Color(hex: "B2B2B2"))
                            Text("Paste, type, upload a screenshot/image with text, or photograph it")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(Color(hex: "B2B2B2"))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .opacity(clauseOpacity)
            }

            if viewModel.isLoading || viewModel.isTrimming {
                AnalysisProgressView(isTrimming: viewModel.isTrimming)
                    .padding(.top, 16)
                    // Previously 56. Added 20pt so the elapsed-time counter
                    // does not sit flush against the undo/redo / analyse pill.
                    .padding(.bottom, 76)
            }
        }
        .frame(maxHeight: .infinity)
        .background(clauseBackground)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isDrawerExpanded)
        .overlay(alignment: .bottom) {
            if viewModel.showUndoRedoPill && !showLockPill {
                UndoRedoPill(
                    canUndo: viewModel.canUndo,
                    canRedo: viewModel.canRedo,
                    onUndo: { viewModel.undo() },
                    onRedo: { viewModel.redo() }
                )
                .padding(.bottom, 12)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: viewModel.showUndoRedoPill)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showUndoRedoPill)
        .overlay(alignment: .bottom) {
            if viewModel.activeTab == .original
                && viewModel.hasGeneratedOutput
                && viewModel.originalText != nil
                && !viewModel.isEditingOriginal {
                AnalysePill(
                    hasCachedResult: viewModel.hasAnalysisCache,
                    isEnabled: viewModel.canAnalyse || viewModel.hasAnalysisCache,
                    isAnalysing: viewModel.isAnalysing,
                    action: { viewModel.onAnalyseButtonTapped() }
                )
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.activeTab == .original && viewModel.hasGeneratedOutput && !viewModel.isEditingOriginal)
        .overlay(alignment: .bottom) {
            if showLockPill {
                LockPill(
                    isEnabled: viewModel.canLockAsOriginal,
                    // Action selector: in edit-original mode the pill
                    // commits the edited Original (preserves the
                    // existing Output); otherwise it performs the
                    // pre-lock first-time lock. The two view-model
                    // methods do different things and must not be
                    // collapsed — `lockAsOriginal()` flips
                    // `isEditOnTheGo = true` and overwrites
                    // `currentText`, which is wrong for the post-lock
                    // re-edit path.
                    action: {
                        if viewModel.isEditingOriginal {
                            viewModel.commitEditingOriginal()
                        } else {
                            viewModel.lockAsOriginal()
                        }
                    }
                )
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showLockPill)
        // Use simultaneousGesture so horizontal swipe-to-tab doesn't block
        // vertical scrolling in the TextEditor / DiffView below. Without
        // this, the gesture recognizer can capture touches that were meant
        // for the scroll view (visible on the Original tab offline).
        .simultaneousGesture(
            DragGesture(minimumDistance: 50, coordinateSpace: .local)
                .onEnded { value in
                    // Suppress swipe-to-tab while editing the locked
                    // Original — symmetric with the disabled Changes
                    // and Output tab segments below.
                    guard viewModel.hasOriginal,
                          viewModel.hasGeneratedOutput,
                          !viewModel.isEditingOriginal else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    // Only act on predominantly horizontal swipes.
                    guard abs(horizontal) > abs(vertical) else { return }
                    if horizontal < 0 {
                        // Swipe left → next tab
                        swipeToNextTab()
                    } else {
                        // Swipe right → previous tab
                        swipeToPreviousTab()
                    }
                }
        )
        // Card always fully rounded now that heat is inside.
        .clipShape(RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
    }

    var segmentedTabBar: some View {
        HStack(spacing: 2) {
            segmentButton(title: "Original",
                          isActive: viewModel.activeTab == .original) {
                viewModel.switchTab(to: .original)
            }
            if viewModel.hasGeneratedOutput {
                // Changes and Output are tap-inert and visually
                // dimmed while the user is editing the locked
                // Original — keeps the user inside the edit-original
                // mode until they commit via the LockPill.
                segmentButton(title: "Changes",
                              isActive: viewModel.activeTab == .showChanges,
                              isDisabled: viewModel.isEditingOriginal) {
                    viewModel.switchTab(to: .showChanges)
                }
                segmentButton(title: "Output",
                              isActive: viewModel.activeTab == .current,
                              isDisabled: viewModel.isEditingOriginal) {
                    viewModel.switchTab(to: .current)
                }
            }
        }
        .padding(2)
        .glassEffect(.regular, in: .capsule)
        .scaleEffect(tabBarPulse ? 1.05 : 1.0)
    }

    func segmentButton(title: String,
                       isActive: Bool,
                       isDisabled: Bool = false,
                       action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        }) {
            Text(title)
                .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .dkTextPrimary : .dkTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    Group {
                        if isActive {
                            Capsule()
                                .fill(Color.dkBackground.opacity(0.6))
                        }
                    }
                )
                .opacity(isDisabled ? 0.4 : 1.0)
        }
        .disabled(isDisabled)
        .accessibilityLabel("\(title) view")
    }

    // MARK: - Bottom Input Section (Claude-style)

    /// Whether the instruction controls (text field, mic, send) are active.
    /// Only enabled once the original is locked in.
    private var isInstructionActive: Bool { viewModel.hasOriginal }

    /// True when the Lock pill should be visible.
    /// Shows during either:
    /// - the pre-lock phase (any non-empty text is in the editor and
    ///   no Original is locked yet), or
    /// - the post-lock edit-original phase (user long-pressed the
    ///   Original tab text and confirmed the "Edit Original?" alert).
    /// The pre-lock branch makes the pill appear as soon as text is
    /// added; it stays disabled (greyed) until the 3-word minimum is
    /// reached via `viewModel.canLockAsOriginal`.
    /// The two branches dispatch to different view-model actions; see
    /// the LockPill mount site for the action selector.
    private var showLockPill: Bool {
        let trimmed = viewModel.clauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prelock = !trimmed.isEmpty
                      && viewModel.originalText == nil
                      && !viewModel.isEditOnTheGo
        return prelock || viewModel.isEditingOriginal
    }

    var bottomInputSection: some View {
        VStack(spacing: 8) {
            // Live transcript indicator
            if speechService.isRecording, !speechService.transcript.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(speechService.transcript)
                        .font(.system(size: 14))
                        .foregroundColor(.dkTextSecondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }

            // Input field with plus button, mic, and send
            HStack(alignment: .center, spacing: 8) {
                // Plus button to open attachment sheet (always active)
                Button(action: { showAttachSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(viewModel.plusUsed ? .dkTextSecondary : .dkPrimary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Add content")

                // Text field (disabled until original is locked)
                let prompt = isInstructionActive
                    ? "Additional instructions..."
                    : "Import or type text first..."
                TextField("", text: $viewModel.additionalInstruction, prompt: Text(prompt).foregroundColor(Color(hex: "B2B2B2")).font(.dkCaption), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.dkCaption)
                    .foregroundColor(.dkTextPrimary)
                    .focused($isInstructionFocused)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(
                        Color.dkSurface
                            .opacity(isInstructionActive ? 1 : 0.5)
                            .overlay(instructionFieldBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(instructionBorderTint, lineWidth: 0.5)
                    )
                    .animation(.easeInOut(duration: 0.15), value: viewModel.additionalInstruction.count)
                    .disabled(!isInstructionActive)
                    .submitLabel(.send)
                    .onSubmit {
                        let trimmed = viewModel.additionalInstruction
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if viewModel.canTriggerRephrase
                            && isInstructionActive
                            && !trimmed.isEmpty
                            && viewModel.additionalInstruction.count <= AdditionalInstructionPrompt.characterLimit
                            && !viewModel.isLoading {
                            viewModel.triggerInstructionRephrase()
                        }
                    }

                // Microphone button — disabled until original is locked.
                // Permission denial is handled at tap time via an alert (not by greying out).
                let micBlocked = !isInstructionActive
                Button(action: {
                    let status = speechService.authorizationStatus
                    if status == .denied {
                        showMicSettingsAlert = true
                    } else if status == .restricted {
                        showMicRestrictedAlert = true
                    } else {
                        speechService.toggleRecording()
                    }
                }) {
                    Image(systemName: speechService.isRecording ? "waveform" : "microphone")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(
                            micBlocked ? Color(.systemGray4)
                            : speechService.isRecording ? .red
                            : .dkTextSecondary
                        )
                        .frame(width: 36, height: 36)
                        .symbolEffect(.variableColor.iterative, isActive: speechService.isRecording)
                }
                .disabled(micBlocked)
                .accessibilityLabel(speechService.isRecording ? "Stop voice input" : "Voice input")

                // Send / Rephrase button. Disabled until original is
                // locked, while the trimmed instruction is empty, while the
                // count exceeds the 500-character soft cap, or while a Send
                // is already in flight (Q5 — see plan §6.5). The up-arrow
                // icon is replaced by an inline spinner during in-flight
                // calls so the button keeps the same 32-pt footprint.
                Button(action: { viewModel.triggerInstructionRephrase() }) {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.dkPrimary)
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(viewModel.canTriggerRephrase && isInstructionActive ? .dkPrimary : Color(.systemGray4))
                        }
                    }
                }
                .disabled(
                    !viewModel.canTriggerRephrase
                    || !isInstructionActive
                    || viewModel.additionalInstruction
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                    || viewModel.additionalInstruction.count > AdditionalInstructionPrompt.characterLimit
                    || viewModel.isLoading
                )
                .accessibilityLabel(viewModel.isLoading ? "Rephrasing in progress" : "Rephrase clause")
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Refresh without prompting:
            // - initial: true seeds the button colour from the real system
            //   state on first render.
            // - subsequent fires re-read status when the app returns from
            //   background so the button re-enables if the user granted
            //   access in Settings.
            if phase == .active {
                speechService.refreshAuthorizationStatus()
            }
        }
        .onChange(of: speechService.isRecording) { _, recording in
            // When recording stops, append transcript to additional instruction
            if !recording, !speechService.transcript.isEmpty {
                let separator = viewModel.additionalInstruction.isEmpty ? "" : " "
                viewModel.additionalInstruction += separator + speechService.transcript
                speechService.transcript = ""
            }
        }
        .onChange(of: speechService.errorMessage) { _, error in
            if let error {
                // Auth errors are handled via the settings alert; only surface
                // genuine recording failures (audio engine, recognizer unavailable) here.
                let isAuthError = speechService.authorizationStatus == .denied
                    || speechService.authorizationStatus == .restricted
                if !isAuthError {
                    viewModel.errorMessage = error
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: speechService.isRecording)
        .alert("Speech Recognition Access", isPresented: $showMicSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Chimera Law does not have permission to use speech recognition. You can enable it in Settings.")
        }
        .alert("Speech Recognition Unavailable", isPresented: $showMicRestrictedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Speech recognition is restricted on this device and cannot be enabled.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                isClauseFocused = false
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            .font(.dkBody)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { showInfoSheet = true }) {
                Image("AppIconDisplay")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        // New + Save + Export share a glass group
        ToolbarItemGroup(placement: .topBarTrailing) {
            // New button
            Button(action: { viewModel.resetAll() }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 21))
                    .foregroundColor(viewModel.canReset ? .dkPrimary : Color(.systemGray4))
            }
            .disabled(!viewModel.canReset)

            // Save (Memory) button — opens the manual save sheet.
            // Icon is hard-coded to outlined `externaldrive` to match
            // the visual rhythm of the other top-toolbar icons (none of
            // which use a filled variant). The "memory available" cue
            // lives in the plus-sheet via the per-slot green tint.
            Button(action: {
                pendingMemorySnapshot = viewModel.memorySnapshot()
                showMemorySaveSheet = true
            }) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 21))
                    .foregroundColor(canSaveToMemory ? .dkPrimary : Color(.systemGray4))
            }
            .disabled(!canSaveToMemory)
            .accessibilityLabel("Save to memory")

            // Export menu
            Menu {
                Button(action: {
                    exportShareItem = ExportShareItem(items: [viewModel.exportableText])
                }) {
                    Label("Share as Text", systemImage: "text.quote")
                }

                Button(action: {
                    ExportService.copyToClipboard(from: viewModel)
                    presentToast("Copied")
                }) {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }

                Button(action: {
                    if let url = ExportService.generateDocx(from: viewModel) {
                        exportShareItem = ExportShareItem(items: [url])
                    }
                }) {
                    Label("Export as Word File", systemImage: "doc.richtext")
                }

                Button(action: {
                    let icon = OnboardingView.loadAppIcon()
                    if let url = ExportService.generatePDF(viewModel: viewModel, appIconImage: icon) {
                        exportShareItem = ExportShareItem(items: [url])
                    }
                }) {
                    Label("Export as PDF", systemImage: "doc.text")
                }

                if viewModel.hasAnalysisCache {
                    Button(action: {
                        let icon = OnboardingView.loadAppIcon()
                        if let url = ExportService.generateTellMePDF(viewModel: viewModel, appIconImage: icon) {
                            exportShareItem = ExportShareItem(items: [url])
                        }
                    }) {
                        Label("Export Tell Me as PDF", systemImage: "text.magnifyingglass")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 21))
                    .foregroundColor(viewModel.canCopy ? .dkPrimary : Color(.systemGray4))
            }
            .disabled(!viewModel.canCopy)
            .accessibilityLabel("Export clause")
        }
        // Settings in its own glass capsule
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: { showSettings = true }) {
                Image(systemName: "gear")
                    .font(.system(size: 21))
                    .foregroundColor(.dkPrimary)
            }
        }
    }

    // MARK: - Helpers

    var clauseBackground: Color {
        // Mirror the pre-lock untinted appearance while the user is
        // editing the locked Original. Visual rule across the app's
        // life-cycle states: locked = tinted, unlocked-for-edit =
        // untinted. SwiftUI picks the change up automatically because
        // `isEditingOriginal` is published by the view-model.
        if viewModel.showingOriginal && !viewModel.isEditingOriginal {
            return colorScheme == .dark
                ? Color(red: 0.12, green: 0.12, blue: 0.22)
                : Color(red: 0.94, green: 0.94, blue: 1.0)
        }
        return Color.dkSurface
    }
}

// MARK: - Analysis Progress View (stepped loading indicator)

/// Cycles through analysis-stage labels while the AI processes the clause.
/// Designed for a potential wait of up to ~60 seconds.
private struct AnalysisProgressView: View {

    let isTrimming: Bool

    private static let analysisSteps = [
        "Analysing clause...",
        "Identifying market standard...",
        "Assessing bias...",
        "Flagging risks...",
        "Evaluating deviations...",
        "Generating variants...",
        "Refining output..."
    ]

    @State private var stepIndex: Int = 0
    @State private var opacity: Double = 1.0
    @State private var elapsedSeconds: Int = 0

    /// Step timer fires every 8 seconds → 7 steps ≈ 56 seconds of coverage.
    private let stepTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    /// Elapsed timer fires every second for the counter.
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(1.6)
                .tint(.dkPrimary)

            Text(currentLabel)
                .font(.dkCaption)
                .foregroundColor(Color(hex: "B2B2B2"))
                .opacity(opacity)
                .animation(.easeInOut(duration: 0.3), value: opacity)

            Text(timeString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(hex: "999999"))
        }
        .onReceive(stepTimer) { _ in
            guard !isTrimming else { return }
            let next = stepIndex + 1
            guard next < Self.analysisSteps.count else { return }

            // Fade out → swap text → fade in
            withAnimation(.easeOut(duration: 0.15)) { opacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                stepIndex = next
                withAnimation(.easeIn(duration: 0.2)) { opacity = 1 }
            }
        }
        .onReceive(clockTimer) { _ in
            elapsedSeconds += 1
        }
    }

    private var currentLabel: String {
        if isTrimming { return "Processing image..." }
        return Self.analysisSteps[stepIndex]
    }

    private var timeString: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        if mins > 0 {
            return String(format: "%d:%02d elapsed", mins, secs)
        } else {
            return "\(secs)s elapsed"
        }
    }
}

// MARK: - Attachment Sheet (Claude-style bottom sheet)

struct AttachmentSheet: View {

    @ObservedObject var viewModel: DraftingViewModel
    let onShowImagePicker: () -> Void
    let onShowCamera: () -> Void
    let onPaste: () -> Void
    let onTrackChanges: () -> Void
    let onEditOriginal: () -> Void
    let onUseOutputAsOriginal: () -> Void
    let onLoadMemory: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var memory = MemoryStore.shared
    @AppStorage("dk_autoSaveMemory") private var autoSaveMemory: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.dkTextSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.dkSecondary)
                        .clipShape(Circle())
                }
                Text("Add wording")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.dkTextPrimary)
                    .padding(.leading, 8)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Action buttons grid (2 x 2) followed by a separator and a
            // manage-original row. The two manage-original cards are
            // always rendered; their `enabled` flag varies with the
            // view-model's `canEditOriginalFromPlusSheet` /
            // `canUseOutputAsOriginalFromPlusSheet` gates.
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    attachOptionCard(icon: "camera.fill", label: "Camera", enabled: !viewModel.isTrimming) {
                        onShowCamera()
                    }
                    attachOptionCard(icon: "photo.fill", label: "Photos", enabled: true) {
                        onShowImagePicker()
                    }
                }
                HStack(spacing: 12) {
                    attachOptionCard(icon: "doc.on.clipboard.fill", label: "Paste", enabled: true) {
                        onPaste()
                    }
                    attachOptionCard(icon: "arrow.trianglehead.merge", label: "Track Changes Import", enabled: true) {
                        onTrackChanges()
                    }
                }

                // Visual separator between import cards (above) and
                // memory load row (below). 0.5pt matches the
                // existing card-stroke weight.
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 0.5)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                // Memory load row — four buttons, each half the width
                // of an import card and the same height. Buttons disable
                // when the slot is empty (Auto also requires the toggle
                // to be on).
                HStack(spacing: 8) {
                    memoryLoadButton(slotKey: MemorySlot.slot1)
                    memoryLoadButton(slotKey: MemorySlot.slot2)
                    memoryLoadButton(slotKey: MemorySlot.slot3)
                    memoryLoadButton(slotKey: MemorySlot.auto)
                }

                // Visual separator between memory load row (above) and
                // manage-original cards (below).
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 0.5)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                // Manage-original row.
                HStack(spacing: 12) {
                    attachOptionCard(
                        icon: "pencil",
                        label: "Edit Original",
                        enabled: viewModel.canEditOriginalFromPlusSheet
                    ) {
                        onEditOriginal()
                    }
                    attachOptionCard(
                        icon: "arrow.up.doc",
                        label: "Use Output as Original",
                        enabled: viewModel.canUseOutputAsOriginalFromPlusSheet
                    ) {
                        onUseOutputAsOriginal()
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    /// One of the four memory-load buttons. Sized at the same 80pt
    /// height as the 2x2 import cards but at half the width so all
    /// four fit on a single row. Icon: `externaldrive` for the three
    /// manual slots, `clock.arrow.circlepath` for the Auto slot. Tints
    /// `.dkSuccess` green when the slot is available; grey otherwise.
    @ViewBuilder
    private func memoryLoadButton(slotKey: String) -> some View {
        let isAuto = (slotKey == MemorySlot.auto)
        let isFilled = memory.isFilled(slotKey)
        let enabled: Bool = {
            if isAuto { return autoSaveMemory && isFilled }
            return isFilled
        }()
        let iconName: String = {
            if isAuto { return "clock.arrow.circlepath" }
            return isFilled ? "externaldrive.fill" : "externaldrive"
        }()
        let iconColor: Color = enabled ? .dkSuccess : .dkTextSecondary
        let labelColor: Color = enabled ? .dkTextPrimary : .dkTextSecondary

        Button {
            onLoadMemory(slotKey)
        } label: {
            VStack(spacing: 4) {
                Text("Load")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(labelColor)
                Image(systemName: iconName)
                    .font(.system(size: 22))
                    .foregroundColor(iconColor)
                Text(MemorySlot.displayName(for: slotKey))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(Color.dkSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        }
        .disabled(!enabled)
        .accessibilityLabel(memoryLoadAccessibilityLabel(slotKey: slotKey, enabled: enabled))
    }

    private func memoryLoadAccessibilityLabel(slotKey: String, enabled: Bool) -> String {
        let name = MemorySlot.displayName(for: slotKey)
        if !enabled {
            if slotKey == MemorySlot.auto {
                return "\(name) memory, empty or auto-save off"
            }
            return "\(name), empty"
        }
        return "Load \(name)"
    }

    private func attachOptionCard(
        icon: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 13, weight: .regular))
            }
            .foregroundColor(enabled ? .dkTextPrimary : .dkTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(Color.dkSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        }
        .disabled(!enabled)
    }
}

// MARK: - Undo / Redo Pill

/// Floating pill with undo and redo buttons, shown at the bottom of
/// the clause card on the Changes and Output tabs.
struct UndoRedoPill: View {

    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(canUndo ? .dkPrimary : Color(.systemGray4))
            }
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 1, height: 22)

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(canRedo ? .dkPrimary : Color(.systemGray4))
            }
            .disabled(!canRedo)
            .accessibilityLabel("Redo")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Analyse Pill

/// Floating pill on the Original tab that triggers Tell Me clause analysis.
/// Shows one of three states: idle ("Tell Me"), running ("Analysing…"),
/// or ready ("Analysis ready"). Icon and label change with state so the
/// user can tell at a glance whether an analysis is in progress or
/// waiting to be viewed.
struct AnalysePill: View {

    let hasCachedResult: Bool
    let isEnabled: Bool
    let isAnalysing: Bool
    let action: () -> Void

    private var iconName: String {
        if isAnalysing { return "hourglass" }
        if hasCachedResult { return "checkmark.circle.fill" }
        return "text.magnifyingglass"
    }

    private var label: String {
        if isAnalysing { return "Analysing…" }
        if hasCachedResult { return "Analysis ready" }
        return "Tell Me"
    }

    private var foreground: Color {
        if !isEnabled && !isAnalysing { return Color(.systemGray4) }
        if hasCachedResult { return .dkAccent }
        return .dkPrimary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 21, weight: .medium))
                    .symbolEffect(.pulse, options: .repeating, isActive: isAnalysing)
                Text(label)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(foreground)
        }
        .disabled(!isEnabled && !isAnalysing)
        .accessibilityLabel(label)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Lock Pill

/// Floating pill shown during the pre-lock edit phase. Becomes visible as
/// soon as the editor contains text and no Original is locked yet. Tapping
/// commits the current editor text as the Original baseline and opens the
/// Original / Show Changes / Output tabs. Disabled when fewer than 3 words
/// are in the editor.
struct LockPill: View {

    let isEnabled: Bool
    let action: () -> Void

    private var foreground: Color {
        isEnabled ? .dkPrimary : Color(.systemGray4)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 21, weight: .medium))
                Text("Lock as Original")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(foreground)
        }
        .disabled(!isEnabled)
        .accessibilityLabel("Lock as Original")
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Export Share Item

/// Identifiable wrapper so `.sheet(item:)` can bind the share items
/// directly to the sheet trigger, avoiding SwiftUI state-batching races.
struct ExportShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - UIActivityViewController Wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
