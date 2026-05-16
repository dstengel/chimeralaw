// NetworkMonitor.swift
// Chimera Law
// NWPathMonitor singleton for offline detection (Common Sense requirement)

import Foundation
import Combine
import Network
import os

@MainActor
final class NetworkMonitor: ObservableObject {

    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.daimos.chimera.networkmonitor")
    private let logger = Logger(subsystem: "com.daimos.chimera", category: "Network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = connected
            }
            if !connected {
                self?.logger.info("Network connection lost")
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
