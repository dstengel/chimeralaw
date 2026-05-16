// ExportService.swift
// Chimera Law
// Export clause text as plain text, clipboard, .docx, or comprehensive PDF.

import UIKit

// MARK: - Export Service

enum ExportService {

    // MARK: - Plain Text (for ShareLink / UIActivityViewController)

    /// Returns the text of the currently active tab.
    static func plainText(from viewModel: DraftingViewModel) -> String {
        viewModel.exportableText
    }

    // MARK: - Copy to Clipboard

    static func copyToClipboard(from viewModel: DraftingViewModel) {
        UIPasteboard.general.string = viewModel.exportableText
    }

    // MARK: - DOCX (comprehensive: Original + Changes + Output)

    /// Generates a comprehensive .docx with header, Original, Changes (tracked),
    /// and Output sections — mirroring the PDF export structure.
    static func generateDocx(from viewModel: DraftingViewModel) -> URL? {
        viewModel.recomputeExportTokens()
        let originalText = viewModel.originalText ?? ""
        let outputText = viewModel.exportableOutputText
        let diffTokens = viewModel.exportTokens
        guard !originalText.isEmpty || !outputText.isEmpty else { return nil }

        let fileFmt = DateFormatter()
        fileFmt.dateFormat = "yyyy_MM_dd HH_mm"
        let fileName = "Chimera \(fileFmt.string(from: Date())).docx"

        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChimeraExports", isDirectory: true)
        let docxURL = exportDir.appendingPathComponent(fileName)
        let buildDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChimeraBuild_\(UUID().uuidString)", isDirectory: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: Date())
        let isoDate = isoDateString()

        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)

            var body = ""
            var revID = 0

            // ===== HEADER =====
            body += docxParagraph(
                "Chimera Law \u{2013} VC Clause Drafting",
                bold: true, fontSize: 40, color: "000000"
            )
            body += docxParagraph(dateString, fontSize: 18, color: "666666")
            body += docxDivider()

            // ===== ORIGINAL =====
            if !originalText.isEmpty {
                body += docxParagraph("Original", bold: true, fontSize: 28, color: "000000",
                                       spacingAfter: 80)
                body += docxBodyParagraphs(originalText)
                body += docxDivider()
            }

            // ===== CHANGES (tracked) =====
            if !diffTokens.isEmpty {
                body += docxParagraph("Changes", bold: true, fontSize: 28, color: "000000",
                                       spacingAfter: 80)
                body += OOXMLTrackedChangesBuilder.build(
                    tokens: diffTokens,
                    author: AppConstants.exportAuthorName,
                    date: isoDate,
                    revisionID: &revID
                )
                body += docxDivider()
            }

            // ===== OUTPUT =====
            if !outputText.isEmpty {
                body += docxParagraph("Output", bold: true, fontSize: 28, color: "000000",
                                       spacingAfter: 80)
                body += docxBodyParagraphs(outputText)
            }

            // ===== FOOTER DISCLAIMER =====
            body += docxDivider()
            body += docxParagraph(Self.exportFooter, fontSize: 16, color: "888888", spacingAfter: 80)

            let documentXML = docxDocumentWrapper(body: body)

            let contentTypesXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
            </Types>
            """

            let relsXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
            </Relationships>
            """

            let wordRelsXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
            </Relationships>
            """

            let settingsXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:trackChanges/>
              <w:defaultTabStop w:val="720"/>
            </w:settings>
            """

            let wordDir = buildDir.appendingPathComponent("word", isDirectory: true)
            let relsDir = buildDir.appendingPathComponent("_rels", isDirectory: true)
            let wordRelsDir = wordDir.appendingPathComponent("_rels", isDirectory: true)

