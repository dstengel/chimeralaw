// MonthlyUsage.swift
// Chimera Law
// Token-based monthly usage tracking, adapted from ErbAssist's Dr. Klein model.
// Stored in CloudKit private database.

import Foundation
import CloudKit

struct MonthlyUsage: Identifiable {
    let id: String
    let monthKey: String              // e.g. "2026-03"
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var estimatedCostUSD: Double

    var recordID: CKRecord.ID?

    // MARK: - Computed

    /// Progress from 0.0 to 1.0 against the monthly budget.
    /// Budget value is passed in so it can come from CloudKit AppConfig.
    func budgetProgress(budget: Double) -> Double {
        guard budget > 0 else { return 1.0 }
        return min(estimatedCostUSD / budget, 1.0)
    }

    func isBudgetExhausted(budget: Double) -> Bool {
        estimatedCostUSD >= budget
    }

    // MARK: - Static Helpers

    static var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    // MARK: - Init from CloudKit

    init?(record: CKRecord) {
        self.id = record.recordID.recordName
        self.recordID = record.recordID
        guard let monthKey = record["monthKey"] as? String else {
            return nil
        }
        self.monthKey = monthKey
        self.totalInputTokens = record["totalInputTokens"] as? Int ?? 0
        self.totalOutputTokens = record["totalOutputTokens"] as? Int ?? 0
        self.estimatedCostUSD = record["estimatedCostUSD"] as? Double ?? 0.0
    }

    // MARK: - Init (new)

    init(monthKey: String) {
        self.id = UUID().uuidString
        self.monthKey = monthKey
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.estimatedCostUSD = 0.0
    }

    // MARK: - Mutation

    mutating func addUsage(
        inputTokens: Int,
        outputTokens: Int,
        inputPricePer1M: Double,
        outputPricePer1M: Double
    ) {
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        estimatedCostUSD =
            (Double(totalInputTokens) / 1_000_000.0 * inputPricePer1M) +
            (Double(totalOutputTokens) / 1_000_000.0 * outputPricePer1M)
    }

    // MARK: - CloudKit Record

    static let recordType = "MonthlyUsage"

    func toRecord() -> CKRecord {
        let record: CKRecord
        if let existingID = recordID {
            record = CKRecord(recordType: Self.recordType, recordID: existingID)
        } else {
            record = CKRecord(recordType: Self.recordType)
        }
        record["monthKey"] = monthKey
        record["totalInputTokens"] = totalInputTokens
        record["totalOutputTokens"] = totalOutputTokens
        record["estimatedCostUSD"] = estimatedCostUSD
        return record
    }
}
