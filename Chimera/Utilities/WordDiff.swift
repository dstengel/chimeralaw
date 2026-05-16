// WordDiff.swift
// Chimera Law
// Word-level diff between two or three text layers using Myers' algorithm.

import Foundation

// MARK: - Diff Token

enum DiffTokenType {
    case equal
    case inserted
    case deleted
}

/// Who produced this change: the AI rephrase or the user's manual edit.
enum DiffTokenSource {
    case ai
    case user
    /// AI inserted the word, then the user deleted it. Net effect: absent
    /// from output. Rendered as orange strikethrough in the diff view.
    case aiThenUser
}

struct DiffToken: Identifiable {
    let id: UUID
    let text: String
    let type: DiffTokenType
    /// Contiguous changed tokens share the same groupId for batch revert.
    let groupId: UUID?
    /// Whether this change was produced by the AI or the user.
    let source: DiffTokenSource?

    init(text: String, type: DiffTokenType, groupId: UUID? = nil, source: DiffTokenSource? = nil) {
        self.id = UUID()
        self.text = text
        self.type = type
        self.groupId = groupId
        self.source = source
    }
}

// MARK: - Word Diff

enum WordDiff {

    // MARK: - Two-Layer Diff (Original → Current)

    /// Simple two-layer diff. Used when no AI output snapshot exists.
    static func diff(old oldText: String, new newText: String) -> [DiffToken] {
        let raw = rawDiff(old: tokenize(oldText), new: tokenize(newText), source: .ai)
        return assignGroupIds(raw)
    }

    // MARK: - Three-Layer Diff (Original → AI Output → Current)

    /// Produces a merged diff showing both AI changes and user changes.
    ///
    /// The result interleaves tokens from two diffs:
    ///   1. Original → AI Output  (AI changes, shown in standard blue/red)
    ///   2. AI Output → Current   (User changes, shown in dark blue/dark red)
    ///
    /// Equal regions that are shared across all three layers are emitted once.
    /// Where the AI changed something and the user then changed it further,
    /// all intermediate steps are shown sequentially (full history).
    static func threeLayerDiff(original: String, aiOutput: String, current: String) -> [DiffToken] {
        let originalWords = tokenize(original)
        let aiWords = tokenize(aiOutput)
        let currentWords = tokenize(current)

        // Diff 1: Original → AI Output
        let aiDiff = rawDiff(old: originalWords, new: aiWords, source: .ai)
        // Diff 2: AI Output → Current
        let userDiff = rawDiff(old: aiWords, new: currentWords, source: .user)

        // Merge: walk the AI diff. For each AI token that survives into the
        // AI output (equal or inserted), check whether the user changed it.
        var merged: [DiffToken] = []

        // Index into userDiff. We consume user-diff tokens as we encounter
        // the corresponding AI-output words.
        var userIdx = 0

        for aiToken in aiDiff {
            switch aiToken.type {
            case .deleted:
                // Word was in Original but removed by AI. Emit as AI deletion.
                merged.append(DiffToken(text: aiToken.text, type: .deleted, source: .ai))

            case .equal, .inserted:
                // This word exists in the AI output. Advance through the user
                // diff to find the corresponding entry.

                // First, emit any user insertions that come before this position.
                while userIdx < userDiff.count && userDiff[userIdx].type == .inserted {
                    merged.append(DiffToken(text: userDiff[userIdx].text, type: .inserted, source: .user))
                    userIdx += 1
                }

                if userIdx < userDiff.count {
                    let userToken = userDiff[userIdx]

                    if userToken.type == .equal {
                        // User kept this word unchanged.
                        if aiToken.type == .equal {
                            // Unchanged across all three layers.
                            merged.append(DiffToken(text: aiToken.text, type: .equal))
                        } else {
                            // AI inserted this word, user kept it.
                            merged.append(DiffToken(text: aiToken.text, type: .inserted, source: .ai))
                        }
                        userIdx += 1
                    } else if userToken.type == .deleted {
                        // User deleted this AI-output word.
                        if aiToken.type == .equal {
                            // Was in original, kept by AI, deleted by user.
                            merged.append(DiffToken(text: aiToken.text, type: .deleted, source: .user))
                        } else {
                            // AI inserted it, user then deleted it.
                            // Net effect: word is absent from output.
                            // Show as a single deletion with .aiThenUser source
                            // (rendered as orange strikethrough).
                            merged.append(DiffToken(text: aiToken.text, type: .deleted, source: .aiThenUser))
                        }
                        userIdx += 1

                        // Emit any user insertions that follow this deletion
                        // (replacement pattern: delete old + insert new).
                        while userIdx < userDiff.count && userDiff[userIdx].type == .inserted {
                            merged.append(DiffToken(text: userDiff[userIdx].text, type: .inserted, source: .user))
                            userIdx += 1
                        }
                    } else {
                        // userToken is .inserted — already handled above, but
                        // as safety, just emit the AI token.
                        if aiToken.type == .equal {
                            merged.append(DiffToken(text: aiToken.text, type: .equal))
                        } else {
                            merged.append(DiffToken(text: aiToken.text, type: .inserted, source: .ai))
                        }
                    }
                } else {
                    // No more user-diff tokens; emit AI token as-is.
                    if aiToken.type == .equal {
                        merged.append(DiffToken(text: aiToken.text, type: .equal))
                    } else {
                        merged.append(DiffToken(text: aiToken.text, type: .inserted, source: .ai))
                    }
                }
            }
        }

        // Emit remaining user insertions at the end.
        while userIdx < userDiff.count {
            let t = userDiff[userIdx]
            if t.type != .equal {
                merged.append(DiffToken(text: t.text, type: t.type, source: .user))
            }
            userIdx += 1
        }

        return assignGroupIds(merged)
    }

