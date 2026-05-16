// DraftingViewToolbar.swift
// Chimera Law
// Legacy toolbar and input row -- retained for backward compatibility.
// The main DraftingView now uses inline components instead.

import SwiftUI

// MARK: - Toolbar Row (legacy, no longer displayed)

struct DraftingToolbarRow: View {

    @ObservedObject var viewModel: DraftingViewModel
    let onShowImagePicker: () -> Void
    let onShowCamera: () -> Void

    var body: some View {
        EmptyView()
    }
}

// MARK: - Input Row (legacy, no longer displayed)

struct DraftingInputRow: View {

    @ObservedObject var viewModel: DraftingViewModel

    var body: some View {
        EmptyView()
    }
}
