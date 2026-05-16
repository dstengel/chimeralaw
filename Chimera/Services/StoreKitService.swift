// StoreKitService.swift
// Chimera Law
// StoreKit 2 subscription management: EUR 15/month, 14-day free trial

import Foundation
import Combine
import StoreKit
import os

@MainActor
final class StoreKitService: ObservableObject {

    static let shared = StoreKitService()

    // MARK: - Product ID

    static let monthlyProductID = "com.daimos.chimera.premium.monthly"

    // MARK: - Published

    @Published var isSubscribed: Bool = false
    @Published var product: Product?
    @Published var purchaseState: PurchaseState = .idle

    private let logger = Logger(subsystem: "com.daimos.chimera", category: "StoreKit")
    private var transactionListener: Task<Void, Never>?

    // MARK: - Init

    private init() {
        transactionListener = listenForTransactionUpdates()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Product

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.monthlyProductID])
            if let monthly = products.first {
                self.product = monthly
            }
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Check Entitlements

    func checkCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.monthlyProductID {
                self.isSubscribed = true
                return
            }
        }
        self.isSubscribed = false
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product else {
            purchaseState = .failed("Product not available. Please try again.")
            return
        }

        purchaseState = .purchasing

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    self.isSubscribed = true
                    self.purchaseState = .purchased
                case .unverified:
                    self.purchaseState = .failed("Purchase could not be verified.")
                }
            case .userCancelled:
                self.purchaseState = .idle
            case .pending:
                self.purchaseState = .idle
            @unknown default:
                self.purchaseState = .idle
            }
        } catch {
            self.purchaseState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Restore

    func restore() async {
        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
            if isSubscribed {
                purchaseState = .restored
            }
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    let productID = transaction.productID
                    await MainActor.run { [weak self] in
                        if productID == StoreKitService.monthlyProductID {
                            self?.isSubscribed = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Purchase State

enum PurchaseState: Equatable {
    case idle
    case purchasing
    case purchased
    case failed(String)
    case restored
}
