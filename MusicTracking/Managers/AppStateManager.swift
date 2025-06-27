import Foundation
import MusicKit
import Observation
import BackgroundTasks

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
        
        do {
            await waitForPersistenceControllerLoad()
            
            try await authorizationService.refreshAuthorizationIfNeeded()
            await tokenManager.checkTokenValidity()
            
            if authorizationService.isAuthorized {
                musicKitService.startListeningTracking()
                setupListeningSessionObservers()
                
                try await enableBackgroundMonitoring()
            }
            
            backgroundTaskManager.registerBackgroundTasks()
            await performHealthCheck()
            await startPeriodicHealthChecks()
            
            isInitialized = true
            
            NotificationCenter.default.post(name: .appInitializationCompleted, object: nil)
            
        } catch {
            let appError = error as? AppError ?? AppError.from(musicKitError: error)
            initializationError = appError
            isHealthy = false
            
            NotificationCenter.default.post(name: .appInitializationFailed, object: appError)
            print("App initialization failed: \(appError)")
        }
    }
    
    private func waitForPersistenceControllerLoad() async {
        while !persistenceController.isLoaded {
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        if let loadError = persistenceController.loadError {
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
                guard let session = notification.object as? ListeningSession else { return }
                
                Task {
                    await self?.saveListeningSession(session)
                }
            }
        )
    }
    
    private func saveListeningSession(_ session: ListeningSession) async {
        do {
            try await repository.saveListeningSession(session)
            
            let weekStart = Calendar.current.startOfWeek(for: session.startTime)
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
        do {
            try await authorizationService.requestAuthorization()
            await tokenManager.handleAuthorizationChange(isAuthorized: true)
            
            if authorizationService.isAuthorized {
                musicKitService.startListeningTracking()
                setupListeningSessionObservers()
            }
            
            await performHealthCheck()
            
        } catch {
            await tokenManager.handleAuthorizationChange(isAuthorized: false)
            musicKitService.stopListeningTracking()
            
            throw error
        }
    }
    
    @MainActor
    public func refreshServices() async throws {
        do {
            try await tokenManager.refreshTokenIfNeeded()
            try await authorizationService.refreshAuthorizationIfNeeded()
            
            if authorizationService.isAuthorized && !musicKitService.isTracking {
                musicKitService.startListeningTracking()
                setupListeningSessionObservers()
            } else if !authorizationService.isAuthorized && musicKitService.isTracking {
                musicKitService.stopListeningTracking()
            }
            
            await performHealthCheck()
            
        } catch {
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
                    await self.handleAppDidBecomeActive()
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    await self.handleAppWillEnterBackground()
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
                try? await Task.sleep(for: .minutes(15))
                
                await MainActor.run {
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
    
    public func getRecentListeningSessions(limit: Int = 50) async throws -> [ListeningSession] {
        return try await repository.fetchRecentListeningSessions(limit: limit)
    }
    
    public func getWeeklyStats(for weekStartDate: Date) async throws -> WeeklyStats? {
        return try await repository.fetchWeeklyStats(for: weekStartDate)
    }
    
    public func getAllWeeklyStats() async throws -> [WeeklyStats] {
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
    public let persistenceStatus: CloudKitSyncStatus
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