            try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: wordRelsDir, withIntermediateDirectories: true)

            try contentTypesXML.write(to: buildDir.appendingPathComponent("[Content_Types].xml"),
                                       atomically: true, encoding: .utf8)
            try relsXML.write(to: relsDir.appendingPathComponent(".rels"),
                              atomically: true, encoding: .utf8)
            try documentXML.write(to: wordDir.appendingPathComponent("document.xml"),
                                  atomically: true, encoding: .utf8)
            try wordRelsXML.write(to: wordRelsDir.appendingPathComponent("document.xml.rels"),
                                  atomically: true, encoding: .utf8)
            try settingsXML.write(to: wordDir.appendingPathComponent("settings.xml"),
                                  atomically: true, encoding: .utf8)

            try zipDirectory(at: buildDir, to: docxURL, excluding: [])
            try? FileManager.default.removeItem(at: buildDir)
            return docxURL
        } catch {
            try? FileManager.default.removeItem(at: buildDir)
            return nil
        }
    }

    // MARK: - DOCX XML Helpers

    /// Wraps body content in the full document.xml structure.
    private static func docxDocumentWrapper(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
                    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
                    xmlns:o="urn:schemas-microsoft-com:office:office"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
                    xmlns:v="urn:schemas-microsoft-com:vml"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:w10="urn:schemas-microsoft-com:office:word"
                    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml"
                    mc:Ignorable="w14 wp14">
        <w:body>
        \(body)
        <w:sectPr>
          <w:pgSz w:w="11906" w:h="16838"/>
          <w:pgMar w:top="1588" w:right="1440" w:bottom="1588" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
        </w:sectPr>
        </w:body>
        </w:document>
        """
    }

    /// Creates a single paragraph with optional formatting.
    private static func docxParagraph(
        _ text: String,
        bold: Bool = false,
        fontSize: Int = 22,  // half-points (22 = 11pt)
        color: String = "000000",
        spacingAfter: Int = 120
    ) -> String {
        let escaped = escapeXML(text)
        let boldTag = bold ? "<w:b/>" : ""
        return """
        <w:p><w:pPr><w:spacing w:after="\(spacingAfter)" w:line="276" w:lineRule="auto"/>\
        <w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>\
        <w:sz w:val="\(fontSize)"/>\(boldTag)<w:color w:val="\(color)"/>\
        </w:rPr></w:pPr>\
        <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>\
        <w:sz w:val="\(fontSize)"/>\(boldTag)<w:color w:val="\(color)"/>\
        </w:rPr><w:t xml:space="preserve">\(escaped)</w:t></w:r></w:p>
        """
    }

    /// Creates a horizontal rule divider paragraph.
    private static func docxDivider() -> String {
        """
        <w:p><w:pPr><w:spacing w:after="120"/>\
        <w:pBdr><w:bottom w:val="single" w:sz="4" w:space="1" w:color="BFBFBF"/></w:pBdr>\
        </w:pPr></w:p>
        """
    }

    /// Converts a multi-line string into body paragraphs (11pt Times New Roman).
    private static func docxBodyParagraphs(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let escaped = escapeXML(line)
            return """
            <w:p><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/>\
            <w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>\
            <w:sz w:val="22"/></w:rPr></w:pPr>\
            <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>\
            <w:sz w:val="22"/></w:rPr>\
            <w:t xml:space="preserve">\(escaped)</w:t></w:r></w:p>
            """
        }.joined()
    }

    // MARK: - Comprehensive PDF

    /// Generates a multi-section PDF with logo, metadata, Original, Changes, and Output.
    /// Margins are generous enough for both A4 and US Letter.
    static func generatePDF(
        viewModel: DraftingViewModel,
        appIconImage: UIImage?
    ) -> URL? {
        viewModel.recomputeExportTokens()
        let pageWidth: CGFloat = 595.28   // A4 width in points (fits within US Letter too)
        let pageHeight: CGFloat = 841.89  // A4 height
        let marginH: CGFloat = 56         // ~20mm horizontal margin
        let marginTop: CGFloat = 56
        let marginBottom: CGFloat = 56
        let contentWidth = pageWidth - 2 * marginH
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Chimera Law Export",
            kCGPDFContextCreator as String: "Chimera Law"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        // Prepare text content
        let originalText = viewModel.originalText ?? ""
        let outputText = viewModel.exportableOutputText
        let diffTokens = viewModel.exportTokens

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: Date())

        let data = renderer.pdfData { context in

            // -- Fonts --
            let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
            let headingFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            let smallFont = UIFont.systemFont(ofSize: 9, weight: .regular)

            let textColor = UIColor.black
            let secondaryColor = UIColor.darkGray
            let deletedColor = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)   // red
            let insertedColor = UIColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1)  // blue
            let dividerColor = UIColor(white: 0.75, alpha: 1)

            var yPosition: CGFloat = 0

            func beginNewPage() {
                context.beginPage()
                yPosition = marginTop
            }

            func ensureSpace(_ needed: CGFloat) {
                if yPosition + needed > pageHeight - marginBottom {
                    beginNewPage()
                }
            }

            func drawDivider() {
                ensureSpace(20)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: marginH, y: yPosition + 8))
                path.addLine(to: CGPoint(x: pageWidth - marginH, y: yPosition + 8))
                dividerColor.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                yPosition += 20
            }

            /// Draws a block of body text, paginating as needed.
            func drawBodyText(_ text: String, font: UIFont, color: UIColor) {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 4
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle
                ]
                let attrStr = NSAttributedString(string: text, attributes: attrs)
                drawAttributedText(attrStr)
            }

            /// Draws paginated attributed text using Core Text.
            /// UIGraphicsPDFRenderer uses UIKit coordinates (origin top-left, y-down).
            /// Core Text expects Quartz coordinates (origin bottom-left, y-up).
            /// We flip the full page to Quartz coords, then position the frame rect
            /// at the correct Quartz y-origin.
            func drawAttributedText(_ attrStr: NSAttributedString) {
                let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
                var charIndex = 0
                let length = attrStr.length

                while charIndex < length {
                    ensureSpace(bodyFont.lineHeight + 4)
                    let availableHeight = pageHeight - marginBottom - yPosition

                    // In Quartz coords, the text area runs from quartzY upward.
                    let quartzY = pageHeight - yPosition - availableHeight

                    let framePath = CGPath(rect: CGRect(x: marginH, y: quartzY,
                                                         width: contentWidth,
                                                         height: availableHeight),
                                           transform: nil)
                    let range = CFRangeMake(charIndex, 0)
                    let frame = CTFramesetterCreateFrame(framesetter, range, framePath, nil)
                    let visibleRange = CTFrameGetVisibleStringRange(frame)

                    if visibleRange.length == 0 {
                        beginNewPage()
                        continue
                    }

                    // Flip entire page to Quartz coordinates, reset text matrix.
                    let ctx = context.cgContext
                    ctx.saveGState()
                    ctx.textMatrix = .identity
                    ctx.translateBy(x: 0, y: pageHeight)
                    ctx.scaleBy(x: 1, y: -1)
                    CTFrameDraw(frame, ctx)
                    ctx.restoreGState()

                    // Calculate how much vertical space was actually used.
                    let lines = CTFrameGetLines(frame) as! [CTLine]
                    if lines.isEmpty { break }

                    var origins = [CGPoint](repeating: .zero, count: lines.count)
                    CTFrameGetLineOrigins(frame, CFRangeMake(0, lines.count), &origins)

                    // origins are relative to the frame path rect's origin (quartzY).
                    // origins[0].y is near availableHeight (top), origins[last].y near 0.
                    let lastOrigin = origins[lines.count - 1]
                    let lastLine = lines[lines.count - 1]
                    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                    CTLineGetTypographicBounds(lastLine, &ascent, &descent, &leading)

                    let usedHeight = availableHeight - lastOrigin.y + descent + leading
                    yPosition += usedHeight + 8

                    charIndex += visibleRange.length
                }
            }

            // ========== PAGE 1: Header ==========
            beginNewPage()

            // App icon
            if let icon = appIconImage {
                let iconSize: CGFloat = 40
                let iconRect = CGRect(x: marginH, y: yPosition, width: iconSize, height: iconSize)
                icon.draw(in: iconRect)

                // App name next to icon
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: titleFont,
                    .foregroundColor: textColor
                ]
                let nameRect = CGRect(x: marginH + iconSize + 12, y: yPosition + 6,
                                       width: contentWidth - iconSize - 12, height: 30)
                "Chimera Law".draw(in: nameRect, withAttributes: nameAttrs)
                yPosition += iconSize + 16
            } else {
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: titleFont,
                    .foregroundColor: textColor
                ]
                "Chimera Law".draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: nameAttrs)
                yPosition += 32
            }

            // Date
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: smallFont,
                .foregroundColor: secondaryColor
            ]
            dateString.draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: dateAttrs)
            yPosition += 18

            yPosition += 8
            drawDivider()

            // ========== SECTION 1: Original ==========
            if !originalText.isEmpty {
                ensureSpace(30)
                let sectionAttrs: [NSAttributedString.Key: Any] = [
                    .font: headingFont,
                    .foregroundColor: textColor
                ]
                "Original".draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: sectionAttrs)
                yPosition += 24

                drawBodyText(originalText, font: bodyFont, color: textColor)
                drawDivider()
            }

            // ========== SECTION 2: Changes (redline) ==========
            if !diffTokens.isEmpty {
                ensureSpace(30)
                let sectionAttrs: [NSAttributedString.Key: Any] = [
                    .font: headingFont,
                    .foregroundColor: textColor
                ]
                "Changes".draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: sectionAttrs)
                yPosition += 24

                // Build attributed string from diff tokens
                let redlineStr = buildRedlineAttributedString(
                    tokens: diffTokens,
                    outputText: outputText,
                    bodyFont: bodyFont,
                    deletedColor: deletedColor,
                    insertedColor: insertedColor,
                    normalColor: textColor
                )
                drawAttributedText(redlineStr)
                drawDivider()
            }

            // ========== SECTION 3: Output ==========
            if !outputText.isEmpty {
                ensureSpace(30)
                let sectionAttrs: [NSAttributedString.Key: Any] = [
                    .font: headingFont,
                    .foregroundColor: textColor
                ]
                "Output".draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: sectionAttrs)
                yPosition += 24

                drawBodyText(outputText, font: bodyFont, color: textColor)
            }

            // ========== FOOTER DISCLAIMER ==========
            drawDivider()
            ensureSpace(20)
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: smallFont, .foregroundColor: secondaryColor]
            ExportService.exportFooter.draw(
                in: CGRect(x: marginH, y: yPosition, width: contentWidth, height: 40),
                withAttributes: footerAttrs)
            yPosition += 20
        }

        // Build filename: "Chimera Clause YYYY_MM_DD HH_mm.pdf"
        let fileFmt = DateFormatter()
        fileFmt.dateFormat = "yyyy_MM_dd HH_mm"
        let fileName = "Chimera \(fileFmt.string(from: Date())).pdf"

        // Write to a dedicated export subdirectory in tmp (avoids stale-file issues).
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChimeraExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir,
                                                  withIntermediateDirectories: true)
        let tempURL = exportDir.appendingPathComponent(fileName)

        // Remove any previous file at this path.
        try? FileManager.default.removeItem(at: tempURL)

        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            // PDF write error — silently fail, return nil
            return nil
        }
    }

    // MARK: - Tell Me PDF

    /// Generates a PDF with header, Original clause, and Tell Me analysis.
    /// Reuses the same page layout and fonts as the clause PDF.
    static func generateTellMePDF(
        viewModel: DraftingViewModel,
        appIconImage: UIImage?
    ) -> URL? {
        guard let analysisResult = viewModel.analysisResult,
              let originalText = viewModel.originalText else { return nil }

        let parsed = AnalysisPrompts.parseAnalysis(analysisResult)

        let pageWidth: CGFloat = 595.28
        let pageHeight: CGFloat = 841.89
        let marginH: CGFloat = 56
        let marginTop: CGFloat = 56
        let marginBottom: CGFloat = 56
        let contentWidth = pageWidth - 2 * marginH
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Chimera Law Tell Me",
            kCGPDFContextCreator as String: "Chimera Law"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: Date())

        let data = renderer.pdfData { context in

            let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
            let headingFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            let smallFont = UIFont.systemFont(ofSize: 9, weight: .regular)
            let dashLabelFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let dashValueFont = UIFont.systemFont(ofSize: 10, weight: .regular)

            let textColor = UIColor.black
            let secondaryColor = UIColor.darkGray
            let headingColor = UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1) // indigo
            let dividerColor = UIColor(white: 0.75, alpha: 1)

            var yPosition: CGFloat = 0

            func beginNewPage() {
                context.beginPage()
                yPosition = marginTop
            }

            func ensureSpace(_ needed: CGFloat) {
                if yPosition + needed > pageHeight - marginBottom {
                    beginNewPage()
                }
            }

            func drawDivider() {
                ensureSpace(20)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: marginH, y: yPosition + 8))
                path.addLine(to: CGPoint(x: pageWidth - marginH, y: yPosition + 8))
                dividerColor.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                yPosition += 20
            }

            func drawBodyText(_ text: String, font: UIFont, color: UIColor) {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 4
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle
                ]
                let attrStr = NSAttributedString(string: text, attributes: attrs)
                drawAttributedText(attrStr)
            }

            func drawAttributedText(_ attrStr: NSAttributedString) {
                let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
                var charIndex = 0
                let length = attrStr.length

                while charIndex < length {
                    ensureSpace(bodyFont.lineHeight + 4)
                    let availableHeight = pageHeight - marginBottom - yPosition
                    let quartzY = pageHeight - yPosition - availableHeight

                    let framePath = CGPath(rect: CGRect(x: marginH, y: quartzY,
                                                         width: contentWidth,
                                                         height: availableHeight),
                                           transform: nil)
                    let range = CFRangeMake(charIndex, 0)
                    let frame = CTFramesetterCreateFrame(framesetter, range, framePath, nil)
                    let visibleRange = CTFrameGetVisibleStringRange(frame)

                    if visibleRange.length == 0 {
                        beginNewPage()
                        continue
                    }

                    let ctx = context.cgContext
                    ctx.saveGState()
                    ctx.textMatrix = .identity
                    ctx.translateBy(x: 0, y: pageHeight)
                    ctx.scaleBy(x: 1, y: -1)
                    CTFrameDraw(frame, ctx)
                    ctx.restoreGState()

                    let lines = CTFrameGetLines(frame) as! [CTLine]
                    if lines.isEmpty { break }

                    var origins = [CGPoint](repeating: .zero, count: lines.count)
                    CTFrameGetLineOrigins(frame, CFRangeMake(0, lines.count), &origins)

                    let lastOrigin = origins[lines.count - 1]
                    let lastLine = lines[lines.count - 1]
                    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                    CTLineGetTypographicBounds(lastLine, &ascent, &descent, &leading)

                    let usedHeight = availableHeight - lastOrigin.y + descent + leading
                    yPosition += usedHeight + 8

                    charIndex += visibleRange.length
                }
            }

            /// Renders markdown text as an attributed string with bold/italic.
            func drawMarkdownText(_ text: String) {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 4

                if let mdAttr = try? NSMutableAttributedString(
                    markdown: text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    mdAttr.addAttributes([
                        .font: bodyFont,
                        .foregroundColor: textColor,
                        .paragraphStyle: paragraphStyle
                    ], range: NSRange(location: 0, length: mdAttr.length))
                    drawAttributedText(mdAttr)
                } else {
                    drawBodyText(text, font: bodyFont, color: textColor)
                }
            }

            // ========== PAGE 1: Header ==========
            beginNewPage()

            if let icon = appIconImage {
                let iconSize: CGFloat = 40
                let iconRect = CGRect(x: marginH, y: yPosition, width: iconSize, height: iconSize)
                icon.draw(in: iconRect)

                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: titleFont,
                    .foregroundColor: textColor
                ]
                let nameRect = CGRect(x: marginH + iconSize + 12, y: yPosition + 6,
                                       width: contentWidth - iconSize - 12, height: 30)
                "Chimera Law".draw(in: nameRect, withAttributes: nameAttrs)
                yPosition += iconSize + 16
            } else {
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: titleFont,
                    .foregroundColor: textColor
                ]
                "Chimera Law".draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: nameAttrs)
                yPosition += 32
            }

            // Date
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: smallFont,
                .foregroundColor: secondaryColor
            ]
            dateString.draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: dateAttrs)
            yPosition += 18

            yPosition += 8
            drawDivider()

            // ========== SECTION 1: Original ==========
            ensureSpace(30)
            let sectionAttrs: [NSAttributedString.Key: Any] = [
                .font: headingFont,
                .foregroundColor: textColor
            ]
            "Original".draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: sectionAttrs)
            yPosition += 24

            drawBodyText(originalText, font: bodyFont, color: textColor)
            drawDivider()

            // ========== SECTION 2: Tell Me Analysis ==========
            ensureSpace(30)
            let analysisHeadingAttrs: [NSAttributedString.Key: Any] = [
                .font: headingFont,
                .foregroundColor: textColor
            ]
            "Tell Me Analysis".draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: analysisHeadingAttrs)
            yPosition += 24

            // Headline
            if let headline = parsed.headline {
                let headlineAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: textColor
                ]
                let headlineStr = NSAttributedString(string: headline, attributes: headlineAttrs)
                drawAttributedText(headlineStr)
                yPosition += 4
            }

            // Dashboard summary
            if let dash = parsed.dashboard {
                ensureSpace(50)
                let lines = [
                    ("Bias:", "\(dash.biasScore) | \(dash.biasLabel)"),
                    ("Risk:", "\(dash.riskLevel) | \(dash.riskLabel)"),
                    ("Market:", "\(dash.marketStandard) | \(dash.marketStandardLabel)")
                ]
                for (label, value) in lines {
                    ensureSpace(16)
                    let lAttrs: [NSAttributedString.Key: Any] = [
                        .font: dashLabelFont,
                        .foregroundColor: secondaryColor
                    ]
                    let vAttrs: [NSAttributedString.Key: Any] = [
                        .font: dashValueFont,
                        .foregroundColor: textColor
                    ]
                    label.draw(at: CGPoint(x: marginH, y: yPosition), withAttributes: lAttrs)
                    let labelWidth = (label as NSString).size(withAttributes: lAttrs).width
                    value.draw(at: CGPoint(x: marginH + labelWidth + 6, y: yPosition), withAttributes: vAttrs)
                    yPosition += 16
                }
                yPosition += 8
            }

            // Analysis sections
            let sectionHeadingAttrs: [NSAttributedString.Key: Any] = [
                .font: headingFont,
                .foregroundColor: headingColor
            ]

            for section in parsed.sections {
                ensureSpace(30)
                let title = NSAttributedString(string: section.title, attributes: sectionHeadingAttrs)
                drawAttributedText(title)
                yPosition += 2
                drawMarkdownText(section.body)
                yPosition += 8
            }

            // Fallback if no sections parsed
            if parsed.sections.isEmpty && parsed.headline == nil {
                drawMarkdownText(analysisResult)
            }

            // ========== FOOTER DISCLAIMER ==========
            drawDivider()
            ensureSpace(20)
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: smallFont, .foregroundColor: secondaryColor]
            ExportService.exportFooter.draw(
                in: CGRect(x: marginH, y: yPosition, width: contentWidth, height: 40),
                withAttributes: footerAttrs)
            yPosition += 20
        }

        // Write to file
        let fileFmt = DateFormatter()
        fileFmt.dateFormat = "yyyy_MM_dd HH_mm"
        let fileName = "Chimera Tell Me \(fileFmt.string(from: Date())).pdf"

        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChimeraExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let tempURL = exportDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: tempURL)

        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    /// Returns the current date/time as an ISO-8601 string for OOXML w:date attributes.
    private static func isoDateString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    /// Builds an NSAttributedString from diff tokens with redline formatting:
    /// - Deletions: red, strikethrough
    /// - Insertions: blue, underline
    /// - Equal: black, normal
    ///
    /// `outputText` is used to detect paragraph boundaries so the redline
    /// preserves the same line breaks as the Output section.
    static func buildRedlineAttributedString(
        tokens: [DiffToken],
        outputText: String,
        bodyFont: UIFont,
        deletedColor: UIColor,
        insertedColor: UIColor,
        normalColor: UIColor
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        // Build a set of word indices (within the output) that start a new paragraph.
        // Walk the output text paragraph by paragraph, counting words to find boundaries.
        var paragraphStartIndices = Set<Int>()
        var wordIndex = 0
        for paragraph in outputText.components(separatedBy: "\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // Empty line: mark the next word as a paragraph start
                paragraphStartIndices.insert(wordIndex)
                continue
            }
            paragraphStartIndices.insert(wordIndex)
            let wordsInParagraph = trimmed.split(omittingEmptySubsequences: true,
                                                  whereSeparator: { $0.isWhitespace })
            wordIndex += wordsInParagraph.count
        }
        // Index 0 should not produce a leading newline.
        paragraphStartIndices.remove(0)

        let result = NSMutableAttributedString()
        let spaceAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: normalColor
        ]

        // outputWordIndex tracks position in the output word stream
        // (only non-deleted tokens advance it, since deleted words aren't in the output).
        var outputWordIndex = 0
        var isFirst = true

        for token in tokens {
            // Skip newline sentinel tokens — paragraph breaks are handled
            // via paragraphStartIndices derived from the output text.
            if WordDiff.isNewline(token.text) {
                continue
            }

            var attrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .paragraphStyle: paragraphStyle
            ]

            switch token.type {
            case .equal:
                attrs[.foregroundColor] = normalColor
            case .deleted:
                attrs[.foregroundColor] = deletedColor
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = deletedColor
            case .inserted:
                attrs[.foregroundColor] = insertedColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.underlineColor] = insertedColor
            }

            // Insert separator before this token (space or paragraph break).
            if !isFirst {
                if token.type != .deleted && paragraphStartIndices.contains(outputWordIndex) {
                    result.append(NSAttributedString(string: "\n\n", attributes: spaceAttrs))
                } else {
                    result.append(NSAttributedString(string: " ", attributes: spaceAttrs))
                }
            }
            isFirst = false

            result.append(NSAttributedString(string: token.text, attributes: attrs))

            // Advance output word counter for non-deleted tokens.
            if token.type != .deleted {
                outputWordIndex += 1
            }
        }
        return result
    }

    /// Bilingual (EN / DE) export footer disclaimer appended to every exported document.
    static let exportFooter =
        "This document was produced by using Chimera Law. All content must be verified by the user. Chimera Law does not accept any liability. / " +
        "Dieses Dokument wurde mit Chimera Law erstellt. Der Nutzer ist verpflichtet, selbst den gesamten Inhalt zu prüfen. Chimera Law übernimmt keine Haftung für seine Richtigkeit."

    /// Escapes XML special characters.
    private static func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Creates a ZIP archive from the contents of a directory.
    /// Uses Foundation's built-in FileManager and NSData compression.
    private static func zipDirectory(at sourceDir: URL, to destURL: URL, excluding: [String]) throws {
        // Use the coordinate-based approach with NSFileCoordinator for ZIP
        // Since iOS doesn't have a built-in ZIP API for directories,
        // we use a minimal ZIP writer.
        let fileManager = FileManager.default
        var files: [(relativePath: String, data: Data)] = []

        let basePath = sourceDir.path
        if let enumerator = fileManager.enumerator(atPath: basePath) {
            while let relativePath = enumerator.nextObject() as? String {
                let fullURL = sourceDir.appendingPathComponent(relativePath)
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: fullURL.path, isDirectory: &isDir)

                if isDir.boolValue { continue }
                if excluding.contains(fullURL.lastPathComponent) { continue }
                if relativePath.contains(".DS_Store") { continue }

                let data = try Data(contentsOf: fullURL)
                files.append((relativePath: relativePath, data: data))
            }
        }

        let zipData = try createZipArchive(files: files)
        try zipData.write(to: destURL)
    }

    /// Minimal ZIP archive creator (no compression, store only — sufficient for .docx).
    private static func createZipArchive(files: [(relativePath: String, data: Data)]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for file in files {
            let nameData = Data(file.relativePath.utf8)
            let fileData = file.data
            let crc = crc32Checksum(fileData)

            // Local file header
            var localHeader = Data()
            localHeader.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // signature
            localHeader.appendUInt16(20)    // version needed
            localHeader.appendUInt16(0)     // flags
            localHeader.appendUInt16(0)     // compression (store)
            localHeader.appendUInt16(0)     // mod time
            localHeader.appendUInt16(0)     // mod date
            localHeader.appendUInt32(crc)
            localHeader.appendUInt32(UInt32(fileData.count)) // compressed size
            localHeader.appendUInt32(UInt32(fileData.count)) // uncompressed size
            localHeader.appendUInt16(UInt16(nameData.count))
            localHeader.appendUInt16(0)     // extra field length

            archive.append(localHeader)
            archive.append(nameData)
            archive.append(fileData)

            // Central directory entry
            var cdEntry = Data()
            cdEntry.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // signature
            cdEntry.appendUInt16(20)    // version made by
            cdEntry.appendUInt16(20)    // version needed
            cdEntry.appendUInt16(0)     // flags
            cdEntry.appendUInt16(0)     // compression
            cdEntry.appendUInt16(0)     // mod time
            cdEntry.appendUInt16(0)     // mod date
            cdEntry.appendUInt32(crc)
            cdEntry.appendUInt32(UInt32(fileData.count))
            cdEntry.appendUInt32(UInt32(fileData.count))
            cdEntry.appendUInt16(UInt16(nameData.count))
            cdEntry.appendUInt16(0)     // extra field length
            cdEntry.appendUInt16(0)     // comment length
            cdEntry.appendUInt16(0)     // disk number start
            cdEntry.appendUInt16(0)     // internal attributes
            cdEntry.appendUInt32(0)     // external attributes
            cdEntry.appendUInt32(offset)
            cdEntry.append(nameData)

            centralDirectory.append(cdEntry)
            offset = UInt32(archive.count)
        }

        let cdOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        // End of central directory
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // signature
        eocd.appendUInt16(0) // disk number
        eocd.appendUInt16(0) // disk with CD
        eocd.appendUInt16(UInt16(files.count))
        eocd.appendUInt16(UInt16(files.count))
        eocd.appendUInt32(UInt32(centralDirectory.count))
        eocd.appendUInt32(cdOffset)
        eocd.appendUInt16(0) // comment length

        archive.append(eocd)
        return archive
    }

    /// CRC-32 checksum (standard ZIP CRC).
    private static func crc32Checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Data Helpers for ZIP

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
