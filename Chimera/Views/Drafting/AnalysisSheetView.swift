// AnalysisSheetView.swift
// Chimera Law
// Dismissable sheet presenting a structured Tell Me clause analysis.
// Headline card, dashboard (Bias/Risk/Market), and 8 detail sections.

import SwiftUI

// MARK: - Analysis Sheet

struct AnalysisSheetView: View {

    @ObservedObject var viewModel: DraftingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isAnalysing {
                    loadingView
                } else if let error = viewModel.analysisError {
                    errorView(error)
                } else if let result = viewModel.analysisResult {
                    resultsView(result)
                } else {
                    // Fallback — should not normally appear.
                    loadingView
                }
            }
            .background(Color.dkBackground)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dkBody)
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.6)
                .tint(.dkPrimary)
            AnalysisLoadingLabel()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.dkError)
            Text(message)
                .font(.dkCaption)
                .foregroundColor(.dkTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !viewModel.isBudgetExhausted {
                Button("Try Again") {
                    viewModel.analyseOriginal()
                }
                .font(.dkBody.weight(.medium))
                .foregroundColor(.dkPrimary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results

    private func resultsView(_ result: String) -> some View {
        let parsed = AnalysisPrompts.parseAnalysis(result)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: DKLayout.subSectionSpacing) {

                // Headline
                if let headline = parsed.headline {
                    MarkdownText(headline)
                        .padding(DKLayout.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.dkPrimary.opacity(0.08))
                        .cornerRadius(DKLayout.cardCornerRadius)
                }

                // Dashboard
                if let dashboard = parsed.dashboard {
                    AnalysisDashboardCard(dashboard: dashboard)
                }

                // Sections
                ForEach(parsed.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.dkSubheadline)
                            .foregroundColor(.dkPrimary)
                        MarkdownText(section.body)
                    }
                    .padding(DKLayout.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dkSecondary)
                    .cornerRadius(DKLayout.cardCornerRadius)
                }

                // Fallback
                if parsed.sections.isEmpty && parsed.headline == nil {
                    MarkdownText(result)
                        .padding(DKLayout.cardPadding)
                        .background(Color.dkSecondary)
                        .cornerRadius(DKLayout.cardCornerRadius)
                }
            }
            .padding(.horizontal, DKLayout.screenPadding)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Dashboard Card

struct AnalysisDashboardCard: View {

    let dashboard: AnalysisPrompts.DashboardData

    var body: some View {
        VStack(spacing: 12) {
            // Bias scale
            VStack(spacing: 6) {
                Text("Bias")
                    .font(.dkLabel)
                    .foregroundColor(.dkTextSecondary)

                HStack(spacing: 0) {
                    Text("B")
                        .font(.dkCaption.weight(.medium))
                        .foregroundColor(.dkTextSecondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(biasGradient)
                                .frame(height: 8)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .offset(x: biasOffset(for: dashboard.biasScore, in: geo.size.width))
                        }
                    }
                    .frame(height: 14)
                    Text("L")
                        .font(.dkCaption.weight(.medium))
                        .foregroundColor(.dkTextSecondary)
                }
                .padding(.horizontal, 4)

                Text(dashboard.biasLabel)
                    .font(.dkCaption)
                    .foregroundColor(.dkTextSecondary)
            }

            Divider()

            // Risk + Market Standard
            HStack {
                VStack(spacing: 4) {
                    Text("Risk")
                        .font(.dkLabel)
                        .foregroundColor(.dkTextSecondary)
                    HStack(spacing: 3) {
                        ForEach(0..<3) { i in
                            Image(systemName: i < dashboard.riskLevel
                                  ? "exclamationmark.triangle.fill"
                                  : "exclamationmark.triangle")
                                .font(.system(size: 14))
                                .foregroundColor(
                                    i < dashboard.riskLevel
                                    ? riskColor(dashboard.riskLevel)
                                    : Color(.systemGray4)
                                )
                        }
                    }
                    Text(dashboard.riskLabel)
                        .font(.dkCaption)
                        .foregroundColor(.dkTextSecondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 50)

                VStack(spacing: 4) {
                    Text("Market Std.")
                        .font(.dkLabel)
                        .foregroundColor(.dkTextSecondary)
                    Image(systemName: dashboard.marketStandardIcon)
                        .font(.system(size: 20))
                        .foregroundColor(dashboard.marketStandardColor)
                    Text(dashboard.marketStandardLabel)
                        .font(.dkCaption)
                        .foregroundColor(.dkTextSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(DKLayout.cardPadding)
        .background(Color.dkSecondary)
        .cornerRadius(DKLayout.cardCornerRadius)
    }

    // MARK: - Helpers

    private var biasGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .blue.opacity(0.3), .gray.opacity(0.3), .orange.opacity(0.3), .orange],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func biasOffset(for score: Int, in width: CGFloat) -> CGFloat {
        let clamped = max(-2, min(2, score))
        let normalized = (CGFloat(clamped) + 2.0) / 4.0
        return (width - 14) * normalized
    }

    private func riskColor(_ level: Int) -> Color {
        switch level {
        case 1: return .orange
        case 2: return .orange
        case 3: return .dkError
        default: return .dkTextSecondary
        }
    }
}

// MARK: - Analysis Loading Label

/// Cycles through analysis-stage labels while the AI processes.
private struct AnalysisLoadingLabel: View {

    private static let phases = [
        "Reading the clause...",
        "Assessing bias and risk...",
        "Checking against market standard...",
        "Compiling the analysis...",
        "Taking a little longer, but the result will be worth it..."
    ]

    private static let phaseDelays: [TimeInterval] = [4.0, 8.0, 14.0, 24.0]

    @State private var phaseIndex: Int = 0
    @State private var opacity: Double = 1.0

    var body: some View {
        Text(Self.phases[min(phaseIndex, Self.phases.count - 1)])
            .font(.dkCaption)
            .foregroundColor(.dkTextSecondary)
            .opacity(opacity)
            .onAppear { scheduleNextPhase(step: 0) }
    }

    private func scheduleNextPhase(step: Int) {
        guard step < Self.phaseDelays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.phaseDelays[step]) {
            withAnimation(.easeOut(duration: 0.15)) { opacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                phaseIndex = step + 1
                withAnimation(.easeIn(duration: 0.2)) { opacity = 1 }
            }
            scheduleNextPhase(step: step + 1)
        }
    }
}

// MARK: - Markdown Text Renderer

/// Renders a string with basic Markdown formatting (**bold**, *italic*).
struct MarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.dkBody)
                .foregroundColor(.dkTextPrimary)
        } else {
            Text(text)
                .font(.dkBody)
                .foregroundColor(.dkTextPrimary)
        }
    }
}
