// OnboardingView.swift
// Chimera Law
// Simplified onboarding: privacy consent only

import SwiftUI

struct OnboardingView: View {

    @EnvironmentObject var appState: AppState

    @State private var consentGiven: Bool = false
    @State private var termsAccepted: Bool = false
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfUse = false
    @State private var isSaving = false

    private var canSubmit: Bool {
        consentGiven && termsAccepted && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .center, spacing: DKLayout.sectionSpacing) {

                    // Header
                    VStack(spacing: 12) {
                        if let uiImage = Self.loadAppIcon() {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                                .accessibilityLabel("Chimera Law app icon")
                        }

                        Text("Welcome to Chimera Law")
                            .font(.dkHeadline)
                            .foregroundColor(.dkTextPrimary)

                        Text("AI-powered clause drafting for German venture-capital lawyers.")
                            .font(.dkBody)
                            .foregroundColor(.dkTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // Offline warning
                    if !NetworkMonitor.shared.isConnected {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.dkError)
                            Text("No internet connection. An active connection is required to complete setup.")
                                .font(.dkCaption)
                                .foregroundColor(.dkError)
                        }
                        .padding(12)
                        .background(Color.dkError.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Consent
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $termsAccepted) {
                            Text("Ich akzeptiere die Nutzungsbedingungen / I accept the Terms of Use")
                                .font(.dkCaption)
                                .foregroundColor(.dkTextPrimary)
                        }
                        .toggleStyle(CheckboxToggleStyle())

                        Button(action: { showTermsOfUse = true }) {
                            Text("Nutzungsbedingungen lesen / Read Terms of Use")
                                .font(.dkCaption)
                                .foregroundColor(.dkPrimary)
                                .underline()
                        }

                        Toggle(isOn: $consentGiven) {
                            Text("Ich habe die Datenschutzerklärung gelesen und akzeptiere sie / I have read and accept the Privacy Policy")
                                .font(.dkCaption)
                                .foregroundColor(.dkTextPrimary)
                        }
                        .toggleStyle(CheckboxToggleStyle())

                        Text("Ihre Eingaben werden von Anthropics Claude-KI verarbeitet. Einzelheiten finden Sie in unserer Datenschutzerklärung. / Your inputs are processed by Anthropic's Claude AI. See our Privacy Policy for details.")
                            .font(.dkCaption)
                            .foregroundColor(.dkTextSecondary)

                        Button(action: { showPrivacyPolicy = true }) {
                            Text("Datenschutzerklärung lesen / Read Privacy Policy")
                                .font(.dkCaption)
                                .foregroundColor(.dkPrimary)
                                .underline()
                        }
                    }
                }
                .padding(.horizontal, DKLayout.screenPadding)
            }

            // Submit button
            VStack(spacing: 0) {
                Divider()
                Button(action: {
                    isSaving = true
                    Task {
                        await appState.completeOnboarding()
                        isSaving = false
                    }
                }) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Get Started")
                    }
                }
                .buttonStyle(DKPrimaryButtonStyle(isEnabled: canSubmit))
                .disabled(!canSubmit)
                .padding(.horizontal, DKLayout.screenPadding)
                .padding(.vertical, 16)
            }
        }
        .background(Color.dkBackground)
        .sheet(isPresented: $showTermsOfUse) {
            NavigationStack {
                TermsOfUseView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: { showTermsOfUse = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.dkTextSecondary)
                            }
                            .accessibilityLabel("Close")
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: { showPrivacyPolicy = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.dkTextSecondary)
                            }
                            .accessibilityLabel("Close")
                        }
                    }
            }
        }
    }

    /// Loads the app icon from the bundle (appiconset requires plist lookup).
    static func loadAppIcon() -> UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let name = files.last {
            return UIImage(named: name)
        }
        return UIImage(named: "AppIcon60x60")
    }
}

// MARK: - Checkbox Toggle Style

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 22))
                .foregroundColor(configuration.isOn ? .dkPrimary : .dkTextSecondary)
                .onTapGesture { configuration.isOn.toggle() }
                .accessibilityLabel(configuration.isOn ? "Checked" : "Unchecked")

            configuration.label
        }
    }
}

// MARK: - Root View

struct RootView: View {

    @EnvironmentObject var appState: AppState
    @AppStorage(LegalVersion.acceptedKey) private var acceptedLegalVersion: String = ""

    /// Persisted flag: true once the user has tapped through the full walkthrough.
    /// Reset automatically when onboarding resets (profile deleted / app reinstalled),
    /// because UserDefaults is cleared on reinstall alongside the profile.
    @AppStorage("dk_walkthrough_seen") private var walkthroughSeen: Bool = false

    /// Persisted flag: true once the user has acknowledged the AI disclaimer
    /// shown after the Terms of Use / Privacy Policy consent. One-time, not
    /// versioned — material wording changes are surfaced via `LegalUpdateView`.
    @AppStorage("dk_ai_disclaimer_acknowledged") private var disclaimerAcknowledged: Bool = false

    private var legalUpdateRequired: Bool {
        // Guard on walkthroughSeen and disclaimerAcknowledged so the
        // legal-update sheet cannot fire while the walkthrough, onboarding,
        // or AI disclaimer are still in progress.
        walkthroughSeen
            && appState.isOnboardingComplete
            && disclaimerAcknowledged
            && acceptedLegalVersion != LegalVersion.current
    }

    var body: some View {
        Group {
            if appState.isLoading {
                TitleScreenView()
            } else if !walkthroughSeen {
                // First launch: show feature walkthrough regardless of CloudKit
                // sync state. Decoupling from isOnboardingComplete prevents
                // a background profile fetch from collapsing the walkthrough
                // mid-flow and jumping straight to MainView.
                WalkthroughView {
                    walkthroughSeen = true
                }
            } else if !appState.isOnboardingComplete {
                OnboardingView()
            } else if !disclaimerAcknowledged {
                AIDisclaimerView {
                    disclaimerAcknowledged = true
                }
            } else {
                MainView()
            }
        }
        .sheet(isPresented: .constant(legalUpdateRequired)) {
            LegalUpdateView()
        }
    }
}

// MARK: - Main View (single tab: Drafting + Settings access)

struct MainView: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        DraftingView()
            .environmentObject(appState)
    }
}
