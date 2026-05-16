// FixesEmptyView.swift
// Chimera Law
// Empty state for the Revise sheet. Shown when the model returned three
// empty arrays, OR when every returned item was dropped by pre-
// validation / dedupe. Single centred message, single Done button.
// The empty result is cached the same way a non-empty result is — re-
// tapping does not re-fire the API call until the cache invalidates.

import SwiftUI

struct FixesEmptyView: View {

    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.dkPrimary)

            Text("Chimera Law found no concrete revisions for this clause. The analysis suggests it is in line with market standard.")
                .font(.dkBody)
                .foregroundColor(.dkTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Done") {
                onDismiss()
            }
            .font(.dkBody.weight(.medium))
            .foregroundColor(.dkPrimary)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
