// ConnectivityBanner.swift
// Chimera Law
// Reusable offline / service-unavailable banner for the drafting screen

import SwiftUI

// MARK: - Connectivity Banner

/// Displays a compact, non-intrusive warning when the device is offline
/// or a backend service (iCloud, Anthropic) is unreachable.
struct ConnectivityBanner: View {

    @ObservedObject private var network = NetworkMonitor.shared

    /// Optional extra message surfaced by AppState when a specific
    /// service fails (e.g. "iCloud sync failed").
    var serviceWarning: String?

    /// Resolved display state.
    private var bannerState: BannerState {
        if !network.isConnected {
            return .offline
        }
        if let warning = serviceWarning, !warning.isEmpty {
            return .serviceIssue(warning)
        }
        return .ok
    }

    var body: some View {
        switch bannerState {
        case .ok:
            EmptyView()

        case .offline:
            bannerRow(
                icon: "wifi.slash",
                text: "No internet connection. Rephrasing, AI analysis, OCR clean-up, and sync are unavailable.",
                color: .dkError
            )

        case .serviceIssue(let message):
            bannerRow(
                icon: "exclamationmark.icloud",
                text: message,
                color: .dkWarning
            )
        }
    }

    // MARK: - Helpers

    private func bannerRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.dkTextPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.2), lineWidth: 0.5)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private enum BannerState {
        case ok
        case offline
        case serviceIssue(String)
    }
}

// MARK: - Drafting Error Banner

/// Shares the visual language of `ConnectivityBanner` for rephrase /
/// clean-up failures surfaced by `DraftingViewModel.errorMessage`. Rendered
/// at the top of the drafting content area so all user-facing failures
/// appear in the same location regardless of cause. Offers a "Try again"
/// trailing button when the view model reports the error as retryable
/// (governed by `DraftingError.isRetryable`).
struct DraftingErrorBanner: View {

    /// The user-facing message to display. Callers should pass
    /// `viewModel.errorMessage`; the banner hides itself when nil.
    let message: String?

    /// True when a retry closure was captured for this error. Drives the
    /// visibility of the trailing button.
    let canRetry: Bool

    /// Invoked when the user taps "Try again". No-op when `canRetry` is
    /// false.
    let onRetry: () -> Void

    /// Optional tap action for the banner body (e.g. dismiss). Does not
    /// fire when the user taps the "Try again" button.
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let message, !message.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.dkError)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.dkTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if canRetry {
                    Button(action: onRetry) {
                        Text("Try again")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.dkError)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.dkError.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Try again")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.dkError.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.dkError.opacity(0.2), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Compact Settings Warning

/// A smaller inline warning for use inside Form / List sections.
struct SettingsConnectivityRow: View {

    @ObservedObject private var network = NetworkMonitor.shared
    var serviceWarning: String?

    var body: some View {
        if !network.isConnected {
            row(icon: "wifi.slash",
                text: "You are offline. Some features may be unavailable.",
                color: .dkError)
        } else if let warning = serviceWarning, !warning.isEmpty {
            row(icon: "exclamationmark.icloud",
                text: warning,
                color: .dkWarning)
        }
    }

    private func row(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(text)
                .font(.dkCaption)
                .foregroundColor(color)
        }
    }
}
