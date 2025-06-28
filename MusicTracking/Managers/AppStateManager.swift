import Foundation
import MusicKit
import Observation
import BackgroundTasks
import UIKit

@Observable
public final class AppStateManager {
    
    public static let shared = AppStateManager()
    
    public let authorizationService = AuthorizationService()
    public let musicKitService = MusicKitService.shared
    public let tokenManager = TokenManager()
    public let persistenceController = PersistenceController.shared
    public let cloudKitSyncService: CloudKitSyncService
    public let repository: CoreDataRepository
    public let backgroundMusicMonitor: BackgroundMusicMonitor
    public let backgroundTaskManager: BackgroundTaskManager
    public let statisticsService: StatisticsService
    
    public private(set) var isInitialized: Bool = false
    public private(set) var isHealthy: Bool = false
    public private(set) var lastHealthCheck: Date?
    public private(set) var initializationError: AppError?
    
    private var notificationObservers: [NSObjectProtocol] = []
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier?
    private var healthCheckTask: Task<Void, Never>?
    
    private init() {
        self.cloudKitSyncService = CloudKitSyncService(persistenceController: persistenceController)
        self.repository = CoreDataRepository(persistenceController: persistenceController)
        self.backgroundMusicMonitor = BackgroundMusicMonitor.shared
        self.backgroundTaskManager = BackgroundTaskManager.shared
        self.statisticsService = StatisticsService.shared
        
        configureBackgroundMonitoring()
        setupNotificationObservers()
        
        Task {
            await initialize()
        }
    }
    
    deinit {
        cleanupNotificationObservers()
        healthCheckTask?.cancel()
    }
    
    @MainActor
    public func initialize() async {
        guard !isInitialized else { return }
        
        initializationError = nil
        print("Starting app initialization...")
        
        do {
            // Step 1: Wait for Core Data to be ready
            try await waitForPersistenceControllerLoad()
            print("✓ Core Data loaded")
            
            // Step 2: Initialize authorization service with proper timing
            await authorizationService.startInitialization()
            await authorizationService.waitForInitialCheck()
            print("✓ Authorization service initialized")
            
            // Step 3: Check token validity
            await tokenManager.checkTokenValidity()
            print("✓ Token manager checked")
            
            // Step 4: Handle authorization-dependent services
            if authorizationService.isAuthorized {
                print("✓ MusicKit authorized - starting tracking services")
                musicKitService.startListeningTracking()
                setupListeningSessionObservers()
                
                // Try to enable background monitoring with better error handling
                do {
                    try await enableBackgroundMonitoring()
                    print("✓ Background monitoring enabled")
                } catch {
                    print("⚠️ Background monitoring failed but continuing: \(error)")
                    // Don't fail initialization if background monitoring fails
                }
            } else if !authorizationService.isFirstTimeUser() {
                // Only show warning for returning users who have lost authorization
                print("⚠️ MusicKit authorization lost - tracking services disabled")
            } else {
                // First-time users - silent initialization
                print("ℹ️ First-time user - tracking services will start after authorization")
            }
            
            // Step 5: Register background tasks and start health monitoring
            backgroundTaskManager.registerBackgroundTasks()
            await performHealthCheck()
            await startPeriodicHealthChecks()
            
            isInitialized = true
            print("✓ App initialization completed successfully")
            
            NotificationCenter.default.post(name: .appInitializationCompleted, object: nil)
            
        } catch {
            let appError = error as? AppError ?? AppError.from(musicKitError: error)
            initializationError = appError
            isHealthy = false
            
            print("❌ App initialization failed: \(appError)")
            NotificationCenter.default.post(name: .appInitializationFailed, object: appError)
        }
    }
    
