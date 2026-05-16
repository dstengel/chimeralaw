// CloudKitService.swift
// Chimera Law
// CloudKit operations for AppConfig, UserProfile, and MonthlyUsage

import Foundation
import CloudKit
import os

@MainActor
final class CloudKitService {

    static let shared = CloudKitService()

    private let container: CKContainer
    private let publicDB: CKDatabase
    private let privateDB: CKDatabase
    private let logger = Logger(subsystem: "com.daimos.chimera", category: "CloudKit")

    private init() {
        container = CKContainer(identifier: "iCloud.com.daimos.chimera")
        publicDB = container.publicCloudDatabase
        privateDB = container.privateCloudDatabase
    }

    // MARK: - AppConfig (Public DB)

    func fetchAppConfig() async throws -> AppConfig {
        let query = CKQuery(
            recordType: "AppConfig",
            predicate: NSPredicate(value: true)
        )

        let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)

        guard let (_, result) = results.first else {
            throw CloudKitError.configNotFound
        }

        let record = try result.get()

        return AppConfig(
            id: record.recordID.recordName,
            claudeApiKey: record["claudeApiKey"] as? String ?? "",
            claudeModel: record["claudeModel"] as? String ?? AppConfig.defaultModel,
            monthlyBudgetUSD: record["monthlyBudgetUSD"] as? Double ?? AppConfig.defaultBudget,
            inputPricePer1M: record["inputPricePer1M"] as? Double ?? AppConfig.defaultInputPrice,
            outputPricePer1M: record["outputPricePer1M"] as? Double ?? AppConfig.defaultOutputPrice
        )
    }

    // MARK: - UserProfile (Private DB)

    func fetchOrCreateUserProfile() async throws -> UserProfile? {
        let query = CKQuery(
            recordType: "UserProfile",
            predicate: NSPredicate(value: true)
        )

        let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)

        if let (_, result) = results.first {
            let record = try result.get()
            return UserProfile(
                id: record.recordID.recordName,
                name: record["name"] as? String ?? "",
                dataConsentGiven: record["dataConsentGiven"] as? Bool ?? false,
                createdDate: record.creationDate ?? Date()
            )
        }

        return nil
    }

    func saveUserProfile(_ profile: UserProfile) async throws {
        let record = CKRecord(recordType: "UserProfile")
        record["name"] = profile.name
        record["dataConsentGiven"] = profile.dataConsentGiven

        try await privateDB.save(record)
        logger.info("User profile saved to CloudKit")
    }

    // MARK: - MonthlyUsage (Private DB)

    func fetchOrCreateMonthlyUsage() async throws -> MonthlyUsage {
        let monthKey = MonthlyUsage.currentMonthKey
        let predicate = NSPredicate(format: "monthKey == %@", monthKey)
        let query = CKQuery(recordType: MonthlyUsage.recordType, predicate: predicate)

        let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)

        if let (_, result) = results.first {
            let record = try result.get()
            if let usage = MonthlyUsage(record: record) {
                return usage
            }
        }

        // Create new monthly record
        var usage = MonthlyUsage(monthKey: monthKey)
        let record = usage.toRecord()
        let savedRecord = try await privateDB.save(record)
        usage.recordID = savedRecord.recordID
        return usage
    }

    func saveMonthlyUsage(_ usage: MonthlyUsage) async throws {
        let record = usage.toRecord()

        if usage.recordID != nil {
            // Fetch existing, update fields, re-save (CKModifyRecordsOperation pattern)
            do {
                let existingRecord = try await privateDB.record(for: record.recordID)
                existingRecord["totalInputTokens"] = usage.totalInputTokens
                existingRecord["totalOutputTokens"] = usage.totalOutputTokens
                existingRecord["estimatedCostUSD"] = usage.estimatedCostUSD
                try await privateDB.save(existingRecord)
            } catch {
                // Fallback: save new
                try await privateDB.save(record)
            }
        } else {
            try await privateDB.save(record)
        }
    }
}

// MARK: - Errors

enum CloudKitError: LocalizedError {
    case configNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "App configuration not found. Please check your internet connection."
        case .saveFailed(let detail):
            return "Failed to save data: \(detail)"
        }
    }
}
