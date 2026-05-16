// LegalUpdateView.swift
// Chimera Law
// Non-dismissible sheet shown when the stored accepted legal version
// does not match LegalVersion.current. Requires explicit acknowledgement
// of both ToS and Privacy Policy before the user may continue.
// Satisfies the "explicit re-consent for material changes" requirement
// that replaces the void "continued use = acceptance" clause (§ 307 BGB).

import SwiftUI

struct LegalUpdateView: View {

    @AppStorage(LegalVersion.acceptedKey) private var acceptedVersion: String = ""

    @State private var tosRead: Bool = false
    @State private var privacyRead: Bool = false
    @State private var showToS: Bool = false
    @State private var showPrivacy: Bool = false

    private var canConfirm: Bool { tosRead && privacyRead }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Legal Documents Updated", systemImage: "doc.badge.ellipsis")
                            .font(.dkHeadline)
                            .foregroundColor(.dkTextPrimary)
                        Text("Our Terms of Use and Privacy Policy have been updated. Please review and acknowledge both documents to continue using Chimera Law.")
                            .font(.dkBody)
                            .foregroundColor(.dkTextSecondary)
                    }

                    Divider()

                    // ToS toggle
                    Toggle(isOn: $tosRead) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I have read and understood the")
                                .font(.dkBody)
                                .foregroundColor(.dkTextPrimary)
                            Button("Terms of Use") { showToS = true }
                                .font(.dkBody)
                                .foregroundColor(.dkPrimary)
                                .underline()
                        }
                    }
                    .toggleStyle(CheckboxToggleStyle())

                    // Privacy toggle
                    Toggle(isOn: $privacyRead) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I have read and understood the")
                                .font(.dkBody)
                                .foregroundColor(.dkTextPrimary)
                            Button("Privacy Policy") { showPrivacy = true }
                                .font(.dkBody)
                                .foregroundColor(.dkPrimary)
                                .underline()
                        }
                    }
                    .toggleStyle(CheckboxToggleStyle())

                    Divider()

                    // Opt-out note
                    Text("If you do not agree, you may cancel your subscription and delete the app at any time.")
                        .font(.dkCaption)
                        .foregroundColor(.dkTextSecondary)

                    // Confirm button
                    Button {
                        acceptedVersion = LegalVersion.current
                    } label: {
                        Text("Confirm — I have taken note")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DKPrimaryButtonStyle(isEnabled: canConfirm))
                    .disabled(!canConfirm)
                }
                .padding(DKLayout.screenPadding)
            }
            .navigationTitle("Legal Update")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showToS) {
            NavigationStack {
                TermsOfUseView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showToS = false } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.dkTextSecondary)
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showPrivacy = false } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.dkTextSecondary)
                            }
                        }
                    }
            }
        }
    }
}
