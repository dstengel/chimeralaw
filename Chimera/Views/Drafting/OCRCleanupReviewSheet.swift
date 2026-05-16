// OCRCleanupReviewSheet.swift
// Chimera Law
//
// Sheet opened when the user taps "Yes" on "Do you want to review the clean-up
// result first?" It replaces the previous approach of routing through the full
// three-tab redline engine.
//
// States:
//   • Loading — API call is still in flight; spinner shown.
//   • Diff    — Inline word-level diff; every word is tappable. AI changes
//               (red strikethrough / blue underline / substitution pairs)
//               revert on tap. AI-untouched words toggle a user-deletion mark
//               (single amber strikethrough) on tap. The same renderer is
//               used when the AI made zero changes — a context-aware caption
//               distinguishes the two cases.
//
// Segment types in the diff:
//   • .unchanged  — word present in both; tap to mark/unmark for user deletion.
//   • .removed    — word in raw OCR, deleted by AI; tap to restore.
//   • .inserted   — word added by AI; tap to remove.
//   • .substitution — adjacent delete+insert pair; tap either chip to swap back.
//   • .newline    — paragraph break; used to split into flow-layout paragraphs.
//
// Accept → commitOCRCleanupFromSheet(finalText:userChoseEmpty:) lands the
//          cleaned text (minus reverted AI insertions and user-deleted words)
//          in the editor as a pre-lock draft. The user reviews / edits and
//          then taps the Lock pill to commit it as Original.
//          `userChoseEmpty` distinguishes a deliberate empty result from the
//          defensive rawText fallback for AI-returned-empty.
// Discard → discardOCRCleanupFromSheet() keeps raw OCR text, no tab change.

import SwiftUI

// MARK: - Sheet

struct OCRCleanupReviewSheet: View {

    @ObservedObject var viewModel: DraftingViewModel

    // MARK: Local state

