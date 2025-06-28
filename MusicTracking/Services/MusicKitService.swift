import Foundation
import MusicKit
import Observation
import UIKit

@Observable
public final class MusicKitService {
    
    public static let shared = MusicKitService()
    
    public private(set) var isAuthorized: Bool = false
    public private(set) var currentSong: Song?
    public private(set) var playbackState: ApplicationMusicPlayer.PlaybackStatus = .stopped
    public private(set) var isTracking: Bool = false
    public private(set) var supportsBackgroundMonitoring: Bool = false
    public private(set) var backgroundMonitoringEnabled: Bool = false
    
    private let player = ApplicationMusicPlayer.shared
    private var playbackObservationTask: Task<Void, Never>?
    private var currentListeningSession: DomainListeningSession?
    private var backgroundMonitor: BackgroundMusicMonitor?
    
    public init() {
        checkBackgroundMonitoringSupport()
        Task {
            await checkAuthorizationStatus()
            await startPlaybackObservation()
        }
    }
    
    deinit {
        playbackObservationTask?.cancel()
    }
    
    @MainActor
    public func requestAuthorization() async throws {
        let status = await MusicAuthorization.request()
        
        switch status {
        case .authorized:
            isAuthorized = true
        case .denied:
            isAuthorized = false
            throw AppError.musicKitPermissionDenied
        case .notDetermined:
            isAuthorized = false
            throw AppError.musicKitNotAuthorized
        case .restricted:
            isAuthorized = false
            throw AppError.musicKitNotAvailable
        @unknown default:
            isAuthorized = false
            throw AppError.musicKitUnknownError(NSError(domain: "MusicKitService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown authorization status"]))
        }
    }
    
    @MainActor
    private func checkAuthorizationStatus() async {
        let status = MusicAuthorization.currentStatus
        isAuthorized = status == .authorized
    }
    
    public func getCurrentPlayingSong() async throws -> Song? {
        guard isAuthorized else {
            throw AppError.musicKitNotAuthorized
        }
        
        guard let currentEntry = player.queue.currentEntry else {
            return nil
        }
        
        // Extract song information from the queue entry
        guard let item = currentEntry.item else {
            return nil
        }
        
        // Handle different types of MusicKit items
        switch item {
        case let song as MusicKit.Song:
            return Song(
                id: song.id,
                title: song.title,
                artistName: song.artistName
            )
        default:
            // For other item types, try to extract song information if available
            return nil
        }
    }
    
    public func getRecentlyPlayedSongs(limit: Int = 25) async throws -> [Song] {
        guard isAuthorized else {
            throw AppError.musicKitNotAuthorized
        }
        
        do {
            let request = MusicRecentlyPlayedRequest<MusicKit.Song>()
            let response = try await request.response()
            
            return response.items.compactMap { song in
                Song(
                    id: song.id,
                    title: song.title,
                    artistName: song.artistName
                )
            }.prefix(limit).map { $0 }
        } catch {
            throw AppError.from(musicKitError: error)
        }
    }
    
    public func searchSongs(query: String, limit: Int = 25) async throws -> [Song] {
        guard isAuthorized else {
            throw AppError.musicKitNotAuthorized
        }
        
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        do {
            var request = MusicCatalogSearchRequest(term: query, types: [MusicKit.Song.self])
            request.limit = limit
            
            let response = try await request.response()
            return response.songs.compactMap { song in
                Song(
                    id: song.id,
                    title: song.title,
                    artistName: song.artistName
                )
            }
        } catch {
            throw AppError.from(musicKitError: error)
        }
    }
    
    public func getSongDetails(for songID: MusicItemID) async throws -> Song? {
        guard isAuthorized else {
            throw AppError.musicKitNotAuthorized
        }
        
        do {
            let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: songID)
            let response = try await request.response()
            
            return response.items.first.map { song in
                Song(
                    id: song.id,
                    title: song.title,
                    artistName: song.artistName
                )
            }
        } catch {
            throw AppError.from(musicKitError: error)
        }
    }
    
    public func getUserLibrarySongs(limit: Int = 100) async throws -> [Song] {
        guard isAuthorized else {
            throw AppError.musicKitNotAuthorized
        }
        
        do {
            var request = MusicLibraryRequest<MusicKit.Song>()
            request.limit = limit
            
            let response = try await request.response()
            return response.items.compactMap { song in
                Song(
                    id: song.id,
                    title: song.title,
                    artistName: song.artistName
                )
            }
        } catch {
            throw AppError.from(musicKitError: error)
        }
    }
    
    @MainActor
    public func startListeningTracking() {
        guard isAuthorized else { return }
        isTracking = true
    }
    
    @MainActor
    public func stopListeningTracking() {
        isTracking = false
        finishCurrentSession()
    }
    
    private func startPlaybackObservation() async {
        playbackObservationTask = Task {
            // Observe playback status changes
            var lastStatus = player.state.playbackStatus
            while !Task.isCancelled {
                let currentStatus = player.state.playbackStatus
                if currentStatus != lastStatus {
                    await MainActor.run {
                        self.playbackState = currentStatus
                        self.handlePlaybackStateChange(currentStatus)
                    }
                    lastStatus = currentStatus
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    
    @MainActor
    private func handlePlaybackStateChange(_ status: ApplicationMusicPlayer.PlaybackStatus) {
        guard isTracking else { return }
        
        switch status {
        case .playing:
            Task {
                await startNewListeningSession()
            }
        case .paused, .stopped:
            finishCurrentSession()
        default:
            break
        }
    }
    
    private func startNewListeningSession() async {
        do {
            guard let song = try await getCurrentPlayingSong() else { return }
            
            await MainActor.run {
                finishCurrentSession()
                
                let session = DomainListeningSession(
                    song: song,
                    startTime: Date(),
                    duration: song.duration ?? 0
                )
                
                currentSong = song
                currentListeningSession = session
                
                NotificationCenter.default.post(
                    name: .listeningSessionStarted,
                    object: session
                )
            }
        } catch {
            print("Failed to start listening session: \(error)")
        }
    }
    
    @MainActor
    private func finishCurrentSession() {
        guard let session = currentListeningSession else { return }
        
        let endTime = Date()
        let actualDuration = endTime.timeIntervalSince(session.startTime)
        let wasSkipped = actualDuration < (session.duration * 0.8)
        
        let completedSession = DomainListeningSession(
            id: session.id,
            song: session.song,
            startTime: session.startTime,
            endTime: endTime,
            duration: actualDuration,
            playCount: session.playCount,
            wasSkipped: wasSkipped,
            skipTime: wasSkipped ? actualDuration : nil
        )
        
        currentListeningSession = nil
        
        NotificationCenter.default.post(
            name: .listeningSessionCompleted,
            object: completedSession
        )
    }
    
    public func refreshAuthorization() async throws {
        guard isAuthorized else {
            throw AppError.musicKitNotAuthorized
        }
        
        do {
            try await requestAuthorization()
        } catch {
            throw AppError.musicKitTokenRefreshFailed
        }
    }
    
    public func setBackgroundMonitor(_ monitor: BackgroundMusicMonitor) {
        backgroundMonitor = monitor
        print("Background monitor set for MusicKitService")
    }
    
    @MainActor
    public func enableBackgroundMonitoring() async throws {
        guard supportsBackgroundMonitoring else {
            throw AppError.backgroundTaskFailed("Background monitoring not supported on this device")
        }
        
        guard isAuthorized else {
            throw AppError.musicKitNotAuthorized
        }
        
        guard let monitor = backgroundMonitor else {
            throw AppError.backgroundTaskFailed("Background monitor not configured")
        }
        
        try await monitor.startMonitoring()
        backgroundMonitoringEnabled = true
        
        NotificationCenter.default.post(
            name: .backgroundMonitoringStarted,
            object: nil,
            userInfo: [
                NotificationKeys.BackgroundMonitoring.isActive: true,
                NotificationKeys.BackgroundMonitoring.timestamp: Date()
            ]
        )
        
        print("Background monitoring enabled")
    }
    
    @MainActor
    public func disableBackgroundMonitoring() async {
        guard backgroundMonitoringEnabled else { return }
        
        if let monitor = backgroundMonitor {
            await monitor.stopMonitoring()
        }
        
        backgroundMonitoringEnabled = false
        
        NotificationCenter.default.post(
            name: .backgroundMonitoringStopped,
            object: nil,
            userInfo: [
                NotificationKeys.BackgroundMonitoring.isActive: false,
                NotificationKeys.BackgroundMonitoring.timestamp: Date()
            ]
        )
        
        print("Background monitoring disabled")
    }
    
    public func isBackgroundMonitoringActive() -> Bool {
        return backgroundMonitoringEnabled && (backgroundMonitor?.state.isActive ?? false)
    }
    
    public func getBackgroundMonitoringState() -> BackgroundMonitoringState {
        return backgroundMonitor?.state ?? .inactive
    }
    
    public func getMonitoringMetrics() -> MonitoringMetrics? {
        return backgroundMonitor?.getMonitoringMetrics()
    }
    
    private func checkBackgroundMonitoringSupport() {
        let status = UIApplication.shared.backgroundRefreshStatus
        
        print("=== Enhanced Background Monitoring Debug ===")
        print("Background refresh status raw value: \(status.rawValue)")
        
        var diagnosisMessages: [String] = []
        var possibleSolutions: [String] = []
        
        switch status {
        case .restricted:
            print("❌ Background refresh is RESTRICTED")
            diagnosisMessages.append("Background App Refresh is restricted by system policies")
            
            // Detailed restriction analysis
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                diagnosisMessages.append("• Low Power Mode is enabled - this can restrict background tasks")
                possibleSolutions.append("Disable Low Power Mode in Settings > Battery")
            }
            
            // Check for parental controls indicators
            diagnosisMessages.append("• Possible causes: Parental Controls, Screen Time restrictions, or Corporate/MDM policies")
            possibleSolutions.append("Check Settings > Screen Time > Content & Privacy Restrictions")
            possibleSolutions.append("Check with IT administrator if device is managed by organization")
            
        case .denied:
            print("❌ Background refresh is DENIED by user")
            diagnosisMessages.append("User has disabled Background App Refresh")
            possibleSolutions.append("Enable in Settings > General > Background App Refresh")
            possibleSolutions.append("Enable for this app specifically in Settings > MusicTracking > Background App Refresh")
            
        case .available:
            print("✅ Background refresh is AVAILABLE")
            diagnosisMessages.append("Background App Refresh is enabled and available")
            
        @unknown default:
            print("⚠️ Unknown background refresh status: \(status)")
            diagnosisMessages.append("Unknown background refresh status - this may be a new iOS version")
        }
        
        // Enhanced system diagnostics
        print("\n--- System Diagnostics ---")
        print("Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)")
        print("Device model: \(UIDevice.current.model)")
        print("iOS Version: \(UIDevice.current.systemVersion)")
        print("App State: \(applicationStateDescription())")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        
        // Memory and performance checks
        let memoryInfo = getMemoryInfo()
        print("Available Memory: \(memoryInfo.available) MB")
        print("Used Memory: \(memoryInfo.used) MB")
        
        // Background modes verification
        print("\n--- Background Capabilities ---")
        if let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] {
            print("Configured background modes: \(backgroundModes)")
        } else {
            print("⚠️ No background modes configured in Info.plist")
            diagnosisMessages.append("Background modes may not be properly configured")
        }
        
        // Background task identifiers check
        if let taskIdentifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] {
            print("Background task identifiers: \(taskIdentifiers)")
        }
        
        // Simulator detection with enhanced warnings
        #if targetEnvironment(simulator)
        print("⚠️ Running in iOS Simulator")
        diagnosisMessages.append("iOS Simulator has limited background task capabilities")
        possibleSolutions.append("Test on physical device for full background functionality")
        #else
        print("✅ Running on physical device")
        #endif
        
        // Settings verification guidance
        print("\n--- Settings Verification Guide ---")
        print("1. Settings > General > Background App Refresh (should be ON)")
        print("2. Settings > MusicTracking > Background App Refresh (should be ON)")
        print("3. Settings > Screen Time > Content & Privacy Restrictions (check if restricted)")
        print("4. Settings > Battery > Low Power Mode (should be OFF for full functionality)")
        
        print("\n--- Diagnosis Summary ---")
        for message in diagnosisMessages {
            print("• \(message)")
        }
        
        if !possibleSolutions.isEmpty {
            print("\n--- Possible Solutions ---")
            for solution in possibleSolutions {
                print("• \(solution)")
            }
        }
        
        supportsBackgroundMonitoring = status == .available
        print("\nFinal supportsBackgroundMonitoring: \(supportsBackgroundMonitoring)")
        print("=== End Enhanced Debug ===\n")
    }
    
    private func applicationStateDescription() -> String {
        switch UIApplication.shared.applicationState {
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        case .background:
            return "Background"
        @unknown default:
            return "Unknown (\(UIApplication.shared.applicationState.rawValue))"
        }
    }
    
    private func getMemoryInfo() -> (available: Int, used: Int) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Int(info.resident_size) / 1024 / 1024
            let totalMB = Int(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024
            return (available: totalMB - usedMB, used: usedMB)
        }
        
        return (available: 0, used: 0)
    }
    
    // MARK: - Comprehensive Background Monitoring Diagnostics
    
    public func performComprehensiveBackgroundDiagnostics() -> BackgroundMonitoringDiagnostics {
        let status = UIApplication.shared.backgroundRefreshStatus
        var diagnostics = BackgroundMonitoringDiagnostics()
        
        // Basic status check
        diagnostics.backgroundRefreshStatus = status
        diagnostics.supportsBackgroundMonitoring = status == .available
        
        // System environment checks
        diagnostics.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        diagnostics.isSimulator = {
            #if targetEnvironment(simulator)
            return true
            #else
            return false
            #endif
        }()
        
        diagnostics.deviceModel = UIDevice.current.model
        diagnostics.iOSVersion = UIDevice.current.systemVersion
        diagnostics.applicationState = UIApplication.shared.applicationState
        
        // Memory diagnostics
        let memoryInfo = getMemoryInfo()
        diagnostics.availableMemoryMB = memoryInfo.available
        diagnostics.usedMemoryMB = memoryInfo.used
        
        // Configuration checks
        diagnostics.backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        diagnostics.backgroundTaskIdentifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        
        // Generate user-friendly diagnosis
        diagnostics.userFriendlyDiagnosis = generateUserFriendlyDiagnosis(for: diagnostics)
        diagnostics.troubleshootingSteps = generateTroubleshootingSteps(for: diagnostics)
        
        return diagnostics
    }
    
    private func generateUserFriendlyDiagnosis(for diagnostics: BackgroundMonitoringDiagnostics) -> String {
        switch diagnostics.backgroundRefreshStatus {
        case .restricted:
            if diagnostics.isLowPowerModeEnabled {
                return "Background monitoring is blocked because Low Power Mode is enabled. This conserves battery but prevents music tracking in the background."
            } else {
                return "Background monitoring is restricted by system policies. This could be due to parental controls, Screen Time restrictions, or corporate device management policies."
            }
            
        case .denied:
            return "Background monitoring is disabled because Background App Refresh has been turned off for this app. You can enable it in Settings."
            
        case .available:
            return "Background monitoring is available and should work normally."
            
        @unknown default:
            return "Background monitoring status is unknown. This may indicate a new iOS version or system issue."
        }
    }
    
    private func generateTroubleshootingSteps(for diagnostics: BackgroundMonitoringDiagnostics) -> [String] {
        var steps: [String] = []
        
        switch diagnostics.backgroundRefreshStatus {
        case .restricted:
            if diagnostics.isLowPowerModeEnabled {
                steps.append("Turn off Low Power Mode: Settings > Battery > Low Power Mode")
            }
            steps.append("Check Screen Time restrictions: Settings > Screen Time > Content & Privacy Restrictions > Background Activities")
            steps.append("If your device is managed by an organization, contact your IT administrator")
            steps.append("Restart your device to clear any temporary restrictions")
            
        case .denied:
            steps.append("Enable Background App Refresh globally: Settings > General > Background App Refresh")
            steps.append("Enable for MusicTracking specifically: Settings > MusicTracking > Background App Refresh")
            
        case .available:
            if diagnostics.isSimulator {
                steps.append("Test on a physical device - simulators have limited background capabilities")
            }
            if diagnostics.backgroundModes.isEmpty {
                steps.append("Contact developer - background modes may not be properly configured")
            }
            
        @unknown default:
            steps.append("Update iOS to the latest version")
            steps.append("Restart the app and try again")
        }
        
        return steps
    }
    
    // MARK: - User-Facing Error Handling
    
    public func getBackgroundMonitoringError() -> AppError? {
        let diagnostics = performComprehensiveBackgroundDiagnostics()
        
        guard !diagnostics.supportsBackgroundMonitoring else {
            return nil // No error if supported
        }
        
        let userInfo: [String: Any] = [
            "diagnosis": diagnostics.userFriendlyDiagnosis,
            "troubleshootingSteps": diagnostics.troubleshootingSteps,
            "backgroundRefreshStatus": diagnostics.backgroundRefreshStatus.rawValue,
            "isLowPowerMode": diagnostics.isLowPowerModeEnabled
        ]
        
        return AppError.backgroundTaskFailedWithDiagnostics(userInfo)
    }

    private func checkBackgroundTaskCapabilities() {
        print("=== Background Task Capabilities ===")
        
        // Check background modes in Info.plist
        if let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] {
            print("Background modes in Info.plist: \(backgroundModes)")
        } else {
            print("❌ No background modes found in Info.plist")
        }
        
        // Check background time remaining
        let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
        print("Background time remaining: \(backgroundTimeRemaining)")
        
        print("=== End Background Task Capabilities ===")
    }

    @MainActor
    private func handleBackgroundModeChange() {
        if UIApplication.shared.applicationState == .background && backgroundMonitoringEnabled {
            Task {
                await backgroundMonitor?.pauseMonitoring()
            }
        } else if UIApplication.shared.applicationState == .active && backgroundMonitoringEnabled {
            Task {
                await backgroundMonitor?.resumeMonitoring()
            }
        }
    }
}

