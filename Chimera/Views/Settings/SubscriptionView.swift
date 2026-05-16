// SubscriptionView.swift
// Chimera Law
// Subscription screen with feature overview and purchase flow

import SwiftUI
import StoreKit

struct SubscriptionView: View {

    @StateObject private var storeKit = StoreKitService.shared
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: - Connectivity Warning
                if !NetworkMonitor.shared.isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.dkError)
                        Text("You are offline. Purchases and restore require an internet connection.")
                            .font(.system(size: 13))
                            .foregroundColor(.dkTextPrimary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dkError.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, DKLayout.screenPadding)
                    .padding(.top, 16)
                }

                // MARK: - Hero

                VStack(spacing: 16) {
                    if let uiImage = Self.loadAppIcon() {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    }

                    VStack(spacing: 6) {
                        Text("Chimera Law")
                            .font(.dkHeadline)
                            .foregroundColor(.dkTextPrimary)

                        Text("AI-powered clause drafting for German venture-capital lawyers. Rephrase across deal stages, shift between founder and investor bias, and export with redline tracking.")
                            .font(.dkCaption)
                            .foregroundColor(.dkTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 32)
                .padding(.bottom, 28)
                .padding(.horizontal, DKLayout.screenPadding)

                // MARK: - Features

                VStack(spacing: 0) {
                    featureRow(
                        icon: "building.columns",
                        title: "7 Deal-Stage Personas",
                        subtitle: "Term Sheet, Series Seed, Series A+, Convertible, Exit, Cross-Border, Plain Language"
                    )
                    featureDivider()
                    featureRow(
                        icon: "slider.horizontal.3",
                        title: "Founder / Investor Orientation",
                        subtitle: "5-level heat control from F2 to I2, all variants generated in one call"
                    )
                    featureDivider()
                    featureRow(
                        icon: "text.badge.checkmark",
                        title: "Word-Level Redline",
                        subtitle: "Three-tab view with Original, Show Changes, and Output"
                    )
                    featureDivider()
                    featureRow(
                        icon: "square.and.arrow.up",
                        title: "Export as Word & PDF",
                        subtitle: "Share, copy, or export with full redline tracking"
                    )
                    featureDivider()
                    featureRow(
                        icon: "camera.viewfinder",
                        title: "Camera & OCR",
                        subtitle: "Scan clauses from printed documents with AI cleanup"
                    )
                    featureDivider()
                    featureRow(
                        icon: "microphone",
                        title: "Voice & Additional Instructions",
                        subtitle: "Dictate or type supplementary context for each rephrase"
                    )
                    featureDivider()
                    featureRow(
                        icon: "bolt.shield",
                        title: "Monthly AI Budget Included",
                        subtitle: "Or bring your own Anthropic API key"
                    )
                }
                .padding(.vertical, 4)
                .background(Color.dkSurface)
                .clipShape(RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius)
                        .stroke(Color(.systemGray5), lineWidth: 0.5)
                )
                .padding(.horizontal, DKLayout.screenPadding)

                // MARK: - Status / Action

                if storeKit.isSubscribed {
                    subscribedSection
                        .padding(.top, 28)
                } else {
                    purchaseSection
                        .padding(.top, 28)
                }

                // MARK: - Restore

                Button("Restore Purchases") {
                    Task { await storeKit.restore() }
                }
                .font(.dkCaption)
                .foregroundColor(.dkPrimary)
                .padding(.top, 16)

                // MARK: - Legal

                Text("Payment is charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. You can manage and cancel your subscription in your Apple ID account settings.")
                    .font(.system(size: 12))
                    .foregroundColor(.dkTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DKLayout.screenPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
            }
        }
        .background(Color.dkBackground)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorText)
        }
        .onChange(of: storeKit.purchaseState) { _, state in
            if case .failed(let msg) = state {
                errorText = msg
                showError = true
            }
        }
        .task { await storeKit.loadProduct() }
    }

    // MARK: - Subscribed

    private var subscribedSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.dkSuccess)
                Text("Subscription Active")
                    .font(.dkBody.weight(.semibold))
                    .foregroundColor(.dkSuccess)
            }

            Button("Manage in App Store") {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(DKSecondaryButtonStyle())
            .padding(.horizontal, DKLayout.screenPadding)
        }
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 16) {
            Text("14-day free trial included")
                .font(.dkCaption)
                .foregroundColor(.dkAccent)

            Button(action: {
                Task { await storeKit.purchase() }
            }) {
                if storeKit.purchaseState == .purchasing {
                    ProgressView().tint(.white)
                } else {
                    Text("Start Free Trial")
                }
            }
            .buttonStyle(DKPrimaryButtonStyle(isEnabled: storeKit.product != nil))
            .disabled(storeKit.product == nil || storeKit.purchaseState == .purchasing)
            .padding(.horizontal, DKLayout.screenPadding)
        }
    }

    // MARK: - Feature Row

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.dkPrimary)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dkBody)
                    .foregroundColor(.dkTextPrimary)
                Text(subtitle)
                    .font(.dkCaption)
                    .foregroundColor(.dkTextSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func featureDivider() -> some View {
        Divider()
            .padding(.leading, 58)
    }

    // MARK: - App Icon Loader

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