    // MARK: - Simple Two-Way Diff (Original → Current, no attribution)

    /// Two-way diff of original vs current text.
    /// Produces .equal, .inserted(source: nil), .deleted(source: nil) tokens.
    /// No AI/user attribution. No phantom cancellation issues.
    /// Used for all exports and the default Simple view.
    static func simpleDiff(original: String, current: String) -> [DiffToken] {
        let old = tokenize(original)
        let new = tokenize(current)

        let changes = new.difference(from: old)

        var removedOffsets = Set<Int>()
        var insertedMap: [Int: String] = [:]

        for change in changes {
            switch change {
            case .remove(let offset, _, _):
                removedOffsets.insert(offset)
            case .insert(let offset, let element, _):
                insertedMap[offset] = element
            }
        }

        var result: [DiffToken] = []
        var oldIdx = 0
        var newIdx = 0

        while oldIdx < old.count || newIdx < new.count {
            if newIdx < new.count, insertedMap[newIdx] != nil {
                result.append(DiffToken(text: new[newIdx], type: .inserted, source: nil))
                newIdx += 1
                continue
            }
            if oldIdx < old.count, removedOffsets.contains(oldIdx) {
                result.append(DiffToken(text: old[oldIdx], type: .deleted, source: nil))
                oldIdx += 1
                continue
            }
            if oldIdx < old.count && newIdx < new.count {
                result.append(DiffToken(text: old[oldIdx], type: .equal))
                oldIdx += 1
                newIdx += 1
            } else {
                break
            }
        }

        return assignGroupIds(result)
    }

    // MARK: - Newline Sentinel

    /// Sentinel value used in the token array to represent a paragraph break.
    /// The diff algorithm treats it as a regular token (so added/removed
    /// newlines are tracked), while the DiffView and text-reconstruction
    /// methods recognise it and emit a line break instead of a space.
    static let newlineSentinel = "\u{2029}" // paragraph separator character

    /// Returns true if a token text is the newline sentinel.
    static func isNewline(_ text: String) -> Bool {
        text == newlineSentinel
    }

    // MARK: - Reconstruct Text

    /// Reconstructs the "current" text: equal + inserted tokens, excluding deleted.
    /// Newline sentinels are converted back to actual newlines.
    static func currentText(from tokens: [DiffToken]) -> String {
        var result = ""
        var needsSpace = false
        for token in tokens where token.type != .deleted {
            if isNewline(token.text) {
                result += "\n"
                needsSpace = false
            } else {
                if needsSpace { result += " " }
                result += token.text
                needsSpace = true
            }
        }
        return result
    }

