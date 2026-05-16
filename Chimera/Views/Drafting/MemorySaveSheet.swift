// MemorySaveSheet.swift
// Chimera Law
// The "Save to memory" sheet — three rows, one per manual slot.
// Empty rows show a green outline + faint green fill (free, safe to
// save); filled rows show a red outline + faint red fill (occupied,
// will overwrite). Tapping an empty row writes immediately + dismisses;
// tapping a filled row raises an overwrite confirmation alert.
//
// The Auto slot is NOT shown here — it auto-manages itself. The Auto
// slot is reachable from the plus-sheet's load row instead.

import SwiftUI

struct MemorySaveSheet: View {

    /// Snapshot to save. Captured by the host view at the moment
    /// the toolbar Save button is tapped, so any subsequent edits
    /// before the user picks a slot do not change what is saved.
    let snapshot: MemorySnapshot

    /// Callback fired after a successful save. The host view uses
    /// this to dismiss the sheet, set the toast message, and play
    /// a haptic.
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var memory = MemoryStore.shared

    /// When non-nil, an overwrite confirmation alert is presented
    /// for the slot key it carries.
    @State private var overwriteSlotKey: String?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DKLayout.itemSpacing) {
                    Text("Tap an empty slot to save. Tap a filled slot to overwrite.")
                        .font(.dkCaption)
                        .foregroundStyle(Color.dkTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, DKLayout.itemSpacing)

                    ForEach(MemorySlot.manualSlots, id: \.self) { slotKey in
                        slotRow(for: slotKey)
                    }
                }
                .padding(DKLayout.screenPadding)
            }
            .navigationTitle("Save to memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                overwriteAlertTitle,
                isPresented: Binding(
                    get: { overwriteSlotKey != nil },
                    set: { if !$0 { overwriteSlotKey = nil } }
                ),
                actions: {
                    Button("Overwrite", role: .destructive) {
                        if let slotKey = overwriteSlotKey {
                            commitSave(to: slotKey)
                        }
                        overwriteSlotKey = nil
                    }
                    Button("Cancel", role: .cancel) {
                        overwriteSlotKey = nil
                    }
                },
                message: {
                    Text("This slot already contains a saved draft. The current contents will be replaced.")
                }
            )
        }
    }

    // MARK: - Slot row

    @ViewBuilder
    private func slotRow(for slotKey: String) -> some View {
        let entry = memory.entry(for: slotKey)
        let isFilled = entry != nil
        let outlineColor: Color = isFilled ? .dkError : .dkSuccess
        let backgroundColor: Color = (isFilled ? Color.dkError : Color.dkSuccess).opacity(0.08)

        Button {
            if isFilled {
                overwriteSlotKey = slotKey
            } else {
                commitSave(to: slotKey)
            }
        } label: {
            HStack(alignment: .top, spacing: DKLayout.itemSpacing) {
                Image(systemName: isFilled ? "externaldrive.fill" : "externaldrive")
                    .font(.system(size: 22))
                    .foregroundStyle(outlineColor)
                    .frame(width: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(MemorySlot.displayName(for: slotKey))
                        .font(.dkBody.weight(.semibold))
                        .foregroundStyle(Color.dkTextPrimary)
                    if let entry {
                        Text(entry.titlePreview.isEmpty ? "(no preview)" : entry.titlePreview)
                            .font(.dkCaption)
                            .foregroundStyle(Color.dkTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("Saved \(Self.relativeFormatter.localizedString(for: entry.savedAt, relativeTo: Date()))")
                            .font(.dkCaption)
                            .foregroundStyle(Color.dkTextSecondary)
                    } else {
                        Text("Empty")
                            .font(.dkCaption)
                            .foregroundStyle(Color.dkTextSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DKLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DKLayout.cardCornerRadius)
                    .stroke(outlineColor, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: slotKey, entry: entry))
    }

    // MARK: - Helpers

    private var overwriteAlertTitle: String {
        if let key = overwriteSlotKey {
            return "Overwrite \(MemorySlot.displayName(for: key))?"
        }
        return "Overwrite slot?"
    }

    private func commitSave(to slotKey: String) {
        memory.save(snapshot, to: slotKey)
        let label = MemorySlot.displayName(for: slotKey)
        onSaved(label)
        dismiss()
    }

    private func accessibilityLabel(for slotKey: String, entry: MemoryEntry?) -> String {
        let name = MemorySlot.displayName(for: slotKey)
        if let entry {
            let when = Self.relativeFormatter.localizedString(for: entry.savedAt, relativeTo: Date())
            return "\(name), filled, saved \(when). Double-tap to overwrite."
        } else {
            return "\(name), empty. Double-tap to save."
        }
    }
}
