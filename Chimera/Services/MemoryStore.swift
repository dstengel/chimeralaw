// MemoryStore.swift
// Chimera Law
// Owns the SwiftData container for the on-device Memory feature
// (3 manual + 1 auto slot). Single source of truth for read/write/
// auto-save/wipe of `MemoryEntry` rows. Privacy-sensitive: the store
// file lives in Application Support and is encrypted via iOS Data
// Protection class .completeUntilFirstUserAuthentication.

import Foundation
import SwiftData
import Combine
import UIKit
import os

// Replaces a `@objc` selector subscription that caused actor-isolation
// issues on a `@MainActor` singleton. Combine pipeline runs the side
// effect on the main run loop, which already matches `@MainActor` in
// the SwiftUI app target.

@MainActor
final class MemoryStore: ObservableObject {

    // MARK: - Singleton

    static let shared = MemoryStore()

    // MARK: - Published state (drives the UI)

    /// Mirrors `dk_autoSaveMemory` (UserDefaults). Republished on every
    /// `UserDefaults.didChangeNotification` so the plus-sheet's Auto
    /// button greys out at the same UI tick the toggle flips.
    @Published private(set) var isAutoSaveEnabled: Bool = false

    /// Set to `true` when the migration fail-safe wiped the store on
    /// the most recent launch. The drafting view reads-and-clears this
    /// to fire a one-shot toast.
    @Published var didWipeOnMigration: Bool = false

    // MARK: - Storage

    private let logger = Logger(subsystem: "com.daimos.chimera", category: "MemoryStore")
    private let autoSaveKey = "dk_autoSaveMemory"
    private let storeURL: URL
    private var container: ModelContainer?
    private var context: ModelContext?

    /// Pending debounced write. Cancelled and replaced on every
    /// `scheduleAutoSave(snapshot:)` call. Fires a 2-second trailing
    /// upsert into the auto slot.
    private var pendingAutoSaveTask: Task<Void, Never>?

    /// Most recent snapshot queued for auto-save. Reads on
    /// `flushPendingSync()` so the scenePhase.background flush always
    /// writes the latest state even if the debounce never fired.
    private var pendingSnapshot: MemorySnapshot?

    /// Subscription to UserDefaults change notifications, used to
    /// republish `isAutoSaveEnabled` when the SettingsView toggle flips.
    private var userDefaultsSubscription: AnyCancellable?

    // MARK: - Lifecycle

    private init() {
        // Build the store URL under Application Support/Chimera/.
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = support.appendingPathComponent("Chimera", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        self.storeURL = folder.appendingPathComponent("Memory.sqlite")

        openContainer()
        applyFileProtectionIfPossible()

        // Mirror the toggle. The Combine pipeline lets us re-read the
        // value on the main run loop without needing an @objc selector
        // (which conflicts with @MainActor isolation on this singleton).
        self.isAutoSaveEnabled = UserDefaults.standard.bool(forKey: autoSaveKey)
        userDefaultsSubscription = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let newValue = UserDefaults.standard.bool(forKey: self.autoSaveKey)
                if newValue != self.isAutoSaveEnabled {
                    self.isAutoSaveEnabled = newValue
                }
            }
    }

    /// Opens the `ModelContainer` for the Memory schema. On unrecoverable
    /// failure (corrupt store, incompatible schema) the store file is
    /// wiped and a fresh container is created. `didWipeOnMigration` is
    /// set so the UI can surface a one-shot toast on next appearance.
    private func openContainer() {
        let schema = Schema([MemoryEntry.self])
        let configuration = ModelConfiguration(
            "Memory",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            self.container = try ModelContainer(
                for: schema,
                configurations: configuration
            )
        } catch {
            logger.error("Memory container open failed: \(error.localizedDescription, privacy: .public). Wiping and retrying.")
            try? FileManager.default.removeItem(at: storeURL)
            self.didWipeOnMigration = true
            do {
                self.container = try ModelContainer(
                    for: schema,
                    configurations: configuration
                )
            } catch {
                logger.error("Memory container retry failed: \(error.localizedDescription, privacy: .public). Memory disabled this session.")
                self.container = nil
            }
        }

        if let container {
            self.context = ModelContext(container)
        }
    }

