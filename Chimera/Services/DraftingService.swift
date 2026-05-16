// DraftingService.swift
// Chimera Law
// API service for rephrasing clauses with Claude.
// Includes token tracking for monthly budget.

import Foundation
import UIKit
import Combine
import os

@MainActor
final class DraftingService: ObservableObject {

    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: - Singleton

    static let shared = DraftingService()

    // MARK: - Properties

    private(set) var systemApiKey: String = ""
    private(set) var modelName: String = AppConfig.defaultModel
    private(set) var monthlyBudgetUSD: Double = AppConfig.defaultBudget
    private(set) var inputPricePer1M: Double = AppConfig.defaultInputPrice
    private(set) var outputPricePer1M: Double = AppConfig.defaultOutputPrice

    /// Whether the user has configured their own API key
    var isUsingUserKey: Bool {
        userApiKey != nil && !(userApiKey ?? "").isEmpty
    }

    /// The active API key (user key takes priority)
    var activeApiKey: String {
        if let userKey = userApiKey, !userKey.isEmpty {
            return userKey
        }
        return systemApiKey
    }

    var isConfigured: Bool {
        !activeApiKey.isEmpty
    }

    private var userApiKey: String? {
        KeychainHelper.read(key: KeychainHelper.userAPIKeyIdentifier)
    }

    private let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    private let logger = Logger(subsystem: "com.daimos.chimera", category: "DraftingService")

    // MARK: - Init

    private init() {}

    // MARK: - Configuration

    func configure(with config: AppConfig) {
        self.systemApiKey = config.claudeApiKey
        self.modelName = config.claudeModel
        self.monthlyBudgetUSD = config.monthlyBudgetUSD
        self.inputPricePer1M = config.inputPricePer1M
        self.outputPricePer1M = config.outputPricePer1M
    }

    // MARK: - Main API Call

    struct RephraseResult {
        let text: String
        let inputTokens: Int
        let outputTokens: Int
    }

    func rephrase(
        clause: String,
        style: DraftingStyle,
        heatLevel: HeatLevel,
        language: String,
        additionalInstruction: String? = nil
    ) async throws -> RephraseResult {
        guard !activeApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }

        let systemPrompt = DraftingPrompts.buildSystemPrompt(
            style: style,
            heat: heatLevel,
            language: language
        )

        let userMessage = DraftingPrompts.buildUserMessage(
            clause: clause,
            additionalInstruction: additionalInstruction
        )