    private func waitForPersistenceControllerLoad() async throws {
        while !persistenceController.isLoaded {
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        if persistenceController.loadError != nil {
            throw AppError.coreDataModelNotFound
        }
    }
    
    private func setupListeningSessionObservers() {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .listeningSessionCompleted,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let session = notification.object as? DomainListeningSession else { return }
                
                Task {
                    await self?.saveListeningSession(session)
                }
            }
        )
    }
    
    private func saveListeningSession(_ session: DomainListeningSession) async {
        do {
            try await repository.saveListeningSession(session)
            
            let _ = Calendar.current.startOfWeek(for: session.startTime)
            if Calendar.current.isInCurrentWeek(session.startTime) {
                await updateWeeklyStatsForCurrentWeek()
            }
        } catch {
            print("Failed to save listening session: \(error)")
        }
    }
    
    private func updateWeeklyStatsForCurrentWeek() async {
        do {
            let currentWeekStart = Calendar.current.startOfWeek(for: Date())
            try await repository.generateWeeklyStatsForWeek(currentWeekStart)
        } catch {
            print("Failed to update weekly stats: \(error)")
        }
    }
    
    @MainActor
    public func performHealthCheck() async {
        lastHealthCheck = Date()
        
        let authInfo = authorizationService.getDetailedAuthorizationInfo()
        let tokenStatus = tokenManager.getTokenStatus()
        let persistenceStatus = persistenceController.getSyncStatus()
        let syncInfo = cloudKitSyncService.getSyncInfo()
        
        let backgroundMonitoringState = musicKitService.getBackgroundMonitoringState()
        let backgroundMonitoringHealthy = backgroundMonitoringState != .error
        
        isHealthy = authInfo.isHealthy && 
                   tokenStatus.isHealthy && 
                   persistenceStatus.isHealthy &&
                   syncInfo.isHealthy &&
                   backgroundMonitoringHealthy &&
                   (!musicKitService.isTracking || authInfo.isAuthorized)
        
        if !isHealthy {
            NotificationCenter.default.post(name: .appHealthStatusChanged, object: false)
        }
    }
    
    @MainActor
    public func requestMusicAuthorization() async throws {
        print("Requesting MusicKit authorization...")
        
        do {
            try await authorizationService.requestAuthorization()
            
            // Wait for authorization to settle
            try await Task.sleep(for: .milliseconds(300))
            
            await authorizationService.checkCurrentStatus()
            await tokenManager.handleAuthorizationChange(isAuthorized: authorizationService.isAuthorized)
            
            if authorizationService.isAuthorized {
                print("✓ Authorization successful - starting services")
                musicKitService.startListeningTracking()
                setupListeningSessionObservers()
                
                // Try to enable background monitoring
                do {
                    try await enableBackgroundMonitoring()
                } catch {
                    print("⚠️ Background monitoring failed after authorization: \(error)")
                    // Don't fail the authorization flow if background monitoring fails
                }
            }
            
            await performHealthCheck()
            
        } catch {
            print("❌ Authorization failed: \(error)")
            await tokenManager.handleAuthorizationChange(isAuthorized: false)
            musicKitService.stopListeningTracking()
            
            throw error
        }
    }
    
    @MainActor
    public func refreshServices() async throws {
        print("Refreshing services...")
        
        do {
            try await tokenManager.refreshTokenIfNeeded()
            
            // Refresh authorization with production-friendly timing
            try await authorizationService.refreshAuthorizationIfNeeded()
            
            // Wait for status to stabilize
            try await Task.sleep(for: .milliseconds(200))
            
            if authorizationService.isAuthorized && !musicKitService.isTracking {
                print("✓ Authorization restored - starting tracking")
                musicKitService.startListeningTracking()
                setupListeningSessionObservers()
            } else if !authorizationService.isAuthorized && musicKitService.isTracking {
                print("⚠️ Authorization lost - stopping tracking")
                musicKitService.stopListeningTracking()
            }
            
            await performHealthCheck()
            
        } catch {
            print("❌ Service refresh failed: \(error)")
            await performHealthCheck()
            throw error
        }
    }
    
    @MainActor
    public func triggerManualSync() async throws {
        try await cloudKitSyncService.triggerManualSync()
        await performHealthCheck()
    }
    
    public func getAppStatus() -> AppStatus {
        return AppStatus(
            isInitialized: isInitialized,
            isHealthy: isHealthy,
            isTracking: musicKitService.isTracking,
            authorizationInfo: authorizationService.getDetailedAuthorizationInfo(),
            tokenStatus: tokenManager.getTokenStatus(),
            lastHealthCheck: lastHealthCheck,
            initializationError: initializationError,
            persistenceStatus: persistenceController.getSyncStatus(),
            syncInfo: cloudKitSyncService.getSyncInfo()
        )
    }
    
    @MainActor
    public func handleAppWillEnterBackground() {
        beginBackgroundTask()
        
        Task {
            do {
                try await tokenManager.refreshTokenIfNeeded()
                try await cloudKitSyncService.triggerManualSync()
                await performHealthCheck()
            } catch {
                print("Background refresh failed: \(error)")
            }
            
            endBackgroundTask()
        }
    }
    
    @MainActor
    public func handleAppDidBecomeActive() {
        Task {
            try? await refreshServices()
            try? await cloudKitSyncService.triggerManualSync()
        }
    }
    
    private func setupNotificationObservers() {
        let center = NotificationCenter.default
        
        notificationObservers.append(
            center.addObserver(forName: .musicKitAuthorizationChanged, object: nil, queue: .main) { [weak self] notification in
                guard let self = self else { return }
                
                Task { @MainActor in
                    let isAuthorized = notification.object as? Bool ?? false
                    await self.tokenManager.handleAuthorizationChange(isAuthorized: isAuthorized)
                    
                    if isAuthorized && !self.musicKitService.isTracking {
                        self.musicKitService.startListeningTracking()
                        self.setupListeningSessionObservers()
                    } else if !isAuthorized {
                        self.musicKitService.stopListeningTracking()
                    }
                    
                    await self.performHealthCheck()
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(forName: .tokenRefreshSucceeded, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    await self.performHealthCheck()
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(forName: .tokenRefreshFailed, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    await self.performHealthCheck()
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(forName: .cloudKitSyncCompleted, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    await self.performHealthCheck()
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    self.handleAppDidBecomeActive()
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    self.handleAppWillEnterBackground()
                }
            }
        )
    }
    
    private func cleanupNotificationObservers() {
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
    
    private func configureBackgroundMonitoring() {
        musicKitService.setBackgroundMonitor(backgroundMusicMonitor)
        print("Background monitoring configured in AppStateManager")
    }
    
    @MainActor
    private func enableBackgroundMonitoring() async throws {
        do {
            try await musicKitService.enableBackgroundMonitoring()
            print("Background monitoring enabled successfully")
        } catch {
            print("Failed to enable background monitoring: \(error)")
            
            // Perform comprehensive diagnostics to help with troubleshooting
            let diagnostics = musicKitService.performComprehensiveBackgroundDiagnostics()
            print("=== Background Monitoring Failure Diagnostics ===")
            print(diagnostics.summary)
            print("User-friendly diagnosis: \(diagnostics.userFriendlyDiagnosis)")
            print("Troubleshooting steps:")
            for (index, step) in diagnostics.troubleshootingSteps.enumerated() {
                print("\(index + 1). \(step)")
            }
            print("=== End Diagnostics ===")
            
            throw error
        }
    }
    
    @MainActor
    public func toggleBackgroundMonitoring() async throws {
        if musicKitService.isBackgroundMonitoringActive() {
            await musicKitService.disableBackgroundMonitoring()
        } else {
            try await musicKitService.enableBackgroundMonitoring()
        }
        
        await performHealthCheck()
    }
    
    // MARK: - Background Monitoring Diagnostics
    
    @MainActor
    public func getBackgroundMonitoringDiagnostics() -> BackgroundMonitoringDiagnostics {
        return musicKitService.performComprehensiveBackgroundDiagnostics()
    }
    
    @MainActor
    public func getBackgroundMonitoringError() -> AppError? {
        return musicKitService.getBackgroundMonitoringError()
    }
    
    public func getBackgroundMonitoringStatus() -> (isActive: Bool, state: BackgroundMonitoringState, metrics: MonitoringMetrics?) {
        return (
            isActive: musicKitService.isBackgroundMonitoringActive(),
            state: musicKitService.getBackgroundMonitoringState(),
            metrics: musicKitService.getMonitoringMetrics()
        )
    }
    
    
    private func beginBackgroundTask() {
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if let identifier = backgroundTaskIdentifier {
            UIApplication.shared.endBackgroundTask(identifier)
            backgroundTaskIdentifier = nil
        }
    }
    
    private func startPeriodicHealthChecks() async {
        healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                
                let _ = await MainActor.run {
                    Task {
                        await performHealthCheck()
                    }
                }
            }
        }
    }
    
    public func getStorageInfo() async throws -> StorageInfo {
        return try await repository.getStorageInfo()
    }
    
    public func getRecentListeningSessions(limit: Int = 50) async throws -> [DomainListeningSession] {
        return try await repository.fetchRecentListeningSessions(limit: limit)
    }
    
    public func getWeeklyStats(for weekStartDate: Date) async throws -> DomainWeeklyStats? {
        return try await repository.fetchWeeklyStats(for: weekStartDate)
    }
    
    public func getAllWeeklyStats() async throws -> [DomainWeeklyStats] {
        return try await repository.fetchAllWeeklyStats()
    }
    
    public func getTopSongs(limit: Int = 10, timeframe: DateInterval? = nil) async throws -> [(Song, Int)] {
        let interval = timeframe ?? DateInterval(start: Calendar.current.startOfWeek(for: Date()), end: Date())
        return try await repository.getTopSongs(from: interval.start, to: interval.end, limit: limit)
    }
    
    public func getTopArtists(limit: Int = 10, timeframe: DateInterval? = nil) async throws -> [(String, Int)] {
        let interval = timeframe ?? DateInterval(start: Calendar.current.startOfWeek(for: Date()), end: Date())
        return try await repository.getTopArtists(from: interval.start, to: interval.end, limit: limit)
    }
}

public struct AppStatus {
    public let isInitialized: Bool
    public let isHealthy: Bool
    public let isTracking: Bool
    public let authorizationInfo: AuthorizationInfo
    public let tokenStatus: TokenStatus
    public let lastHealthCheck: Date?
    public let initializationError: AppError?
    public let persistenceStatus: PersistenceStatus
    public let syncInfo: SyncInfo
    
    public var needsUserAttention: Bool {
        return !isHealthy || 
               authorizationInfo.needsUserAction || 
               initializationError?.requiresUserAction == true ||
               !persistenceStatus.isHealthy ||
               syncInfo.requiresAttention
    }
    
    public var statusDescription: String {
        if !isInitialized {
            return "Initializing..."
        } else if !persistenceStatus.isHealthy {
            return "Database issue"
        } else if syncInfo.requiresAttention {
            return "Sync issue"
        } else if !isHealthy {
            return "Needs attention"
        } else if isTracking {
            return "Tracking active"
        } else {
            return "Ready"
        }
    }
    
    public var detailedStatus: String {
        var components: [String] = []
        
        if !isInitialized {
            components.append("Not initialized")
        }
        
        if !authorizationInfo.isAuthorized {
            components.append("Not authorized")
        }
        
        if !persistenceStatus.isHealthy {
            components.append("Database: \(persistenceStatus.statusDescription)")
        }
        
        if syncInfo.requiresAttention {
            components.append("Sync: \(syncInfo.status.displayName)")
        }
        
        if components.isEmpty {
            return isTracking ? "All systems operational, tracking active" : "All systems ready"
        } else {
            return components.joined(separator: ", ")
        }
    }
}

