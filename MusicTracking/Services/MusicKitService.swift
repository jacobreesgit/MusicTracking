import Foundation
import MusicKit
import Observation

@Observable
public final class MusicKitService {
    
    public static let shared = MusicKitService()
    
    public private(set) var isAuthorized: Bool = false
    public private(set) var currentSong: Song?
    public private(set) var playbackState: MusicPlayer.PlaybackStatus = .stopped
    public private(set) var isTracking: Bool = false
    public private(set) var supportsBackgroundMonitoring: Bool = false
    public private(set) var backgroundMonitoringEnabled: Bool = false
    
    private let player = MusicPlayer.shared
    private var playbackObservationTask: Task<Void, Never>?
    private var currentListeningSession: ListeningSession?
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
        
        do {
            guard let currentEntry = player.queue.currentEntry,
                  let song = currentEntry.item else {
                return nil
            }
            
            return Song(from: song)
        } catch {
            throw AppError.from(musicKitError: error)
        }
    }
    
    public func getRecentlyPlayedSongs(limit: Int = 25) async throws -> [Song] {
        guard isAuthorized else {
            throw AppError.musicKitNotAuthorized
        }
        
        do {
            let request = MusicRecentlyPlayedRequest()
            let response = try await request.response()
            
            return response.items.compactMap { item in
                if case .song(let song) = item {
                    return Song(from: song)
                }
                return nil
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
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = limit
            
            let response = try await request.response()
            return response.songs.compactMap { Song(from: $0) }
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
            
            return response.items.first.map { Song(from: $0) }
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
            return response.items.compactMap { Song(from: $0) }
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
            for await playbackStatus in player.state.playbackStatus.values {
                await MainActor.run {
                    self.playbackState = playbackStatus
                    self.handlePlaybackStateChange(playbackStatus)
                }
            }
        }
    }
    
    @MainActor
    private func handlePlaybackStateChange(_ status: MusicPlayer.PlaybackStatus) {
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
                
                let session = ListeningSession(
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
        
        let completedSession = ListeningSession(
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
        supportsBackgroundMonitoring = UIApplication.shared.backgroundRefreshStatus == .available
        print("Background monitoring support: \(supportsBackgroundMonitoring)")
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