    /// Tag the SQLite store file with the iOS Data Protection class
    /// `.completeUntilFirstUserAuthentication`. The file is created
    /// lazily by SwiftData on first write, so this is best-effort: if
    /// the file does not yet exist the call is a no-op and the
    /// attribute is re-applied after the first save in `commit()`.
    private func applyFileProtectionIfPossible() {
        let path = storeURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: path
            )
        } catch {
            logger.error("Set file protection failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // No deinit: this class is a process-lifetime singleton
    // (`MemoryStore.shared`) so the Combine subscription and the
    // SwiftData container live until the app terminates.

    // MARK: - Read API

    /// Returns the entry for the given slot key, or nil if empty.
    func entry(for slotKey: String) -> MemoryEntry? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<MemoryEntry>(
            predicate: #Predicate { $0.slotKey == slotKey }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// All entries currently in the store. Order is not guaranteed.
    func allEntries() -> [MemoryEntry] {
        guard let context else { return [] }
        return (try? context.fetch(FetchDescriptor<MemoryEntry>())) ?? []
    }

    /// True if a row exists for the given slot key.
    func isFilled(_ slotKey: String) -> Bool {
        entry(for: slotKey) != nil
    }

    // MARK: - Write API

    /// Upsert: replace the slot's row with this snapshot, or insert if
    /// the slot was empty. Always overwrites in place.
    func save(_ snapshot: MemorySnapshot, to slotKey: String) {
        guard let context else { return }
        let now = Date()
        if let existing = entry(for: slotKey) {
            snapshot.writeFields(into: existing, savedAt: now)
        } else {
            let entry = snapshot.makeEntry(slotKey: slotKey, savedAt: now)
            context.insert(entry)
        }
        commit()
    }

    /// Removes the row for the given slot key (if any).
    func wipe(slotKey: String) {
        guard let context else { return }
        if let existing = entry(for: slotKey) {
            context.delete(existing)
            commit()
        }
    }

    /// Removes every row from the store. Used by the "Wipe all memory"
    /// destructive button in Settings.
    func wipeAll() {
        guard let context else { return }
        for entry in allEntries() {
            context.delete(entry)
        }
        commit()
    }

    // MARK: - Auto-save

    /// Schedules a debounced 2-second trailing write into the auto
    /// slot. Subsequent calls cancel and replace the pending task.
    /// No-op when auto-save is disabled.
    func scheduleAutoSave(snapshot: MemorySnapshot) {
        guard isAutoSaveEnabled else { return }
        guard hasContentToSave(snapshot) else { return }

        pendingSnapshot = snapshot
        pendingAutoSaveTask?.cancel()
        pendingAutoSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            guard let snapshot = self.pendingSnapshot else { return }
            self.save(snapshot, to: MemorySlot.auto)
            self.pendingSnapshot = nil
        }
    }

    /// Cancel the debounce timer and write the most recent queued
    /// snapshot synchronously. Called from the scenePhase.background
    /// hook in `ChimeraApp.swift`. No-op when auto-save is disabled or
    /// no snapshot is queued.
    func flushPendingSync() {
        pendingAutoSaveTask?.cancel()
        pendingAutoSaveTask = nil
        guard isAutoSaveEnabled, let snapshot = pendingSnapshot else { return }
        save(snapshot, to: MemorySlot.auto)
        pendingSnapshot = nil
    }

    /// True when the snapshot has either an Original or non-whitespace
    /// clauseText. Mirrors the auto-save gate from §6.4 of the plan.
    private func hasContentToSave(_ snapshot: MemorySnapshot) -> Bool {
        if let original = snapshot.originalText, !original.isEmpty {
            return true
        }
        let trimmed = snapshot.clauseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    // MARK: - Helpers

    private func commit() {
        guard let context else { return }
        do {
            try context.save()
            applyFileProtectionIfPossible()
        } catch {
            logger.error("Memory commit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

}