        return try await sendRequest(systemPrompt: systemPrompt, userMessage: userMessage)
    }

    // MARK: - Raw Rephrase (for V+/V-)

    func rephraseRaw(
        systemPrompt: String,
        userMessage: String,
        maxTokens: Int = 1500
    ) async throws -> RephraseResult {
        guard !activeApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }
        return try await sendRequest(systemPrompt: systemPrompt, userMessage: userMessage, maxTokens: maxTokens)
    }

    // MARK: - Additional-Instruction (Send / AI) Rephrase

    /// Result of an Additional-Instruction call, including the parsed
    /// outcome and per-call usage tokens.
    struct AdditionalInstructionResult {
        let outcome: AdditionalInstructionOutcome
        let inputTokens: Int
        let outputTokens: Int
    }

    /// Single-variant rephrase driven by the user's free-text instruction.
    /// Composes the dedicated AI-flow system prompt and routes the response
    /// through `AdditionalInstructionPrompt.parseOutcome(_:)`. Honours the
    /// existing user-key/system-key fallback by translating an
    /// `.invalidAPIKey` from a user key into
    /// `.userKeyInvalidFallbackAvailable`.
    func rephraseAdditionalInstruction(
        style: DraftingStyle,
        language: String,
        sourceText: String,
        instruction: String
    ) async throws -> AdditionalInstructionResult {
        guard !activeApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }

        let systemPrompt = AdditionalInstructionPrompt.buildSystemPrompt(
            style: style,
            language: language
        )
        let userMessage = AdditionalInstructionPrompt.buildUserMessage(
            sourceText: sourceText,
            instruction: instruction
        )

        do {
            let raw = try await sendRequest(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                maxTokens: 1500
            )
            let outcome = try AdditionalInstructionPrompt.parseOutcome(raw.text)
            return AdditionalInstructionResult(
                outcome: outcome,
                inputTokens: raw.inputTokens,
                outputTokens: raw.outputTokens
            )
        } catch DraftingError.invalidAPIKey where isUsingUserKey && !systemApiKey.isEmpty {
            throw DraftingError.userKeyInvalidFallbackAvailable
        }
    }

    /// System-key variant of the Additional-Instruction rephrase, used by
    /// the BYOK fallback path so the JSON envelope is parsed by the same
    /// parser as the primary-key flow.
    func rephraseAdditionalInstructionWithSystemKey(
        style: DraftingStyle,
        language: String,
        sourceText: String,
        instruction: String
    ) async throws -> AdditionalInstructionResult {
        guard !systemApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }

        let systemPrompt = AdditionalInstructionPrompt.buildSystemPrompt(
            style: style,
            language: language
        )
        let userMessage = AdditionalInstructionPrompt.buildUserMessage(
            sourceText: sourceText,
            instruction: instruction
        )

        let raw = try await sendRequestWithSystemKey(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: 1500
        )
        let outcome = try AdditionalInstructionPrompt.parseOutcome(raw.text)
        return AdditionalInstructionResult(
            outcome: outcome,
            inputTokens: raw.inputTokens,
            outputTokens: raw.outputTokens
        )
    }

    // MARK: - Fixes (drafting fixes derived from a Tell Me analysis)

    /// Result of a Fixes API call. Returns the parsed three-group payload
    /// BEFORE pre-validation — pre-validation and dedup run on the caller
    /// side via `FixesPrompt.validateAndDedup(_:)`. Per-call usage tokens
    /// are passed through so the caller can record budget.
    struct FixesResult {
        let groups: FixesGroups
        let inputTokens: Int
        let outputTokens: Int
    }

    /// Fires the Fixes API call. Inputs: the user's drafting style (drives
    /// persona; under SIMPLE-fallback the caller passes `.aplus` explicitly
    /// so the persona matches the Tell Me analysis), the original clause
    /// text, the Tell Me result text, and the call language.
    ///
    /// `language` is a `String` to mirror `rephraseAdditionalInstruction`;
    /// current behaviour produces English output.
    ///
    /// Throws `DraftingError` on any failure path. The view-model wraps
    /// the error with the phase prefix per plan §7.5
    /// ("Couldn't generate revisions. <existing errorDescription>").
    func generateFixes(
        style: DraftingStyle,
        originalText: String,
        tellMeResult: String,
        language: String
    ) async throws -> FixesResult {
        guard !activeApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }
        // `language` is currently unused inside the prompt — Fixes inherit
        // the analysis text's language. Reserved for future
        // multi-language support; kept in the signature so call sites do
        // not need to change when the prompt starts honouring it.
        _ = language

        let systemPrompt = FixesPrompt.buildSystemPrompt(style: style)
        let userMessage = FixesPrompt.buildUserMessage(
            originalText: originalText,
            tellMeResult: tellMeResult
        )

        let raw = try await sendRequest(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: FixesPrompt.maxResponseTokens
        )

        let groups = try FixesPrompt.parseGroups(raw.text)
        return FixesResult(
            groups: groups,
            inputTokens: raw.inputTokens,
            outputTokens: raw.outputTokens
        )
    }

    // MARK: - Clause Trimming (Camera Capture)

    func trimClause(ocrText: String) async throws -> RephraseResult {
        guard !activeApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }
        let systemPrompt = DraftingPrompts.clauseTrimmingSystemPrompt
        let userMessage = DraftingPrompts.buildTrimmingUserMessage(ocrText: ocrText)
        return try await sendRequest(systemPrompt: systemPrompt, userMessage: userMessage)
    }

    // MARK: - Sentence Reconstruction (Camera: incomplete fragments)

    func reconstructSentence(ocrText: String) async throws -> RephraseResult {
        guard !activeApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }
        let systemPrompt = DraftingPrompts.sentenceReconstructionSystemPrompt
        let userMessage = DraftingPrompts.buildReconstructionUserMessage(ocrText: ocrText)
        return try await sendRequest(systemPrompt: systemPrompt, userMessage: userMessage)
    }

    // MARK: - Multi-Variant Rephrase (all 5 heat levels in one call)

    struct MultiVariantResult {
        let variants: [String: String]   // "F2","F1","N","I1","I2" → clause text
        let inputTokens: Int
        let outputTokens: Int
    }

    func rephraseAllVariants(
        systemPrompt: String,
        userMessage: String
    ) async throws -> MultiVariantResult {
        guard !activeApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }

        let requestBody = AnthropicRequest(
            model: modelName,
            max_tokens: 8000,
            system: systemPrompt,
            messages: [AnthropicMessage(role: "user", content: userMessage)]
        )

        let jsonData = try encoder.encode(requestBody)
        let request = buildURLRequest(apiKey: activeApiKey, body: jsonData)

        do {
            let result = try await executeWithRetry(request, maxAttempts: 2)
            let variants = try parseVariants(from: result.text)
            return MultiVariantResult(
                variants: variants,
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens
            )
        } catch DraftingError.invalidAPIKey where isUsingUserKey && !systemApiKey.isEmpty {
            throw DraftingError.userKeyInvalidFallbackAvailable
        }
    }

    func rephraseAllVariantsWithSystemKey(
        systemPrompt: String,
        userMessage: String
    ) async throws -> MultiVariantResult {
        guard !systemApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }

        let requestBody = AnthropicRequest(
            model: modelName,
            max_tokens: 8000,
            system: systemPrompt,
            messages: [AnthropicMessage(role: "user", content: userMessage)]
        )

        let jsonData = try encoder.encode(requestBody)
        let request = buildURLRequest(apiKey: systemApiKey, body: jsonData)
        let result = try await executeWithRetry(request, maxAttempts: 2)
        let variants = try parseVariants(from: result.text)

        return MultiVariantResult(
            variants: variants,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens
        )
    }

    // MARK: - Variant Parsing (tolerant)

    /// The five bias keys, in canonical form. Any key the model emits is
    /// normalized (uppercase, whitespace + separators stripped) before
    /// comparison against this set.
    private static let canonicalVariantKeys: [String] = ["F2", "F1", "N", "I1", "I2"]

    /// Extract the `<variants>...</variants>` JSON block and parse it into
    /// a `[canonical key: clause text]` dictionary. Throws a specific
    /// DraftingError case for each distinguishable failure mode (missing
    /// section, malformed JSON, missing key, empty value) to support both
    /// targeted user messages and os.Logger diagnostics. Deliberately does
    /// NOT apply semantic aliases (e.g. "Neutral" → "N") — that would mask
    /// prompt drift.
    private func parseVariants(from text: String) throws -> [String: String] {
        // Previews of the raw response are useful for diagnosis but they
        // include clause text — only log them on the failure paths below
        // so the happy path stays silent in the Xcode console.
        let preview = String(text.prefix(400))

        // 1. Extract `<variants>...</variants>` content using a DOTALL
        //    regex. If the model emits multiple matches (unusual, but can
        //    happen when it echoes the format example inside prose), take
        //    the LAST one — it is almost always the real output.
        let jsonCandidate: String
        if let extracted = extractLastVariantsBlock(from: text) {
            jsonCandidate = extracted
        } else {
            logger.error("parseVariants: <variants> tag not found. preview=\(preview, privacy: .private)")
            throw DraftingError.variantsSectionMissing
        }

        // 2. Strip markdown fences and whitespace.
        let cleaned = jsonCandidate
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Attempt JSON parse. If it fails due to raw newlines inside
        //    string values (a common drift mode), retry once with a
        //    newline-escape repair pass.
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(
                with: Data(cleaned.utf8),
                options: [.fragmentsAllowed]
            )
        } catch {
            let repaired = escapeRawNewlinesInJSONStrings(cleaned)
            do {
                jsonObject = try JSONSerialization.jsonObject(
                    with: Data(repaired.utf8),
                    options: [.fragmentsAllowed]
                )
            } catch let repairError {
                logger.error("parseVariants: JSON parse failed. detail=\(repairError.localizedDescription) preview=\(preview, privacy: .private)")
                throw DraftingError.variantsJSONMalformed(repairError.localizedDescription)
            }
        }

        // 4. Unwrap a single-key outer envelope if present
        //    (e.g. {"variants": { ... }}).
        let effectiveRoot: [String: Any]
        if let outer = jsonObject as? [String: Any] {
            if outer.count == 1,
               let onlyValue = outer.values.first as? [String: Any],
               containsAnyCanonicalKey(normalizedKeys: onlyValue.keys.map(Self.normalizeVariantKey)) {
                effectiveRoot = onlyValue
            } else {
                effectiveRoot = outer
            }
        } else {
            logger.error("parseVariants: top-level JSON is not an object. preview=\(preview, privacy: .private)")
            throw DraftingError.variantsJSONMalformed("top-level value is not a JSON object")
        }

        // 5. Normalize keys and extract string values (unwrapping
        //    single-string-field value objects where necessary).
        var normalized: [String: String] = [:]
        for (rawKey, rawValue) in effectiveRoot {
            let key = Self.normalizeVariantKey(rawKey)
            if let string = extractStringValue(from: rawValue) {
                normalized[key] = string
            }
        }

        // 6. Validate presence and non-emptiness of all five canonical keys.
        var result: [String: String] = [:]
        for key in Self.canonicalVariantKeys {
            guard let value = normalized[key] else {
                logger.error("parseVariants: missing key \(key). keys=\(normalized.keys.sorted().joined(separator: ","))")
                throw DraftingError.variantsKeyMissing(key)
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                logger.error("parseVariants: empty value for key \(key)")
                throw DraftingError.variantsEmptyValue(key)
            }
            result[key] = trimmed
        }

        return result
    }

    /// Returns the content of the LAST `<variants>...</variants>` block in
    /// the input, or nil if no such block is found. DOTALL so that the
    /// block may span lines.
    private func extractLastVariantsBlock(from text: String) -> String? {
        let pattern = "<variants>(.*?)</variants>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return nil
        }
        let ns = text as NSString
        let matches = regex.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        )
        guard let last = matches.last, last.numberOfRanges >= 2 else {
            return nil
        }
        let range = last.range(at: 1)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }

    /// Uppercase and strip whitespace, hyphens, underscores, and full stops
    /// from a candidate variant key. "f-2" → "F2", " Neutral " → "NEUTRAL"
    /// (not mapped to "N" — semantic aliasing is intentionally NOT applied).
    static func normalizeVariantKey(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
        return stripped.uppercased()
    }

    /// Returns true if any of the normalized keys match one of the five
    /// canonical bias keys. Used to decide whether to descend into a
    /// single-key outer envelope.
    private func containsAnyCanonicalKey(normalizedKeys: [String]) -> Bool {
        let canonical = Set(Self.canonicalVariantKeys)
        return normalizedKeys.contains(where: canonical.contains)
    }

    /// Extract a clause-text string from a variant value. If the value is
    /// a nested object with a single string field named `text`, `clause`,
    /// `variant`, `value`, or `output`, return that field's string. Returns
    /// nil for any other shape.
    private func extractStringValue(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let dict = value as? [String: Any] {
            let preferredKeys = ["text", "clause", "variant", "value", "output"]
            for key in preferredKeys {
                if let string = dict[key] as? String {
                    return string
                }
            }
        }
        return nil
    }

    /// Best-effort repair: walk the string and replace raw newline
    /// characters that appear INSIDE a JSON string literal with a literal
    /// `\n` escape. Newlines outside strings are left untouched. Quotes
    /// preceded by a backslash are treated as escaped and do not toggle
    /// string state.
    private func escapeRawNewlinesInJSONStrings(_ raw: String) -> String {
        var result = ""
        result.reserveCapacity(raw.count)
        var inString = false
        var escape = false
        for character in raw {
            if escape {
                result.append(character)
                escape = false
                continue
            }
            if character == "\\" {
                result.append(character)
                escape = true
                continue
            }
            if character == "\"" {
                inString.toggle()
                result.append(character)
                continue
            }
            if inString && character.isNewline {
                result.append("\\n")
                continue
            }
            result.append(character)
        }
        return result
    }

    // MARK: - Track Changes Analysis (Vision)

    struct TrackChangesSpan: Codable {
        enum Status: String, Codable {
            case normal
            case inserted
            case deleted
        }
        let text: String
        let status: Status
    }

    struct TrackChangesResult {
        let spans: [TrackChangesSpan]
        let markupDetected: Bool
        let inputTokens: Int
        let outputTokens: Int
    }

    func analyzeTrackChanges(image: UIImage) async throws -> TrackChangesResult {
        guard !activeApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            throw DraftingError.invalidResponse
        }
        let base64String = jpegData.base64EncodedString()

        let systemPrompt = DraftingPrompts.trackChangesSystemPrompt
        let userText = DraftingPrompts.trackChangesUserMessage

        let requestBody: [String: Any] = [
            "model": modelName,
            "max_tokens": 8000,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userText
                        ],
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64String
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        var request = buildURLRequest(apiKey: activeApiKey, body: jsonData)
        request.timeoutInterval = 120

        do {
            let result = try await executeWithRetry(request, maxAttempts: 2)
            let spans = try parseTrackChangesSpans(from: result.text)
            let markupDetected = spans.contains { $0.status != .normal }
            return TrackChangesResult(
                spans: spans,
                markupDetected: markupDetected,
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens
            )
        } catch DraftingError.invalidAPIKey where isUsingUserKey && !systemApiKey.isEmpty {
            throw DraftingError.userKeyInvalidFallbackAvailable
        }
    }

    private func parseTrackChangesSpans(from text: String) throws -> [TrackChangesSpan] {
        // Try direct decode first
        if let data = text.data(using: .utf8),
           let spans = try? JSONDecoder().decode([TrackChangesSpan].self, from: data) {
            return spans
        }

        // Strip markdown fences if present
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let spans = try? JSONDecoder().decode([TrackChangesSpan].self, from: data) {
            return spans
        }

        // Try to extract array from surrounding text
        if let bracketStart = cleaned.firstIndex(of: "["),
           let bracketEnd = cleaned.lastIndex(of: "]") {
            let jsonString = String(cleaned[bracketStart...bracketEnd])
            if let data = jsonString.data(using: .utf8),
               let spans = try? JSONDecoder().decode([TrackChangesSpan].self, from: data) {
                return spans
            }
        }

        throw DraftingError.invalidResponseFormat
    }

    // MARK: - System Key Fallback (explicit, after user confirmation)

    func sendRequestWithSystemKey(
        systemPrompt: String,
        userMessage: String,
        maxTokens: Int = 1500
    ) async throws -> RephraseResult {
        guard !systemApiKey.isEmpty else {
            throw DraftingError.missingAPIKey
        }
        let requestBody = AnthropicRequest(
            model: modelName,
            max_tokens: maxTokens,
            system: systemPrompt,
            messages: [AnthropicMessage(role: "user", content: userMessage)]
        )
        let jsonData = try encoder.encode(requestBody)
        let request = buildURLRequest(apiKey: systemApiKey, body: jsonData)
        return try await executeWithRetry(request, maxAttempts: 2)
    }

    // MARK: - HTTP

    private func sendRequest(
        systemPrompt: String,
        userMessage: String,
        maxTokens: Int = 1500
    ) async throws -> RephraseResult {
        let requestBody = AnthropicRequest(
            model: modelName,
            max_tokens: maxTokens,
            system: systemPrompt,
            messages: [AnthropicMessage(role: "user", content: userMessage)]
        )

        let jsonData = try encoder.encode(requestBody)

        let request = buildURLRequest(apiKey: activeApiKey, body: jsonData)

        do {
            return try await executeWithRetry(request, maxAttempts: 2)
        } catch DraftingError.invalidAPIKey where isUsingUserKey && !systemApiKey.isEmpty {
            // User key failed -- offer fallback instead of auto-switching
            throw DraftingError.userKeyInvalidFallbackAvailable
        }
    }

    private func buildURLRequest(apiKey: String, body: Data) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = body
        request.timeoutInterval = 120
        return request
    }

    // MARK: - Retry Logic

    private func executeWithRetry(
        _ request: URLRequest,
        maxAttempts: Int,
        attempt: Int = 1
    ) async throws -> RephraseResult {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DraftingError.invalidResponse
            }

            let status = httpResponse.statusCode

            // 2xx — fall through to decode.
            if status >= 200 && status < 300 {
                let apiResponse = try decoder.decode(AnthropicResponse.self, from: data)
                guard let firstBlock = apiResponse.content.first,
                      case .text(let text) = firstBlock else {
                    logger.error("2xx but no text content block. stop_reason=\(apiResponse.stop_reason ?? "nil")")
                    throw DraftingError.invalidResponse
                }

                // stop_reason gating. Truncation and refusal are surfaced as
                // dedicated errors so the parser never has to guess.
                if let stop = apiResponse.stop_reason {
                    if stop == "max_tokens" {
                        logger.error("Response truncated at max_tokens. model=\(self.modelName) out=\(apiResponse.usage?.output_tokens ?? 0)")
                        throw DraftingError.responseTruncated
                    }
                    if stop == "refusal" {
                        logger.error("Model refused. model=\(self.modelName)")
                        throw DraftingError.apiModelRefused
                    }
                }

                let inputTokens = apiResponse.usage?.input_tokens ?? 0
                let outputTokens = apiResponse.usage?.output_tokens ?? 0

                return RephraseResult(
                    text: text,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens
                )
            }

            // HTTP error branches. Preserve behaviour where callers (user-key
            // fallback) key on .invalidAPIKey for 401.
            let detail = String(data: data, encoding: .utf8) ?? "Unknown"
            logger.error("HTTP \(status) from API. detail=\(detail.prefix(400))")

            switch status {
            case 401:
                throw DraftingError.invalidAPIKey
            case 403:
                throw DraftingError.httpPermissionDenied
            case 404:
                throw DraftingError.modelNotFound(self.modelName)
            case 429:
                // Anthropic standard rate limit. Keep legacy .rateLimited for
                // external callers that match on it.
                throw DraftingError.rateLimited
            case 529:
                // Anthropic "overloaded" status.
                throw DraftingError.apiOverloaded
            case 400..<500:
                throw DraftingError.clientError(status, detail)
            case 500...:
                if attempt < maxAttempts {
                    try await Task.sleep(for: .seconds(1))
                    return try await executeWithRetry(
                        request, maxAttempts: maxAttempts, attempt: attempt + 1
                    )
                }
                throw DraftingError.httpServerError(status)
            default:
                throw DraftingError.clientError(status, detail)
            }

        } catch let error as DraftingError {
            throw error
        } catch is CancellationError {
            // Cooperative task cancellation — propagate silently.
            throw CancellationError()
        } catch let urlError as URLError {
            return try await handleURLError(
                urlError,
                request: request,
                maxAttempts: maxAttempts,
                attempt: attempt
            )
        } catch {
            logger.error("Unknown error from executeWithRetry: \(error.localizedDescription)")
            throw DraftingError.decodingError(error.localizedDescription)
        }
    }

    /// Triage URLError codes into specific DraftingError cases with
    /// tailored retry policy. Timeouts and "not connected" states are not
    /// retried because retrying only doubles the user's wait.
    private func handleURLError(
        _ urlError: URLError,
        request: URLRequest,
        maxAttempts: Int,
        attempt: Int
    ) async throws -> RephraseResult {
        let code = urlError.code
        logger.error("URLError code=\(code.rawValue) description=\(urlError.localizedDescription)")

        switch code {
        case .cancelled:
            // URLSession maps task cancellation to URLError.cancelled. This is
            // NOT a network failure — the caller has already moved on.
            throw CancellationError()

        case .timedOut:
            // Do not retry. A 120s idle timeout that fired once will almost
            // certainly fire again, doubling the user's wait with no payoff.
            throw DraftingError.requestTimedOut

        case .notConnectedToInternet:
            throw DraftingError.offline

        case .networkConnectionLost:
            throw DraftingError.connectionLost

        case .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            if attempt < maxAttempts {
                try await Task.sleep(for: .seconds(1))
                return try await executeWithRetry(
                    request, maxAttempts: maxAttempts, attempt: attempt + 1
                )
            }
            throw DraftingError.cannotReachHost

        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            throw DraftingError.tlsFailure

        default:
            if attempt < maxAttempts {
                try await Task.sleep(for: .seconds(1))
                return try await executeWithRetry(
                    request, maxAttempts: maxAttempts, attempt: attempt + 1
                )
            }
            throw DraftingError.genericURLError(code.rawValue)
        }
    }
}

