// DraftingViewComponents.swift
// Chimera Law
// Reusable subviews for the drafting screen: selectors, toggles, info sheet

import SwiftUI

// MARK: - Style Selector (Sliding Capsule)

struct StyleSelector: View {

    @Binding var selection: DraftingStyle?
    var appearDeselected: Bool = false
    @Namespace private var styleNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DraftingStyle.allCases) { style in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selection = style
                    }
                } label: {
                    let isSelected = selection == style && !appearDeselected
                    Text(style.shortLabel)
                        .font(isSelected ? .dkSubheadline.weight(.bold) : .dkSubheadline.weight(.regular))
                        .foregroundColor(isSelected ? .dkTextPrimary : .dkTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.dkPrimary.opacity(0.15))
                                        .matchedGeometryEffect(id: "styleIndicator", in: styleNamespace)
                                }
                            }
                        )
                }
                .accessibilityLabel("\(style.label) style")
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Heat Selector (Sliding Capsule)

struct HeatSelector: View {

    @Binding var selection: HeatLevel?
    var appearDeselected: Bool = false
    var compact: Bool = false
    /// Fires when the user taps the already-selected level (no binding change).
    var onReselect: (() -> Void)? = nil
    /// Returns true if the heat level is available to select. When false,
    /// the button is greyed out and disabled. Defaults to always-available
    /// so existing callers keep their behaviour.
    var isAvailable: (HeatLevel) -> Bool = { _ in true }
    @Namespace private var heatNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HeatLevel.allCases) { level in
                let available = isAvailable(level)
                Button {
                    if selection == level {
                        onReselect?()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selection = level
                        }
                    }
                } label: {
                    let isSelected = selection == level && !appearDeselected
                    Text(level.shortLabel)
                        .font(compact
                              ? .system(size: 16, weight: isSelected ? .semibold : .regular)
                              : (isSelected ? .dkSubheadline : .dkSubheadline.weight(.regular)))
                        .foregroundColor(heatLabelColor(level, isSelected: isSelected, available: available))
                        .frame(maxWidth: .infinity, minHeight: compact ? 40 : 44)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule()
                                        .fill(level.color.opacity(backgroundOpacity(for: level)))
                                        .matchedGeometryEffect(id: "heatIndicator", in: heatNamespace)
                                }
                            }
                        )
                }
                .disabled(!available)
                .accessibilityLabel("\(level.label) bias level")
            }
        }
        .padding(compact ? 2 : 3)
        .glassEffect(.regular, in: .capsule)
    }

    private func heatLabelColor(_ level: HeatLevel, isSelected: Bool, available: Bool) -> Color {
        if !available { return .dkTextSecondary.opacity(0.35) }
        return isSelected ? level.color : .dkTextSecondary
    }

    /// Stronger background for outer heat levels (I2, F2) to emphasise
    /// the gradient relative to the inner levels (I1, F1).
    private func backgroundOpacity(for level: HeatLevel) -> Double {
        switch level.shortLabel {
        case "I2", "F2": return 0.28
        case "I1", "F1": return 0.15
        default:         return 0.15
        }
    }
}

// MARK: - Info Sheet

struct DraftingInfoSheet: View {

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // MARK: - Header
                    Text("Chimera Law")
                        .font(.dkHeadline)
                        .foregroundColor(.dkPrimary)

                    Text("Built for German venture-capital clauses. AI redrafting, word-level change tracking, and clause analysis across the seven deal stages.")
                        .font(.dkBody)

                    // MARK: - Quick Start
                    Divider()
                    sectionTitle("How It Works")
                    stepRow(number: "1", title: "Import", detail: "Paste, type, upload a screenshot or image, photograph your clause, or load a saved memory slot.")
                    stepRow(number: "2", title: "Analyse", detail: "Tap the Tell Me button to understand bias, risk, and market position.")
                    stepRow(number: "3", title: "Redraft", detail: "Choose a bias level to generate five AI variants instantly.")
                    stepRow(number: "4", title: "Edit", detail: "Refine the output manually. Every change is tracked.")
                    stepRow(number: "5", title: "Export", detail: "Share as text, Word, or PDF -- including a full redline.")

