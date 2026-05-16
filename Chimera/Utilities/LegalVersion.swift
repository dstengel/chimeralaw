// LegalVersion.swift
// Chimera Law
// Single source of truth for the current legal document version.
// Bump `current` whenever ToS or Privacy Policy change materially.
// The in-app consent mechanism (LegalUpdateView) fires when
// the stored accepted version does not match `current`.

enum LegalVersion {
    /// Increment on every substantive ToS or Privacy Policy change.
    static let current = "1.1"
    /// UserDefaults key storing the version the user last accepted.
    static let acceptedKey = "dk_legal_version_accepted"
}