// MARK: - API Models

struct AnthropicRequest: Codable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [AnthropicMessage]
}

struct AnthropicMessage: Codable {
    let role: String
    let content: String
}

private struct AnthropicResponse: Codable {
    let content: [ContentBlock]
    let usage: UsageInfo?
    let stop_reason: String?
}

private struct UsageInfo: Codable {
    let input_tokens: Int?
    let output_tokens: Int?
}

private enum ContentBlock: Codable {
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "text" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown content block type: \(type)"
            )
        }
        let text = try container.decode(String.self, forKey: .text)
        self = .text(text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text
    }
}

// MARK: - Errors

/// Chimera Law-specific error taxonomy.
///
/// The enum is intentionally granular so that the UI can surface specific,
/// actionable messages and so that diagnostics at the os.Logger layer can
/// distinguish transport failures from response-parsing failures. Legacy
/// cases (`networkError`, `invalidResponseFormat`, `clientError`,
/// `serverError`, `rateLimited`) are retained for source compatibility with
/// older call sites but new code paths should throw the specific cases.
enum DraftingError: LocalizedError, Equatable {

    // Authentication / configuration
    case missingAPIKey
    case invalidAPIKey
    case userKeyInvalidFallbackAvailable
    case budgetExhausted
    case modelNotFound(String)

