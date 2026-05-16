// DataModels.swift
// Chimera Law
// Core data models for the app

import Foundation
import SwiftUI

// MARK: - User Profile

struct UserProfile: Codable, Identifiable {
    var id: String
    var name: String
    var dataConsentGiven: Bool
    var createdDate: Date

    init(
        id: String = UUID().uuidString,
        name: String = "",
        dataConsentGiven: Bool = false,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.dataConsentGiven = dataConsentGiven
        self.createdDate = createdDate
    }
}

// MARK: - App Config (from CloudKit)

struct AppConfig {
    var id: String
    var claudeApiKey: String
    var claudeModel: String
    var monthlyBudgetUSD: Double
    var inputPricePer1M: Double
    var outputPricePer1M: Double

    static let defaultModel = "claude-sonnet-4-6"
    static let defaultBudget: Double = 10.0
    static let defaultInputPrice: Double = 3.0
    static let defaultOutputPrice: Double = 15.0
}

// MARK: - Appearance

enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}