    @State private var segments: [CleanupSegment] = []
    @State private var revertedIds: Set<UUID> = []
    /// Ids of `.unchanged` segments the user has tapped to mark for deletion.
    /// Independent of `revertedIds` (which only carries AI-change ids).
    @State private var userDeletedIds: Set<UUID> = []
    /// Guard against re-running buildSegments when the cleaned text hasn't changed.
    @State private var lastComputedCleaned: String? = nil

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.ocrReviewCleanedText == nil {
                    loadingView
                } else {
                    // Uniform diff renderer. When the AI made zero changes,
                    // every segment is .unchanged (plus .newline) and the
                    // user can still tap any word to mark it for deletion.
                    diffScrollView
                }
            }
            .navigationTitle("Review Clean-Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        viewModel.discardOCRCleanupFromSheet()
                    }
                    .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept") {
                        let final = buildFinalText()
                        // `userActed` proves the user touched at least one
                        // chip or word during the review session. An empty
                        // `final` with `userActed == true` is a deliberate
                        // delete-everything choice; an empty `final` with
                        // `userActed == false` falls back to raw OCR in the
                        // view-model (defensive — AI-returned-empty case).
                        let userActed =
                            !userDeletedIds.isEmpty || !revertedIds.isEmpty
                        viewModel.commitOCRCleanupFromSheet(
                            finalText: final,
                            userChoseEmpty: final.isEmpty && userActed
                        )
                    }
                    .foregroundColor(.dkAccent)
                    .fontWeight(.semibold)
                    .disabled(viewModel.ocrReviewCleanedText == nil)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear { recomputeIfNeeded() }
        .onChange(of: viewModel.ocrReviewCleanedText) { _, _ in recomputeIfNeeded() }
    }

    // MARK: Recompute segments

    private func recomputeIfNeeded() {
        guard let cleaned = viewModel.ocrReviewCleanedText,
              cleaned != lastComputedCleaned else { return }
        segments = buildSegments(raw: viewModel.ocrReviewRawText, cleaned: cleaned)
        // Both id sets are scoped to the current `segments` array. When the
        // cleaned text identity changes, the previous UUIDs are stale and must
        // be cleared. Clearing `revertedIds` here also fixes a latent bug
        // (previously the set survived recompute with no matching ids).
        revertedIds.removeAll()
        userDeletedIds.removeAll()
        lastComputedCleaned = cleaned
    }

    // MARK: Loading view

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Cleaning up text with AI\u{2026}")
                .font(.dkBody)
                .foregroundColor(.dkTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Diff scroll view

    private var diffScrollView: some View {
        // True iff the segments contain at least one AI-change cell.
        // Zero AI changes is the path users land on when the AI returned text
        // identical to raw OCR but the user still tapped Yes on the prompt.
        let hasAIChanges = segments.contains { seg in
            switch seg {
            case .removed, .inserted, .substitution: true
            case .unchanged, .newline:               false
            }
        }
        let captionText: String =
            hasAIChanges
            ? "Tap an AI change (red or blue) to revert it. Tap any other word to mark it for deletion (amber strikethrough)."
            : "AI made no changes. Tap any word to mark it for deletion (amber strikethrough)."

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Label(captionText, systemImage: "hand.tap")
                    .font(.dkCaption)
                    .foregroundColor(.dkTextSecondary)

                // Split into paragraphs; each rendered in its own flow layout row.
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                        CleanupFlowLayout(spacing: 5) {
                            ForEach(para) { seg in
                                segmentView(seg)
                            }
                        }
                    }
                }
            }
            .padding(DKLayout.screenPadding)
        }
    }

    // MARK: Paragraph splitting

    private var paragraphs: [[CleanupSegment]] {
        var result: [[CleanupSegment]] = [[]]
        for seg in segments {
            if case .newline = seg {
                result.append([])
            } else {
                result[result.count - 1].append(seg)
            }
        }
        return result.filter { !$0.isEmpty }
    }

    // MARK: Per-segment view

    @ViewBuilder
    private func segmentView(_ segment: CleanupSegment) -> some View {
        switch segment {

        case .unchanged(let id, let text):
            let deleted = userDeletedIds.contains(id)
            Button { toggleUserDelete(id) } label: {
                Text(text)
                    .font(.dkBody)
                    .strikethrough(deleted, color: .dkAccent)
                    .foregroundColor(deleted ? Color.dkAccent.opacity(0.6) : .primary)
                    .padding(.horizontal, deleted ? 3 : 0)
                    .padding(.vertical, deleted ? 2 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(deleted
                                  ? Color.dkAccent.opacity(0.18)
                                  : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(deleted ? "\(text), marked for deletion" : "\(text), kept")
            .accessibilityHint(deleted ? "Double tap to keep" : "Double tap to delete")
            .animation(.easeInOut(duration: 0.12), value: deleted)

        case .newline:
            EmptyView()

        case .removed(let id, let text):
            let reverted = revertedIds.contains(id)
            Button { toggle(id) } label: {
                Text(text)
                    .font(.dkBody)
                    .strikethrough(!reverted, color: .red)
                    .foregroundColor(reverted ? .primary : Color.red.opacity(0.75))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(reverted
                                  ? Color.dkAccent.opacity(0.08)
                                  : Color.red.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.12), value: reverted)

        case .inserted(let id, let text):
            let reverted = revertedIds.contains(id)
            Button { toggle(id) } label: {
                Text(text)
                    .font(.dkBody)
                    .strikethrough(reverted, color: .red)
                    .underline(!reverted, color: .blue)
                    .foregroundColor(reverted ? Color.secondary.opacity(0.45) : .blue)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(reverted
                                  ? Color.red.opacity(0.05)
                                  : Color.blue.opacity(0.07))
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.12), value: reverted)

        case .substitution(let id, let old, let new):
            // Both chips share the same toggle ID — tapping either reverts the whole pair.
            let reverted = revertedIds.contains(id)
            HStack(spacing: 2) {
                // Old word: strikethrough when the AI substitution is active (not reverted).
                Button { toggle(id) } label: {
                    Text(old)
                        .font(.dkBody)
                        .strikethrough(!reverted, color: .red)
                        .foregroundColor(!reverted ? Color.red.opacity(0.75) : .primary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                // New word: blue underline when active; dimmed strikethrough when reverted.
                Button { toggle(id) } label: {
                    Text(new)
                        .font(.dkBody)
                        .strikethrough(reverted, color: .red)
                        .underline(!reverted, color: .blue)
                        .foregroundColor(reverted ? Color.secondary.opacity(0.45) : .blue)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
            }
            .animation(.easeInOut(duration: 0.12), value: reverted)
        }
    }

    // MARK: Toggle helpers

    /// Toggles an AI-change chip's revert state. Used by .removed / .inserted /
    /// .substitution cells.
    private func toggle(_ id: UUID) {
        if revertedIds.contains(id) { revertedIds.remove(id) }
        else                        { revertedIds.insert(id) }
    }

    /// Toggles user-deletion mark on an AI-untouched (`.unchanged`) cell.
    private func toggleUserDelete(_ id: UUID) {
        if userDeletedIds.contains(id) { userDeletedIds.remove(id) }
        else                           { userDeletedIds.insert(id) }
    }

    // MARK: Build final text

    private func buildFinalText() -> String {
        // Walk segments paragraph-by-paragraph. `.unchanged` words are skipped
        // when in `userDeletedIds`; AI chips honour `revertedIds` as before.
        // Within a paragraph, surviving tokens are rejoined with single spaces
        // (each token is whitespace-free by construction). Paragraphs whose
        // every token was deleted/reverted-out collapse — their newline is
        // dropped. This is a deliberate v1 simplification (see plan §5/§9.4).
        var paragraphTexts: [String] = []
        var currentWords: [String] = []

        for segment in segments {
            switch segment {
            case .unchanged(let id, let text):
                if !userDeletedIds.contains(id) { currentWords.append(text) }
            case .newline:
                paragraphTexts.append(currentWords.joined(separator: " "))
                currentWords = []
            case .removed(let id, let text):
                if revertedIds.contains(id) { currentWords.append(text) }
            case .inserted(let id, let text):
                if !revertedIds.contains(id) { currentWords.append(text) }
            case .substitution(let id, let old, let new):
                currentWords.append(revertedIds.contains(id) ? old : new)
            }
        }
        // Flush trailing paragraph.
        paragraphTexts.append(currentWords.joined(separator: " "))

        // Defensive trim per paragraph; drop wholly empty paragraphs (v1).
        let trimmed = paragraphTexts.map { $0.trimmingCharacters(in: .whitespaces) }
        let nonEmpty = trimmed.filter { !$0.isEmpty }
        return nonEmpty.joined(separator: "\n")
    }
}

// MARK: - Segment model

private extension OCRCleanupReviewSheet {

    enum CleanupSegment: Identifiable {
        case unchanged(id: UUID, text: String)
        case removed(id: UUID, text: String)
        case inserted(id: UUID, text: String)
        case substitution(id: UUID, old: String, new: String)
        case newline(id: UUID)

        var id: UUID {
            switch self {
            case .unchanged(let id, _):       id
            case .removed(let id, _):         id
            case .inserted(let id, _):        id
            case .substitution(let id, _, _): id
            case .newline(let id):            id
            }
        }
    }

    /// Sentence terminators that always split. CJK fullwidth `。！？` and
    /// ASCII `!` `?` (the latter never appear inside numbers). The ASCII `.`
    /// is conditional and handled inline in `splitOnSentenceTerminators`.
    static var unconditionalTerminators: Set<Character> {
        ["!", "?", "\u{3002}", "\u{FF01}", "\u{FF1F}"]
    }

    /// Splits a non-whitespace token at sentence boundaries. The terminator
    /// stays with the token that precedes it. The conditional `.` rule keeps
    /// decimals (`3.14`), currency (`$1,234.56`), section numbers (`4.1.2`),
    /// and percentages (`5.5%`) intact — `.` only splits when followed by
    /// whitespace, end-of-token, or another sentence terminator. CJK and
    /// ASCII `!` `?` are unconditional.
    static func splitOnSentenceTerminators(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let isLast = (i == chars.count - 1)
            let nextIsTerminatorOrEnd: Bool = {
                if isLast { return true }
                let n = chars[i + 1]
                return n.isWhitespace
                    || Self.unconditionalTerminators.contains(n)
                    || n == "."
            }()
            let shouldSplit: Bool
            if Self.unconditionalTerminators.contains(ch) {
                shouldSplit = true
            } else if ch == "." {
                shouldSplit = nextIsTerminatorOrEnd
            } else {
                shouldSplit = false
            }
            if shouldSplit && !isLast {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.isEmpty ? [text] : pieces
    }

    /// Converts a two-way word diff into display segments.
    /// Adjacent (deleted, inserted) token pairs become .substitution to keep
    /// the linked-toggle semantics consistent.
    func buildSegments(raw: String, cleaned: String) -> [CleanupSegment] {
        let tokens = WordDiff.diff(old: raw, new: cleaned)
        var result: [CleanupSegment] = []
        var i = 0
        while i < tokens.count {
            let token = tokens[i]

            // Adjacent delete+insert (neither a newline) → substitution pair.
            if token.type == .deleted,
               !WordDiff.isNewline(token.text),
               i + 1 < tokens.count,
               tokens[i + 1].type == .inserted,
               !WordDiff.isNewline(tokens[i + 1].text) {
                result.append(.substitution(id: UUID(),
                                            old: token.text,
                                            new: tokens[i + 1].text))
                i += 2
                continue
            }

            switch token.type {
            case .equal:
                if WordDiff.isNewline(token.text) {
                    result.append(.newline(id: UUID()))
                } else {
                    // Sheet-local sentence-terminator split. Splits CJK
                    // paragraphs into per-sentence cells and surfaces ASCII
                    // sentence boundaries that whitespace-tokenisation already
                    // covers without affecting decimals / currency / section
                    // numbers (conditional `.` rule). Applied only here so
                    // WordDiff.tokenize itself stays untouched.
                    for piece in Self.splitOnSentenceTerminators(token.text) {
                        result.append(.unchanged(id: UUID(), text: piece))
                    }
                }
            case .deleted:
                if !WordDiff.isNewline(token.text) {
                    result.append(.removed(id: UUID(), text: token.text))
                }
                // Deleted newlines are silently dropped; paragraph structure
                // is preserved by equal-newline tokens alone.
            case .inserted:
                if WordDiff.isNewline(token.text) {
                    result.append(.newline(id: UUID()))
                } else {
                    result.append(.inserted(id: UUID(), text: token.text))
                }
            }
            i += 1
        }
        return result
    }
}

// MARK: - Flow layout (word-wrapping, no newline handling needed here)

/// Simple left-to-right wrapping layout. Newlines are handled by splitting
/// segments into paragraphs before rendering; this layout is per-paragraph.
private struct CleanupFlowLayout: Layout {

    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        arrange(subviews: subviews, in: proposal.replacingUnspecifiedDimensions().width).size
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let result = arrange(subviews: subviews, in: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: frame.minX + bounds.minX,
                            y: frame.minY + bounds.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat) -> ArrangeResult {
        var result = ArrangeResult()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let s = subview.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            result.frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }

        result.size = CGSize(width: maxWidth, height: y + rowHeight)
        return result
    }
}