                    // MARK: - Tell Me (prominent)
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.dkAccent)
                        Text("Tell Me -- Clause Analysis")
                            .font(.dkSubheadline)
                            .foregroundColor(.dkAccent)
                    }

                    Text("A comprehensive AI analysis of your venture-capital clause, available on the Original tab after redrafting. Tap the magnifying glass pill at the bottom of the editor.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    VStack(alignment: .leading, spacing: 6) {
                        tellMeRow("Dashboard", "Visual summary of Bias, Risk Level, and Market Standard.")
                        tellMeRow("Bias Assessment", "How the clause favours founder or investor.")
                        tellMeRow("Risk Flags", "Dilution, control, tax leakage, and deal-blocker risks.")
                        tellMeRow("Typical Deviations", "Where the clause diverges from BVK / NVCA market practice.")
                        tellMeRow("Market Standard", "How typical the wording is at this deal stage.")
                        tellMeRow("Related Clauses", "Cross-references across Term Sheet, Beteiligungsvertrag, GV, and Satzung.")
                        tellMeRow("Purpose & Relevance", "What the clause does in a financing round and why it matters.")
                        tellMeRow("Historical Predecessors", "NVCA-to-Germany adoption path and BVK standardisation.")
                    }

                    Text("Tell Me is stage-aware and uses the active deal-stage persona. Results are cached -- tap the button again to recall them. Export as a separate PDF via the export menu.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    // MARK: - Import
                    Divider()
                    sectionTitle("Importing Text")
                    toolRow("camera.fill", "Camera -- Photograph a clause; text is read automatically")
                    toolRow("photo.fill", "Photos -- Select a screenshot or image; text is read automatically")
                    toolRow("doc.on.clipboard.fill", "Paste -- Import from your clipboard")
                    toolRow("arrow.trianglehead.merge", "Track Changes -- Import a screenshot of a Word document with tracked changes")
                    toolRow("externaldrive.fill", "Memory -- Load a saved draft from Memory 1, 2, 3, or Auto")
                    toolRow("pencil", "Edit Original -- Edit the locked baseline")
                    toolRow("arrow.up.doc", "Use Output as Original -- Replace the locked baseline with your current Output")
                    Text("Camera, photo, and track changes import are also available as home screen quick actions (long-press the app icon).")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    // MARK: - AI Redrafting
                    Divider()
                    sectionTitle("AI Redrafting")
                    Text("Chimera Law gives you two main ways to redraft a clause. They use different starting points and produce different kinds of output, and they do not interact: tapping a bias level ignores the Additional Instructions field, and sending an instruction does not pick a bias level. There is also a third entry point — Revise, which surfaces concrete revisions drawn from the Tell Me analysis.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    Text("Pull down the grabber bar at the top of the editor to reveal the bias and style controls. The Additional Instructions field sits at the bottom of the editor, with its own Send button.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    Text("Bias")
                        .font(.dkCaption).fontWeight(.semibold).foregroundColor(.dkTextPrimary)
                    Text("Controls founder/investor orientation. Tap any pill to redraft the clause at that bias level. All five variants are generated in one call so switching between them is instant. The bias selector ignores anything you have typed in the Additional Instructions field -- those two flows are separate.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("Starting point: the current Output (or the locked Original if you have not redrafted yet). Result: a fresh set of bias-leaning variants.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    ForEach(HeatLevel.allCases) { level in
                        HStack(spacing: 10) {
                            Text(level.shortLabel)
                                .font(.dkMono.weight(.bold))
                                .foregroundColor(level.color)
                                .frame(width: 32, alignment: .leading)
                            Text(level.infoDescription)
                                .font(.dkCaption)
                                .foregroundColor(.dkTextSecondary)
                        }
                    }

                    Text("Stages")
                        .font(.dkCaption).fontWeight(.semibold).foregroundColor(.dkTextPrimary)
                    Text("Seven deal-stage personas that reshape tone, structure, and terminology — from term sheet through priced rounds and convertibles to secondary / exit work, with a cross-border NVCA overlay and a plain-language re-skin.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    ForEach(DraftingStyle.allCases) { style in
                        HStack(alignment: .top, spacing: 10) {
                            Text(style.shortLabel)
                                .font(.dkMono.weight(.bold))
                                .foregroundColor(.dkPrimary)
                                .frame(width: 56, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.label)
                                    .font(.dkCaption).fontWeight(.medium)
                                Text(style.infoDescription)
                                    .font(.dkCaption)
                                    .foregroundColor(.dkTextSecondary)
                            }
                        }
                    }

                    Text("Additional Instructions")
                        .font(.dkCaption).fontWeight(.semibold).foregroundColor(.dkTextPrimary)
                    Text("Tell Chimera Law how to change the clause — for example, \"add a co-investor\", \"add a fair-value floor\", or \"shorten it\". Chimera Law rewrites to follow your instruction, building on the latest version each time. Keep it short and on-topic; if the instruction is too long or asks for something other than a redraft, Chimera Law will say so and you can adjust.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    Text("Revise")
                        .font(.dkCaption).fontWeight(.semibold).foregroundColor(.dkTextPrimary)
                    Text("After Tell Me has analysed your clause, the grabber bar above the tabs turns indigo. Pull down the drawer and tap \"Revise\" to see concrete revisions drawn from the analysis, organised into three groups: Risk Flags, Absent Components, and Typical Deviations. Risk Flags and Typical Deviations show up to five revisions each; Absent Components shows up to ten.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("Each card shows the finding from the analysis on top and a short instruction below. Tap a card and the instruction is sent through Additional Instructions automatically -- anything you have typed in that field will be replaced, the bias selection will reset, and the redraft will chain from the current Output, exactly as if you had typed the instruction yourself.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("If you tap Revise before running Tell Me, Chimera Law starts the analysis straight away in the background. A short note appears to let you know -- once you dismiss it, you can carry on editing the clause. The grabber bar at the top of the editor pulses while Chimera Law is working, so you always know something is in progress. When the revisions are ready, the sheet opens automatically -- unless you are typing, in which case a small \"Revise \u{2014} ready\" banner appears so you can finish your thought before opening it.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("Revisions are cached for the life of the analysis. Cards you have already applied are greyed out but stay tappable.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    // MARK: - Change Tracking
                    Divider()
                    sectionTitle("Change Tracking")
                    Text("Switch between Original, Changes, and Output using the tabs or by swiping.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    VStack(alignment: .leading, spacing: 4) {
                        changeRow(Color.blue, "AI additions (underlined)")
                        changeRow(Color.red, "AI deletions (strikethrough)")
                        changeRow(Color(hex: "6D8A6F"), "Your additions")
                        changeRow(Color(hex: "600000"), "Your deletions")
                        changeRow(Color.orange, "AI added, then you deleted")
                    }

                    Text("Tap any marked change in the Changes view to revert it.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    Text("Undo / Redo")
                        .font(.dkCaption).fontWeight(.semibold).foregroundColor(.dkTextPrimary)
                    Text("A floating undo/redo pill on the Changes and Output tabs covers one shared history -- typing, AI rephrases, bias taps, and Revise taps. Up to 50 steps. An in-flight AI call is cancelled when you tap undo. The chain resets on fresh starts (lock, Edit Original, Use Output as Original, import overwrite, Show as Redline, Discard & Rephrase, memory load, New).")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    // MARK: - Track Changes Import
                    Divider()
                    sectionTitle("Track Changes Import")
                    Text("Import a screenshot of a Word document showing track changes. Chimera Law reads the markup and lets you choose how to handle it: import as plain text, accept all changes, reject all changes, or view the redline in the Changes tab.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("Tap the plus button and select \"Track Changes\", or long-press the app icon and choose \"Import Track Changes\". Only Microsoft Word conventions are supported (strikethrough for deletions, coloured underline for insertions).")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    // MARK: - Locking the Original
                    Divider()
                    sectionTitle("Locking the Original")
                    Text("As soon as text appears in the Original field, a \"Lock as Original\" pill shows at the bottom of the editor. Edit the text freely, then tap the pill when the baseline is ready. The Original, Show Changes, and Output tabs become active at that moment. If the text is good as-is, tap the pill straight away.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("A minimum of three words is required to lock; the pill stays disabled below that. Locking clears any pre-lock edit history. The Original is fixed once committed. To edit it, either long-press the Original tab text or open the plus button and pick \"Edit Original\". Confirm in the popup; this clears Tell Me, bias variants, and Revise, but keeps your Output. Tap the Lock pill when you are done editing.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("In detail: \"Edit Original\" is reachable two ways \u{2014} long-press the Original-tab text (which surfaces an \"Edit Original\u{2026}\" menu item) or tap the plus button and choose \"Edit Original\". The confirmation popup is titled \"Edit Original?\" with two buttons, \"Cancel\" and \"Go\". While you are editing, the Changes and Output tabs are temporarily disabled, the bias and instruction controls are inactive, and the editor returns to its untinted, pre-lock appearance. VoiceOver users reach the long-press option through the context-menu rotor. The plus button also offers \"Use Output as Original\", which promotes the current Output to the locked baseline and clears Tell Me, bias variants, and Revise; the Output text replaces the Original on both tabs and Show Changes resets to a clean baseline.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    // MARK: - Memory
                    Divider()
                    sectionTitle("Memory")
                    Text("Save and reload your working draft on this device. Three manual slots plus an optional auto-save slot. Nothing is uploaded.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("Save")
                        .font(.dkCaption).fontWeight(.semibold).foregroundColor(.dkTextPrimary)
                    Text("Tap the external-drive icon in the top toolbar. The sheet shows three slots. A green outline means the slot is empty (safe to save); a red outline means it is filled (tap will ask you to confirm an overwrite). Filled rows preview the saved Original and the save date.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("Load")
                        .font(.dkCaption).fontWeight(.semibold).foregroundColor(.dkTextPrimary)
                    Text("Open the plus button. Between the import grid and the manage-original row sits a row of four cards: Memory 1, Memory 2, Memory 3, and Auto. Tinted green when filled, grey when empty. Tap to load. If you have unsaved changes, you are asked to confirm before the current draft is replaced.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("Auto-save")
                        .font(.dkCaption).fontWeight(.semibold).foregroundColor(.dkTextPrimary)
                    Text("Off by default. Enable in Settings under Memory. When on, the Auto slot updates in the background as you edit. Turning it off clears the Auto slot only -- Memory 1, 2, and 3 are not touched.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                    Text("Wipe")
                        .font(.dkCaption).fontWeight(.semibold).foregroundColor(.dkTextPrimary)
                    Text("Settings -> Memory -> Wipe all memory clears every slot after confirmation.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)

                    // MARK: - Toolbar Reference
                    Divider()
                    sectionTitle("Toolbar")
                    toolRow("plus", "Import, load a memory slot, or manage the Original")
                    toolRow("microphone", "Dictate additional instructions")
                    toolRow("square.and.pencil", "Clear and start fresh")
                    toolRow("externaldrive", "Save the current draft to a memory slot")
                    toolRow("square.and.arrow.up", "Share as text, copy, or export as Word / PDF")
                    toolRow("gear", "Style, appearance, API key, subscription, memory")

                    // MARK: - Footer
                    Divider()
                    Text("Inputs are not saved on our servers. Character limit: 5,000.")
                        .font(.dkCaption).foregroundColor(.dkTextSecondary)
                }
                .padding(DKLayout.screenPadding)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.font(.dkBody)
                }
            }
        }
    }

    // MARK: - Helper Views

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.dkSubheadline)
            .foregroundColor(.dkPrimary)
    }

    private func toolRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.dkPrimary)
                .frame(width: 24)
            Text(text)
                .font(.dkCaption)
                .foregroundColor(.dkTextSecondary)
        }
    }

    private func stepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.dkMono.weight(.bold))
                .foregroundColor(.dkPrimary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dkCaption).fontWeight(.semibold)
                Text(detail)
                    .font(.dkCaption)
                    .foregroundColor(.dkTextSecondary)
            }
        }
    }

    private func tellMeRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("--")
                .font(.dkCaption)
                .foregroundColor(.dkAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.dkCaption).fontWeight(.medium)
                Text(detail)
                    .font(.dkCaption)
                    .foregroundColor(.dkTextSecondary)
            }
        }
    }

    private func changeRow(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.dkCaption)
                .foregroundColor(.dkTextSecondary)
        }
    }
}
