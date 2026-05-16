// ChimeraApp.swift
// Chimera Law
// App entry point and central state container

import SwiftUI
import Combine
import os

@main
struct ChimeraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.resolvedColorScheme)
                .task { await appState.loadInitialData() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if let actionType = QuickActionService.shared.consumePendingAction() {
                    if actionType == "com.daimos.chimera.useCamera" {
                        appState.pendingCameraQuickAction = true
                    } else if actionType == "com.daimos.chimera.usePhoto" {
                        appState.pendingPhotoQuickAction = true
                    } else if actionType == "com.daimos.chimera.importTrackChanges" {
                        appState.pendingTrackChangesQuickAction = true
                    }
                }
            }
            // Memory auto-save flush: cancel the 2s debounce and write
            // the most recent queued snapshot synchronously. .background
            // only — .inactive fires on every transient interruption
            // (sheet present, Control Center peek, banner notification),
            // and a flush on each of those would write to disk on every
            // fleeting state change. .background fires exactly once per
            // real backgrounding event (lock, app switcher, kill).
            // No-op when auto-save is disabled.
            if phase == .background {
                MemoryStore.shared.flushPendingSync()
            }
        }
    }
}

// MARK: - Quick Action (Home Screen Shortcut) Handling

final class QuickActionService {
    static let shared = QuickActionService()
    private var pendingActionType: String?

    func handle(_ shortcutItem: UIApplicationShortcutItem) {
        pendingActionType = shortcutItem.type
    }

    /// Returns and clears the pending action type. Call once per activation cycle.
    func consumePendingAction() -> String? {
        defer { pendingActionType = nil }
        return pendingActionType
    }
}

// MARK: - AppDelegate (minimal — no scene configuration override)

class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: Scene Configuration

    /// Provide the default configuration so UIKit creates a UIWindowScene that
    /// SwiftUI manages.  The scene delegate captures the quick-action shortcut
    /// that was used to cold-launch the app (replaces the deprecated
    /// LaunchOptionsKey.shortcutItem path).
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Capture quick-action from ConnectionOptions on cold launch.
        if let shortcutItem = options.shortcutItem {
            QuickActionService.shared.handle(shortcutItem)
        }
        let config = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        return config
    }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    private let logger = Logger(subsystem: "com.daimos.chimera", category: "AppState")
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published

    @Published var userProfile: UserProfile?
    @Published var isOnboardingComplete: Bool = false
    @Published var isLoading: Bool = true
    @Published var appConfig: AppConfig?
    @Published var errorMessage: String?
    @Published var pendingCameraQuickAction: Bool = false
    @Published var pendingPhotoQuickAction: Bool = false
    @Published var pendingTrackChangesQuickAction: Bool = false

    /// Non-nil when a backend service (iCloud, Anthropic) failed during sync.
    /// Displayed by ConnectivityBanner on the drafting screen.
    @Published var serviceWarning: String?

    // MARK: - Services
    // Computed properties so singletons are NOT eagerly initialised
    // during AppState init (which blocks the first SwiftUI render).
    // Each singleton is created on first actual use — typically inside
    // loadInitialData(), by which time the TitleScreenView is already visible.

    var cloudKit: CloudKitService { CloudKitService.shared }
    var draftingService: DraftingService { DraftingService.shared }
    var storeKit: StoreKitService { StoreKitService.shared }
    var networkMonitor: NetworkMonitor { NetworkMonitor.shared }

    // MARK: - Appearance

    @AppStorage("dk_appearanceMode") var appearanceMode: Int = 0

    var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    // MARK: - Startup

    func loadInitialData() async {
        isLoading = true

        // Step 1: Load cached profile (instant, no network).
        if let cached = UserDefaults.standard.data(forKey: "dk_cachedUserProfile"),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: cached) {
            self.userProfile = profile
            self.isOnboardingComplete = profile.dataConsentGiven
        }

        // Brief branded splash, then show real UI immediately.
        try? await Task.sleep(for: .seconds(1.5))
        isLoading = false

        // Step 2+: Network sync runs in the background while the UI
        // is already interactive. Results update reactively via @Published.
        await syncRemoteData()

        // Step 3: When connectivity is restored after a failure, retry sync
        // automatically so the serviceWarning banner disappears.
        networkMonitor.$isConnected
            .removeDuplicates()
            .dropFirst()                         // skip the initial value
            .filter { $0 == true }               // only on reconnect
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.syncRemoteData() }
            }
            .store(in: &cancellables)
    }

    /// Fetches AppConfig, user profile, and StoreKit data from the network.
    /// Runs after the UI is already visible so the user is never blocked.
    /// Sets `serviceWarning` if any backend is unreachable.
    private func syncRemoteData() async {
        // Clear previous warning before retrying.
        serviceWarning = nil

        var iCloudFailed = false

        // Fetch AppConfig from CloudKit
        do {
            let config = try await cloudKit.fetchAppConfig()
            self.appConfig = config
            draftingService.configure(with: config)
        } catch {
            logger.error("Failed to load AppConfig: \(error.localizedDescription)")
            iCloudFailed = true
        }

        // Fetch or create user profile from CloudKit
        do {
            if let cloudProfile = try await cloudKit.fetchOrCreateUserProfile() {
                self.userProfile = cloudProfile
                self.isOnboardingComplete = cloudProfile.dataConsentGiven
                cacheProfile(cloudProfile)
            }
        } catch {
            logger.error("Failed to load user profile: \(error.localizedDescription)")
            iCloudFailed = true
        }

        // Load StoreKit product and entitlements
        await storeKit.loadProduct()
        await storeKit.checkCurrentEntitlements()

        // Surface iCloud warning if sync failed
        if iCloudFailed {
            if !networkMonitor.isConnected {
                // The offline banner already covers this; no extra warning needed.
                serviceWarning = nil
            } else {
                serviceWarning = "iCloud sync failed. Usage tracking and settings may be out of date."
            }
        }

        // Check that the AI service is configured
        if !draftingService.isConfigured && networkMonitor.isConnected {
            serviceWarning = "AI service not configured. Check your connection or add an API key in Settings."
        }
    }

    // MARK: - Onboarding

    func completeOnboarding() async {
        // Record that the user has accepted the current legal version.
        UserDefaults.standard.set(LegalVersion.current, forKey: LegalVersion.acceptedKey)

        var profile = UserProfile(
            dataConsentGiven: true
        )

        do {
            try await cloudKit.saveUserProfile(profile)
            if let saved = try await cloudKit.fetchOrCreateUserProfile() {
                profile = saved
            }
        } catch {
            logger.error("Failed to save profile: \(error.localizedDescription)")
        }

        self.userProfile = profile
        self.isOnboardingComplete = true
        cacheProfile(profile)
    }

    // MARK: - Profile Update

    func updateProfile(_ profile: UserProfile) async {
        self.userProfile = profile
        cacheProfile(profile)

        do {
            try await cloudKit.saveUserProfile(profile)
        } catch {
            logger.error("Failed to update profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func cacheProfile(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "dk_cachedUserProfile")
        }
    }
}
