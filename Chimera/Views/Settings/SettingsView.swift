// SettingsView.swift
// Chimera Law
// App settings: appearance, API key, subscription, legal

import SwiftUI
import os

struct SettingsView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var network = NetworkMonitor.shared

    @AppStorage("dk_draftingStyle") private var storedStyleRaw: String = DraftingStyle.aplus.rawValue
    @AppStorage("dk_appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("dk_autoTellMeOnLock") private var autoTellMeOnLock: Bool = false
    @AppStorage("dk_autoSaveMemory") private var autoSaveMemory: Bool = false
    @AppStorage("dk_useComplexDiffView") private var useComplexDiffView: Bool = false

    @State private var apiKey: String = ""
    @State private var isValidating = false
    @State private var validationResult: ValidationResult?
    @State private var keyStateVersion: Int = 0  // bumped to refresh status indicator
    @State private var monthlyUsage: MonthlyUsage?

    // Memory section state
    @State private var showDisableAutoSaveAlert: Bool = false
    @State private var showWipeAllMemoryAlert: Bool = false
    @ObservedObject private var memory = MemoryStore.shared

    private let logger = Logger(subsystem: "com.daimos.chimera", category: "Settings")

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Connectivity Warning
                SettingsConnectivityRow(serviceWarning: appState.serviceWarning)

                // MARK: - Drafting Style
                Section(header: Text("Drafting style")) {
                    Picker("Style", selection: $storedStyleRaw) {
                        ForEach(DraftingStyle.allCases) { style in
                            Text(style.label).tag(style.rawValue)
                        }
                    }

                    if let style = DraftingStyle(rawValue: storedStyleRaw) {
                        Text(style.infoDescription)
                            .font(.dkCaption)
                            .foregroundColor(.dkTextSecondary)
                    }
                }

                // MARK: - Tell Me
                Section(header: Text("Tell Me")) {
                    Toggle("Run Tell Me automatically on lock", isOn: $autoTellMeOnLock)

                    Text("When enabled, a Tell Me analysis runs in the background each time you lock a new Original. The Tell Me pill on the Original tab shows the progress and signals when the result is ready.")
                        .font(.dkCaption)
                        .foregroundColor(.dkTextSecondary)
                }

                // MARK: - Memory
                Section(header: Text("Memory")) {
                    Toggle("Auto-save current draft", isOn: autoSaveMemoryBinding)

                    Text("When on, your most recent draft is saved automatically to a fourth memory slot (\"Auto\") on this device. Manual memory slots (1, 2, 3) are always available — tap the memory-disk icon at the top to use them. Nothing is uploaded.")
                        .font(.dkCaption)
                        .foregroundColor(.dkTextSecondary)

                    Button(role: .destructive) {
                        showWipeAllMemoryAlert = true
                    } label: {
                        Text("Wipe all memory")
                    }
                    .disabled(!hasAnyMemoryContent)
                }

                // MARK: - Appearance
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                }

                // MARK: - Changes View
                Section {
                    Toggle("Complex Changes View", isOn: $useComplexDiffView)
                    Text("Shows AI and manual edits in separate colours. Exports always use the simple view.")
                        .font(.dkCaption)
                        .foregroundColor(.dkTextSecondary)
                }

                // MARK: - API Key
                Section(header: Text("Claude API Key")) {

                    // Budget bar (system key only). While offline, the
                    // displayed value is the last-synced CloudKit usage —
                    // still informative but may be slightly stale. Marked
                    // with a "(cached)" suffix so the user is aware.
                    if !service.isUsingUserKey {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.dkTextSecondary)
                                Text(network.isConnected ? "Monthly budget" : "Monthly budget (cached)")
                                    .font(.system(size: 15))
                                    .foregroundColor(.dkTextPrimary)
                                Spacer()
                                Text("\(Int(budgetProgress * 100))%")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(budgetBarColor)
                                    .opacity(network.isConnected ? 1.0 : 0.6)
                            }

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 6)
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(budgetBarColor)
                                            .frame(
                                                width: geo.size.width * budgetProgress,
                                                height: 6
                                            )
                                    }
                            }
                            .frame(height: 6)
                            .opacity(network.isConnected ? 1.0 : 0.6)
                            .accessibilityLabel(
                                "Monthly budget \(Int(budgetProgress * 100)) percent used"
                            )
                        }
                    }

                    // Live status: which key is active right now
                    HStack(spacing: 8) {
                        Image(systemName: activeKeyIcon)
                            .foregroundColor(activeKeyColor)
                        Text(activeKeyLabel)
                            .font(.dkCaption)
                            .foregroundColor(.dkTextPrimary)
                        Spacer()
                        Text(activeKeyBadge)
                            .font(.dkCaption.weight(.medium))
                            .foregroundColor(activeKeyColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(activeKeyColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .id(keyStateVersion) // forces re-render when key changes

                    SecureField("API Key (optional)", text: $apiKey)
                        .font(.dkBody)
                        .autocapitalization(.none)
                        .textContentType(.password)

                    if let result = validationResult {
                        HStack {
                            Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.isValid ? .dkSuccess : .dkError)
                            Text(result.message)
                                .font(.dkCaption)
                                .foregroundColor(result.isValid ? .dkSuccess : .dkError)
                        }
                    }

                    HStack {
                        Button("Save Key") {
                            saveAPIKey()
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)

                        if isValidating {
                            ProgressView().padding(.leading, 8)
                        }

                        Spacer()

                        if KeychainHelper.read(key: KeychainHelper.userAPIKeyIdentifier) != nil {
                            Button("Remove Key", role: .destructive) {
                                KeychainHelper.delete(key: KeychainHelper.userAPIKeyIdentifier)
                                apiKey = ""
                                validationResult = ValidationResult(isValid: true, message: "Key removed")
                                keyStateVersion += 1
                            }
                        }
                    }

                    Text("Bring Your Own Key (BYOK): You may provide your own Anthropic API key if you already have one. This app does not facilitate or sell API keys. Your key is stored securely in the device Keychain and usage is subject to your Anthropic account terms.\n\nProviding your own key does not unlock any additional functionality. An active App Store subscription is always required to use Chimera Law.")
                        .font(.dkCaption)
                        .foregroundColor(.dkTextSecondary)
                }

                // MARK: - Subscription
                Section(header: Text("Subscription")) {
                    Button(action: {
                        Task { await StoreKitService.shared.restore() }
                    }) {
                        HStack {
                            Text("Restore Purchase")
                            Spacer()
                            if StoreKitService.shared.isSubscribed {
                                Text("Active")
                                    .font(.dkCaption)
                                    .foregroundColor(.dkSuccess)
                            }
                        }
                    }

                    Text("If you previously subscribed, tap Restore Purchase to reactivate. Subscriptions are managed through your Apple ID in the App Store.")
                        .font(.dkCaption)
                        .foregroundColor(.dkTextSecondary)
                }

                // MARK: - Legal / Rechtliches
                Section(header: Text("Rechtliches / Legal")) {
                    NavigationLink("Impressum / Imprint") {
                        ImpressumView()
                    }

                    NavigationLink("Datenschutz / Privacy Policy") {
                        PrivacyPolicyView()
                    }

                    NavigationLink("Nutzungsbedingungen / Terms of Use") {
                        TermsOfUseView()
                    }

                    Link(destination: URL(string: "https://www.anthropic.com/privacy")!) {
                        HStack {
                            Text("Anthropic-Datenschutz / Anthropic Privacy")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .font(.caption)
                                .foregroundColor(.dkTextSecondary)
                        }
                    }

                    Link(destination: URL(string: "https://www.apple.com/legal/privacy/")!) {
                        HStack {
                            Text("Apple-Datenschutz / Apple Privacy")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .font(.caption)
                                .foregroundColor(.dkTextSecondary)
                        }
                    }
                }

                // MARK: - About
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion).foregroundColor(.dkTextSecondary)
                    }

                    HStack {
                        Text("Developer")
                        Spacer()
                        Text("Daniel Stengel-Dori").foregroundColor(.dkTextSecondary)
                    }

                    HStack {
                        Text("Copyright")
                        Spacer()
                        Text("\u{00A9} 2026 Daniel Stengel-Dori")
                            .font(.dkCaption)
                            .foregroundColor(.dkTextSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dkBody)
                }
            }
            .onAppear {
                if let existingKey = KeychainHelper.read(key: KeychainHelper.userAPIKeyIdentifier) {
                    apiKey = existingKey
                }
                Task {
                    monthlyUsage = try? await CloudKitService.shared.fetchOrCreateMonthlyUsage()
                }
            }
            .alert(
                "Disable auto-save?",
                isPresented: $showDisableAutoSaveAlert,
                actions: {
                    Button("Disable and clear", role: .destructive) {
                        autoSaveMemory = false
                        memory.wipe(slotKey: MemorySlot.auto)
                    }
                    Button("Cancel", role: .cancel) {
                        // Republish the unchanged @AppStorage value to
                        // force the Toggle's visual state back to ON.
                        autoSaveMemory = true
                    }
                },
                message: {
                    Text("The Auto memory slot will be cleared. Memory 1, 2, and 3 are not affected.")
                }
            )
            .alert(
                "Wipe all memory?",
                isPresented: $showWipeAllMemoryAlert,
                actions: {
                    Button("Wipe", role: .destructive) {
                        memory.wipeAll()
                    }
                    Button("Cancel", role: .cancel) { }
                },
                message: {
                    Text("All saved drafts in Memory 1, 2, 3, and Auto will be deleted. This cannot be undone.")
                }
            )
        }
    }

    // MARK: - Memory helpers

    /// Mediates the @AppStorage toggle so the user must confirm
    /// turning auto-save OFF (which wipes the Auto slot). Turning it
    /// ON commits immediately.
    private var autoSaveMemoryBinding: Binding<Bool> {
        Binding(
            get: { autoSaveMemory },
            set: { newValue in
                if newValue == false && autoSaveMemory == true {
                    showDisableAutoSaveAlert = true
                } else {
                    autoSaveMemory = newValue
                }
            }
        )
    }

    /// True when at least one of the four slots is filled. Drives the
    /// "Wipe all memory" button's enabled state.
    private var hasAnyMemoryContent: Bool {
        for slot in MemorySlot.allSlots where memory.isFilled(slot) {
            return true
        }
        return false
    }

    // MARK: - Budget

    private var budgetProgress: Double {
        guard !service.isUsingUserKey else { return 0 }
        return monthlyUsage?.budgetProgress(budget: service.monthlyBudgetUSD) ?? 0
    }

    private var budgetBarColor: Color {
        if budgetProgress >= 1.0 { return .dkError }
        if budgetProgress >= 0.75 { return .dkWarning }
        return .dkSuccess
    }

    // MARK: - App Version

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Active Key Status

    private var service: DraftingService { DraftingService.shared }

    private var activeKeyIcon: String {
        if service.isUsingUserKey {
            return "person.crop.circle.badge.checkmark"
        } else if !service.systemApiKey.isEmpty {
            return "server.rack"
        } else {
            return "exclamationmark.triangle"
        }
    }

    private var activeKeyLabel: String {
        if service.isUsingUserKey {
            return "Using your API key"
        } else if !service.systemApiKey.isEmpty {
            return "Using app API key"
        } else {
            return "No API key configured"
        }
    }

    private var activeKeyBadge: String {
        if service.isUsingUserKey {
            return "Personal"
        } else if !service.systemApiKey.isEmpty {
            return "System"
        } else {
            return "None"
        }
    }

    private var activeKeyColor: Color {
        if service.isUsingUserKey {
            return .dkPrimary
        } else if !service.systemApiKey.isEmpty {
            return .dkSuccess
        } else {
            return .dkWarning
        }
    }

    // MARK: - API Key Validation

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { return }

        isValidating = true
        validationResult = nil

        Task {
            let isValid = await validateAPIKey(trimmedKey)
            isValidating = false

            if isValid {
                KeychainHelper.save(key: KeychainHelper.userAPIKeyIdentifier, value: trimmedKey)
                validationResult = ValidationResult(isValid: true, message: "Key validated and saved")
                keyStateVersion += 1
            } else {
                validationResult = ValidationResult(isValid: false, message: "Invalid API key")
            }
        }
    }

    private func validateAPIKey(_ key: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(key, forHTTPHeaderField: "x-api-key")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "test"]]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return false
        }
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // 200 = valid, 401 = invalid key
                return httpResponse.statusCode != 401
            }
            return false
        } catch {
            logger.error("API key validation failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Validation Result

private struct ValidationResult {
    let isValid: Bool
    let message: String
}
