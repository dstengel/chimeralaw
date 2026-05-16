// TitleScreenView.swift
// Chimera Law
// Loading splash screen with premium app branding

import SwiftUI

struct TitleScreenView: View {

    @State private var logoScale: CGFloat = 0.95
    @State private var taglineOpacity: Double = 0
    @State private var spinnerOpacity: Double = 1

    var body: some View {
        ZStack {
            Color.dkBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    // App icon (adaptive: light/dark variant chosen by system)
                    Image("AppIconDisplay")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 40))
                        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
                        .scaleEffect(logoScale)
                        .accessibilityLabel("Chimera Law app icon")

                    // Tagline
                    Text("Venture-capital drafting.\nPowered by AI.")
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundColor(.dkTextSecondary)
                        .multilineTextAlignment(.center)
                        .tracking(0.8)
                        .opacity(taglineOpacity)

                    // Loading indicator — visible immediately
                    ProgressView()
                        .tint(Color.dkPrimary.opacity(0.6))
                        .scaleEffect(1.1)
                        .opacity(spinnerOpacity)
                        .padding(.top, 12)
                }

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                logoScale = 1.0
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.15)) {
                taglineOpacity = 1.0
            }
        }
    }
}
