// DraftingViewModel+Helpers.swift
// Chimera Law
// OCR, clipboard, and usage tracking extensions for DraftingViewModel

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
@preconcurrency import Vision
import os

extension DraftingViewModel {

    // MARK: - OCR

    /// Converts an image to grayscale and applies a mild contrast boost before OCR.
    /// Sharper luminance contrast helps Vision detect diacritic dots (ä, ö, ü, ß).
    /// Falls back to the original CGImage if Core Image processing fails.
    private func preprocessedForOCR(_ image: UIImage) -> CGImage? {
        guard let ciImage = CIImage(image: image) else { return image.cgImage }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let filter = CIFilter(name: "CIColorControls") else { return image.cgImage }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0,  forKey: kCIInputSaturationKey) // grayscale
        filter.setValue(1.15, forKey: kCIInputContrastKey)   // mild contrast boost
        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: output.extent)
        else { return image.cgImage }
        return result
    }

    func performOCR(on image: UIImage) {
        guard let cgImage = preprocessedForOCR(image) else { return }

        Task.detached { [weak self] in
            let request = VNRecognizeTextRequest()
            // de-DE first: language correction preserves umlauts rather than stripping them.
            request.recognitionLanguages = ["de-DE", "en-GB"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let observations = request.results else { return }
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                if let self {
                    await MainActor.run {
                        self.clauseText.append(text)
                        if self.clauseText.count > 5000 {
                            self.clauseText = String(self.clauseText.prefix(5000))
                        }
                        self.textAddedViaPhoto = true
                        // Only offer AI cleanup when online and budget is available.
                        // Offline/exhausted: skip the prompt, import as-is.
                        if NetworkMonitor.shared.isConnected, !self.isBudgetExhausted {
                            self.showPhotoCleanUpPrompt = true
                        }
                    }
                }
            } catch {
                let msg = error.localizedDescription
                if let self {
                    await MainActor.run {
                        self.errorMessage = "OCR failed: \(msg)"
                    }
                }
            }
        }
    }

    // MARK: - Camera Capture with Trimming

    /// Gate check: returns true if the camera can be opened (hardware present, budget available, online).
    /// Sets errorMessage and returns false otherwise.
    func canOpenCamera() -> Bool {
        // OCR itself is local (Vision framework). The AI trimming step that
        // follows requires network + budget, but the camera entry should not
        // be blocked — the user can capture raw text offline, and the
        // trimming/cleanup logic gates the API call separately.
        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            errorMessage = "Camera is not available on this device."
            return false
        }
        return true
    }

    /// Receives a photo from the camera, OCRs it, sends to Claude for
    /// sentence-boundary trimming, then appends clean text to the clause field.
    func captureAndTrimClause(from image: UIImage) {
        guard let cgImage = preprocessedForOCR(image) else { return }

        isTrimming = true
        errorMessage = nil

        Task.detached { [weak self] in
            // Step 1: OCR via Vision
            let request = VNRecognizeTextRequest()
            // de-DE first: language correction preserves umlauts rather than stripping them.
            request.recognitionLanguages = ["de-DE", "en-GB"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                let msg = error.localizedDescription
                if let self {
                    await MainActor.run {
                        self.errorMessage = "OCR failed: \(msg)"
                        self.isTrimming = false
                    }
                }
                return
            }

            guard let observations = request.results else {
                if let self {
                    await MainActor.run {
                        self.errorMessage = "No text recognised in photo."
                        self.isTrimming = false
                    }
                }
                return
            }

            let ocrText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")

            guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if let self {
                    await MainActor.run {
                        self.errorMessage = "No text recognised in photo."
                        self.isTrimming = false
                    }
                }
                return
            }

            // Step 2: Send to Claude for sentence-boundary trimming.
            // If offline or budget exhausted, skip the AI trim and import
            // the raw OCR text directly. The user can still use the app.
            guard let self else { return }
            let canTrim = await MainActor.run { () -> Bool in
                NetworkMonitor.shared.isConnected && !self.isBudgetExhausted
            }
            if !canTrim {
                await MainActor.run {
                    self.clauseText.append(ocrText.trimmingCharacters(in: .whitespacesAndNewlines))
                    if self.clauseText.count > 5000 {
                        self.clauseText = String(self.clauseText.prefix(5000))
                    }
                    self.textAddedViaPhoto = true
                    self.isTrimming = false
                }
                return
            }
            do {
                let result = try await DraftingService.shared.trimClause(ocrText: ocrText)
                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                await self.recordUsage(result)

                if trimmed == "[NO_COMPLETE_SENTENCE]" || trimmed.isEmpty {
                    // No complete sentences — attempt AI reconstruction.
                    do {
                        let reconResult = try await DraftingService.shared.reconstructSentence(ocrText: ocrText)
                        let reconstructed = reconResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        await MainActor.run {
                            if reconstructed.isEmpty {
                                self.errorMessage = "No complete sentences found in the photo. Try capturing more of the clause."
                            } else {
                                self.clauseText.append(reconstructed)
                                if self.clauseText.count > 5000 {
                                    self.clauseText = String(self.clauseText.prefix(5000))
                                }
                                self.textAddedViaPhoto = true
                                self.textWasReconstructed = true
                                if NetworkMonitor.shared.isConnected, !self.isBudgetExhausted {
                                    self.showPhotoCleanUpPrompt = true
                                }
                            }
                            self.isTrimming = false
                        }
                        await self.recordUsage(reconResult)
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "No complete sentences found in the photo. Try capturing more of the clause."
                            self.isTrimming = false
                        }
                    }
                } else {
                    await MainActor.run {
                        self.clauseText.append(trimmed)
                        if self.clauseText.count > 5000 {
                            self.clauseText = String(self.clauseText.prefix(5000))
                        }
                        self.textAddedViaPhoto = true
                        self.isTrimming = false
                        if NetworkMonitor.shared.isConnected, !self.isBudgetExhausted {
                            self.showPhotoCleanUpPrompt = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Trimming failed: \(error.localizedDescription)"
                    self.isTrimming = false
                }
            }
        }
    }

    // MARK: - Clipboard

    func pasteFromClipboard() {
        guard let pastedText = UIPasteboard.general.string else {
            errorMessage = "Clipboard is empty"
            return
        }

        let totalLength = clauseText.count + pastedText.count
        if totalLength > 5000 {
            let available = 5000 - clauseText.count
            if available > 0 {
                clauseText.append(String(pastedText.prefix(available)))
                errorMessage = "Text truncated to 5,000 characters"
            } else {
                errorMessage = "Maximum length already reached"
            }
        } else {
            clauseText.append(pastedText)
        }
    }

    func copyClause() {
        let text = exportableText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    // MARK: - Usage Recording

    func recordUsage(_ result: DraftingService.RephraseResult) async {
        let service = DraftingService.shared
        guard !service.isUsingUserKey else { return }
        guard var usage = monthlyUsage else { return }

        usage.addUsage(
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens,
            inputPricePer1M: service.inputPricePer1M,
            outputPricePer1M: service.outputPricePer1M
        )
        self.monthlyUsage = usage

        do {
            try await CloudKitService.shared.saveMonthlyUsage(usage)
        } catch {
            Logger.app.error("Failed to save usage: \(error.localizedDescription)")
        }
    }
}