    /// Reconstructs the effective AI output from diff tokens after user reverts.
    /// Includes: equal tokens, AI insertions (not reverted), user deletions
    /// (word was in AI output but user removed it).
    /// Excludes: AI deletions (not reverted), user insertions, aiThenUser
    /// deletions (AI added it, user removed it — should not reappear).
    /// This lets reverted AI changes stay "baked in" across tab switches.
    static func effectiveAiOutput(from tokens: [DiffToken]) -> String {
        let filtered = tokens.filter { token in
            switch token.type {
            case .equal:
                return true
            case .inserted:
                return token.source == .ai
            case .deleted:
                // User deletions of original words are in the AI output.
                // But aiThenUser deletions (AI inserted, user removed) should
                // be excluded so they don't resurface on recompute.
                return token.source == .user
            }
        }
        var result = ""
        var needsSpace = false
        for token in filtered {
            if isNewline(token.text) {
                result += "\n"
                needsSpace = false
            } else {
                if needsSpace { result += " " }
                result += token.text
                needsSpace = true
            }
        }
        return result
    }

    // MARK: - Private

    /// Tokenizes text into words with newline sentinels preserving paragraph breaks.
    /// Splits on newlines first, then words within each line. A newline sentinel
    /// is inserted between paragraphs. Consecutive blank lines produce one sentinel.
    static func tokenize(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var tokens: [String] = []
        var previousLineHadContent = false

        for line in lines {
            let words = line.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
                .map(String.init)

            if words.isEmpty {
                // Blank line — only emit a sentinel if we had content before
                // (avoids leading sentinels or double sentinels).
                if previousLineHadContent {
                    tokens.append(newlineSentinel)
                    previousLineHadContent = false
                }
            } else {
                // Non-blank line after content — emit sentinel for line break.
                if previousLineHadContent {
                    tokens.append(newlineSentinel)
                }
                tokens.append(contentsOf: words)
                previousLineHadContent = true
            }
        }

        return tokens
    }

    /// Raw two-array diff using CollectionDifference (Myers algorithm).
    /// Returns unmerged tokens without group IDs.
    private static func rawDiff(old: [String], new: [String], source: DiffTokenSource) -> [DiffToken] {
        let changes = new.difference(from: old)

        var removedOffsets = Set<Int>()
        var insertedMap: [Int: String] = [:]

        for change in changes {
            switch change {
            case .remove(let offset, _, _):
                removedOffsets.insert(offset)
            case .insert(let offset, let element, _):
                insertedMap[offset] = element
            }
        }

        var result: [DiffToken] = []
        var oldIdx = 0
        var newIdx = 0

        while oldIdx < old.count || newIdx < new.count {
            if newIdx < new.count, insertedMap[newIdx] != nil {
                result.append(DiffToken(text: new[newIdx], type: .inserted, source: source))
                newIdx += 1
                continue
            }
            if oldIdx < old.count, removedOffsets.contains(oldIdx) {
                result.append(DiffToken(text: old[oldIdx], type: .deleted, source: source))
                oldIdx += 1
                continue
            }
            if oldIdx < old.count && newIdx < new.count {
                result.append(DiffToken(text: old[oldIdx], type: .equal))
                oldIdx += 1
                newIdx += 1
            } else {
                break
            }
        }

        return result
    }

    /// Assigns a shared groupId to each contiguous run of non-equal tokens
    /// that share the same type AND source.
    private static func assignGroupIds(_ tokens: [DiffToken]) -> [DiffToken] {
        var result: [DiffToken] = []
        var currentGroupKey: String? = nil
        var currentGroupId: UUID? = nil

        for token in tokens {
            if token.type == .equal {
                result.append(token)
                currentGroupKey = nil
                currentGroupId = nil
            } else {
                let sourceKey: String
                switch token.source {
                case .user:       sourceKey = "user"
                case .aiThenUser: sourceKey = "aiThenUser"
                default:          sourceKey = "ai"
                }
                let key = "\(token.type)_\(sourceKey)"
                if key != currentGroupKey {
                    currentGroupId = UUID()
                    currentGroupKey = key
                }
                result.append(DiffToken(text: token.text, type: token.type, groupId: currentGroupId, source: token.source))
            }
        }
        return result
    }
}
