// OOXMLTrackedChangesBuilder.swift
// Chimera Law
// Generates the OOXML tracked-changes markup for the Word export Changes section.
// Uses real <w:ins> / <w:del> elements so Accept All / Reject All works in Word.
//
// The builder receives simple two-way diff tokens (source == nil on changed tokens)
// from WordDiff.simpleDiff — no AI/user attribution, no phantom cancellations.
// Author name comes from AppConstants.exportAuthorName, passed in by the caller.

import Foundation

enum OOXMLTrackedChangesBuilder {

    /// Builds the OOXML Changes section as a string of <w:p> elements with
    /// real tracked-change wrappers (<w:ins> / <w:del>).
    ///
    /// - Parameters:
    ///   - tokens:     Simple diff tokens (equal / inserted / deleted, source == nil).
    ///   - author:     Author name for w:author attribute (AppConstants.exportAuthorName).
    ///   - date:       ISO-8601 date string for w:date attribute.
    ///   - revisionID: Monotonically incrementing revision counter (inout — caller owns it).
    /// - Returns: A string of OOXML paragraph elements ready to embed in document.xml.
    static func build(
        tokens: [DiffToken],
        author: String,
        date: String,
        revisionID: inout Int
    ) -> String {
        var paragraphs: [String] = []
        var currentRuns: [String] = []

        func flushParagraph() {
            guard !currentRuns.isEmpty else { return }
            let runs = currentRuns.joined()
            paragraphs.append("""
            <w:p><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/>\
            </w:pPr>\(runs)</w:p>
            """)
            currentRuns.removeAll()
        }

        let escapedAuthor = escapeXML(author)
        var needsSpace = false

        for token in tokens {
            // Newline sentinels flush the current paragraph and start a new one.
            if WordDiff.isNewline(token.text) {
                flushParagraph()
                needsSpace = false
                continue
            }

            let escapedText = escapeXML(token.text)
            let textWithSpace = needsSpace ? " \(escapedText)" : escapedText
            needsSpace = true

            let runProps = """
            <w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>\
            <w:sz w:val="22"/></w:rPr>
            """

            switch token.type {
            case .equal:
                currentRuns.append("""
                <w:r>\(runProps)<w:t xml:space="preserve">\(textWithSpace)</w:t></w:r>
                """)

            case .inserted:
                revisionID += 1
                currentRuns.append("""
                <w:ins w:id="\(revisionID)" w:author="\(escapedAuthor)" w:date="\(date)">\
                <w:r>\(runProps)<w:t xml:space="preserve">\(textWithSpace)</w:t></w:r>\
                </w:ins>
                """)

            case .deleted:
                revisionID += 1
                currentRuns.append("""
                <w:del w:id="\(revisionID)" w:author="\(escapedAuthor)" w:date="\(date)">\
                <w:r>\(runProps)<w:delText xml:space="preserve">\(textWithSpace)</w:delText></w:r>\
                </w:del>
                """)
            }
        }

        flushParagraph()
        return paragraphs.joined()
    }

    // MARK: - Private

    private static func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