    // Transport layer (URLError triage)
    case offline
    case connectionLost
    case requestTimedOut
    case cannotReachHost
    case tlsFailure
    case genericURLError(Int)

    // HTTP layer
    case httpRateLimited
    case httpServerError(Int)
    case httpPermissionDenied
    case clientError(Int, String)
    case serverError(Int, String)

    // API body / response level
    case apiOverloaded
    case apiModelRefused
    case responseTruncated
    case invalidResponse

    // Response parsing (multi-variant)
    case variantsSectionMissing
    case variantsJSONMalformed(String)
    case variantsKeyMissing(String)
    case variantsEmptyValue(String)
    case decodingError(String)

    // Legacy aliases (kept for source compatibility)
    case invalidResponseFormat
    case rateLimited
    case networkError

    var errorDescription: String? {
        switch self {

        // Authentication / configuration
        case .missingAPIKey:
            return "API key not configured. Add your own key in Settings or wait for the app to load."
        case .invalidAPIKey:
            return "The API key was rejected. Check it in Settings."
        case .userKeyInvalidFallbackAvailable:
            return "Your API key is invalid or expired. Would you like to use the system key instead?"
        case .budgetExhausted:
            return "Your monthly budget has been reached. Add your own API key in Settings to continue."
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Check the model name in Settings."

        // Transport
        case .offline:
            return "No internet connection. Reconnect and try again."
        case .connectionLost:
            return "The connection dropped mid-request. Try again."
        case .requestTimedOut:
            return "The AI service took too long to respond. Try a shorter clause or try again."
        case .cannotReachHost:
            return "Could not reach the AI service. Check your connection and try again."
        case .tlsFailure:
            return "Secure connection failed. Check your device's date and time."
        case .genericURLError(let code):
            return "Connection error (code \(code)). Try again."

        // HTTP
        case .httpRateLimited, .rateLimited:
            return "Rate limit reached. Wait a moment and try again."
        case .httpServerError(let status):
            return "The AI service is temporarily unavailable (HTTP \(status)). Try again shortly."
        case .httpPermissionDenied:
            return "AI access denied (HTTP 403). Check your API key permissions."
        case .clientError(let code, _):
            return "Request rejected by the AI service (HTTP \(code)). Try again."
        case .serverError(let code, _):
            return "The AI service is temporarily unavailable (HTTP \(code)). Try again shortly."

        // API body / response
        case .apiOverloaded:
            return "The AI service is overloaded. Try again in a moment."
        case .apiModelRefused:
            return "The AI declined to process this clause. Revise the clause and try again."
        case .responseTruncated:
            return "The AI response was cut off before completing. Try a shorter clause."
        case .invalidResponse:
            return "The AI service returned an unreadable response. Try again."

        // Parsing
        case .variantsSectionMissing:
            return "The AI response was missing the variants block. Try again."
        case .variantsJSONMalformed:
            return "The AI response was not valid JSON. Try again."
        case .variantsKeyMissing(let key):
            return "The AI response was missing the '\(key)' bias. Try again."
        case .variantsEmptyValue(let key):
            return "The AI returned empty text for '\(key)'. Try again."
        case .decodingError:
            return "The AI response could not be decoded. Try again."

        // Legacy
        case .invalidResponseFormat:
            return "The AI response could not be processed. Try again."
        case .networkError:
            return "Network error. Check your connection and try again."
        }
    }

    /// Whether a "Try again" action on the error banner should be offered.
    /// Errors that require the user to change their input, their API key,
    /// or their device state return false.
    var isRetryable: Bool {
        switch self {
        case .missingAPIKey,
             .invalidAPIKey,
             .userKeyInvalidFallbackAvailable,
             .budgetExhausted,
             .modelNotFound,
             .offline,
             .tlsFailure,
             .httpPermissionDenied,
             .apiModelRefused:
            return false
        case .connectionLost,
             .requestTimedOut,
             .cannotReachHost,
             .genericURLError,
             .httpRateLimited, .rateLimited,
             .httpServerError,
             .clientError,
             .serverError,
             .apiOverloaded,
             .responseTruncated,
             .invalidResponse,
             .variantsSectionMissing,
             .variantsJSONMalformed,
             .variantsKeyMissing,
             .variantsEmptyValue,
             .decodingError,
             .invalidResponseFormat,
             .networkError:
            return true
        }
    }
}
