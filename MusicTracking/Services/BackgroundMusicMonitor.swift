import Foundation
import MediaPlayer
import Observation
import UIKit

@Observable
public final class BackgroundMusicMonitor {
    
    public static let shared = BackgroundMusicMonitor()
    
    public private(set) var state: BackgroundMonitoringState = .inactive
    public private(set) var monitoringState: MonitoringState
    public private(set) var lastError: AppError?
    public private(set) var currentSession: ListeningSession?
    public private(set) var sessionCount: Int = 0
    public private(set) var totalUptime: TimeInterval = 0
    
    private let musicKitService: MusicKitService
    private let repository: MusicDataRepositoryProtocol
    private let audioSessionManager: AudioSessionManager
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var notificationObservers: [NSObjectProtocol] = []
    private var monitoringTask: Task<Void, Never>?
    private var sessionStartTime: Date?
    private var monitoringStartTime: Date?
    private var lastPlaybackState: MPMusicPlaybackState = .stopped
    private var lastCurrentItem: MPMediaItem?
    
    public init(
        musicKitService: MusicKitService = MusicKitService.shared,
        repository: MusicDataRepositoryProtocol,
        audioSessionManager: AudioSessionManager = .shared
    ) {
        self.musicKitService = musicKitService
        self.repository = repository
        self.audioSessionManager = audioSessionManager
        
        self.monitoringState = MonitoringState(
            state: .inactive,
            isTracking: false,
            currentSong: nil,
            playbackState: .stopped,
            lastActivity: nil,
            error: nil,
            sessionCount: 0,
            uptime: 0
        )
        
        setupNotificationObservers()
        print("BackgroundMusicMonitor initialized")
    }
    
    deinit {
        cleanupNotificationObservers()
        stopBackgroundTask()
    }
    
    @MainActor
    public func startMonitoring() async throws {
        guard state.canStart else {
            throw AppError.backgroundTaskFailed("Cannot start monitoring in current state: \(state)")
        }
        
        print("Starting background music monitoring...")
        
        do {
            updateState(.starting)
            
            try audioSessionManager.configureForBackgroundMonitoring()
            try audioSessionManager.activateSession()
            
            startBackgroundTask()
            
            try await setupMusicPlayerMonitoring()
            
            monitoringStartTime = Date()
            updateState(.active)
            
            startMonitoringLoop()
            
            NotificationCenter.default.post(
                name: .backgroundMonitoringStarted,
                object: nil,
                userInfo: [
                    NotificationKeys.BackgroundMonitoring.state: state.rawValue,
                    NotificationKeys.BackgroundMonitoring.timestamp: Date()
                ]
            )
            
            print("Background music monitoring started successfully")
            
        } catch {
            let appError = AppError.backgroundTaskFailed("Failed to start monitoring: \(error.localizedDescription)")
            await handleError(appError)
            throw appError
        }
    }
    
    @MainActor
    public func stopMonitoring() async {
        guard state.canStop else {
            print("Cannot stop monitoring in current state: \(state)")
            return
        }
        
        print("Stopping background music monitoring...")
        
        updateState(.stopping)
        
        await completeCurrentSession()
        
        monitoringTask?.cancel()
        monitoringTask = nil
        
        stopBackgroundTask()
        
        if let startTime = monitoringStartTime {
            totalUptime += Date().timeIntervalSince(startTime)
            monitoringStartTime = nil
        }
        
        updateState(.inactive)
        
        NotificationCenter.default.post(
            name: .backgroundMonitoringStopped,
            object: nil,
            userInfo: [
                NotificationKeys.BackgroundMonitoring.state: state.rawValue,
                NotificationKeys.BackgroundMonitoring.timestamp: Date()
            ]
        )
        
        print("Background music monitoring stopped")
    }
    
    @MainActor
    public func pauseMonitoring() async {
        guard state == .active else { return }
        
        updateState(.paused)
        await completeCurrentSession()
        
        print("Background music monitoring paused")
    }
    
    @MainActor
    public func resumeMonitoring() async {
        guard state == .paused else { return }
        
        updateState(.active)
        startMonitoringLoop()
        
        print("Background music monitoring resumed")
    }
    
    public func getMonitoringMetrics() -> MonitoringMetrics {
        let currentUptime = monitoringStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let totalSessionTime = totalUptime + currentUptime
        
        return MonitoringMetrics(
            totalUptime: totalSessionTime,
            totalSessions: sessionCount,
            averageSessionDuration: sessionCount > 0 ? totalSessionTime / Double(sessionCount) : 0,
            lastError: lastError,
            lastErrorDate: lastError != nil ? Date() : nil,
            backgroundTime: totalSessionTime * 0.8,
            foregroundTime: totalSessionTime * 0.2
        )
    }
    
    private func setupNotificationObservers() {
        let center = NotificationCenter.default
        
        notificationObservers.append(
            center.addObserver(
                forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
                object: musicPlayer,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    await self?.handleNowPlayingItemChanged(notification)
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(
                forName: .MPMusicPlayerControllerPlaybackStateDidChange,
                object: musicPlayer,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    await self?.handlePlaybackStateChanged(notification)
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppDidEnterBackground()
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppWillEnterForeground()
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
    
    private func setupMusicPlayerMonitoring() async throws {
        musicPlayer.beginGeneratingPlaybackNotifications()
        
        lastPlaybackState = musicPlayer.playbackState
        lastCurrentItem = musicPlayer.nowPlayingItem
        
        updateMonitoringState(
            playbackState: lastPlaybackState,
            currentSong: lastCurrentItem
        )
        
        print("Music player monitoring setup completed")
    }
    
    private func startMonitoringLoop() {
        monitoringTask = Task { @MainActor in
            while !Task.isCancelled && state == .active {
                await performMonitoringCycle()
                
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }
    
    @MainActor
    private func performMonitoringCycle() async {
        let currentPlaybackState = musicPlayer.playbackState
        let currentItem = musicPlayer.nowPlayingItem
        
        let playbackStateChanged = currentPlaybackState != lastPlaybackState
        let songChanged = currentItem?.persistentID != lastCurrentItem?.persistentID
        
        if playbackStateChanged || songChanged {
            await handlePlaybackChange(
                newState: currentPlaybackState,
                newItem: currentItem,
                songChanged: songChanged
            )
            
            lastPlaybackState = currentPlaybackState
            lastCurrentItem = currentItem
        }
        
        updateMonitoringState(
            playbackState: currentPlaybackState,
            currentSong: currentItem
        )
    }
    
    @MainActor
    private func handlePlaybackChange(
        newState: MPMusicPlaybackState,
        newItem: MPMediaItem?,
        songChanged: Bool
    ) async {
        if songChanged {
            await completeCurrentSession()
            
            if newState == .playing, let item = newItem {
                await startNewSession(with: item)
            }
        } else {
            switch (lastPlaybackState, newState) {
            case (.stopped, .playing), (.paused, .playing):
                if currentSession == nil, let item = newItem {
                    await startNewSession(with: item)
                } else if let session = currentSession {
                    await resumeSession(session)
                }
                
            case (.playing, .paused):
                if let session = currentSession {
                    await pauseSession(session)
                }
                
            case (.playing, .stopped), (.paused, .stopped):
                await completeCurrentSession()
                
            default:
                break
            }
        }
        
        NotificationCenter.default.post(
            name: .musicPlayerPlaybackStateChanged,
            object: nil,
            userInfo: [
                NotificationKeys.MusicPlayer.playbackState: newState.rawValue,
                NotificationKeys.MusicPlayer.song: newItem as Any
            ]
        )
    }
    
    @MainActor
    private func handleNowPlayingItemChanged(_ notification: Notification) async {
        let newItem = musicPlayer.nowPlayingItem
        
        NotificationCenter.default.post(
            name: .musicPlayerSongChanged,
            object: nil,
            userInfo: [
                NotificationKeys.MusicPlayer.song: newItem as Any,
                NotificationKeys.MusicPlayer.previousSong: lastCurrentItem as Any
            ]
        )
        
        print("Now playing item changed: \(newItem?.title ?? "None")")
    }
    
    @MainActor
    private func handlePlaybackStateChanged(_ notification: Notification) async {
        let newState = musicPlayer.playbackState
        
        print("Playback state changed: \(newState)")
    }
    
    @MainActor
    private func handleAppDidEnterBackground() async {
        print("App entered background - maintaining music monitoring")
        startBackgroundTask()
    }
    
    @MainActor
    private func handleAppWillEnterForeground() async {
        print("App entering foreground - refreshing monitoring state")
        stopBackgroundTask()
    }
    
    @MainActor
    private func startNewSession(with item: MPMediaItem) async {
        guard let song = createSongFromMediaItem(item) else {
            print("Could not create song from media item")
            return
        }
        
        let session = ListeningSession(
            id: UUID(),
            song: song,
            startTime: Date(),
            endTime: nil,
            duration: 0,
            playCount: 1,
            wasSkipped: false,
            skipTime: nil
        )
        
        currentSession = session
        sessionStartTime = Date()
        sessionCount += 1
        
        updateMonitoringState(
            isTracking: true,
            currentSong: item
        )
        
        NotificationCenter.default.post(
            name: .listeningSessionStarted,
            object: nil,
            userInfo: [
                NotificationKeys.ListeningSession.session: session,
                NotificationKeys.ListeningSession.song: song
            ]
        )
        
        print("Started new listening session: \(song.title)")
    }
    
    @MainActor
    private func pauseSession(_ session: ListeningSession) async {
        NotificationCenter.default.post(
            name: .listeningSessionPaused,
            object: nil,
            userInfo: [
                NotificationKeys.ListeningSession.session: session
            ]
        )
        
        print("Paused listening session: \(session.song.title)")
    }
    
    @MainActor
    private func resumeSession(_ session: ListeningSession) async {
        NotificationCenter.default.post(
            name: .listeningSessionResumed,
            object: nil,
            userInfo: [
                NotificationKeys.ListeningSession.session: session
            ]
        )
        
        print("Resumed listening session: \(session.song.title)")
    }
    
    @MainActor
    private func completeCurrentSession() async {
        guard let session = currentSession,
              let startTime = sessionStartTime else {
            return
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        let songDuration = session.song.duration ?? 0
        let wasSkipped = songDuration > 0 && duration < (songDuration * 0.5)
        
        let completedSession = ListeningSession(
            id: session.id,
            song: session.song,
            startTime: session.startTime,
            endTime: endTime,
            duration: duration,
            playCount: session.playCount,
            wasSkipped: wasSkipped,
            skipTime: wasSkipped ? duration : nil
        )
        
        await saveSession(completedSession)
        
        currentSession = nil
        sessionStartTime = nil
        
        updateMonitoringState(
            isTracking: false,
            currentSong: nil
        )
        
        NotificationCenter.default.post(
            name: .listeningSessionCompleted,
            object: nil,
            userInfo: [
                NotificationKeys.ListeningSession.session: completedSession,
                NotificationKeys.ListeningSession.wasSkipped: wasSkipped
            ]
        )
        
        print("Completed listening session: \(completedSession.song.title) (\(duration.formattedDurationMedium))")
    }
    
    private func saveSession(_ session: ListeningSession) async {
        do {
            try await repository.saveListeningSession(session)
            print("Saved listening session: \(session.song.title)")
        } catch {
            let appError = AppError.backgroundTaskFailed("Failed to save session: \(error.localizedDescription)")
            await handleError(appError)
        }
    }
    
    private func createSongFromMediaItem(_ item: MPMediaItem) -> Song? {
        guard let title = item.title,
              let artistName = item.artist else {
            return nil
        }
        
        return Song(
            id: MusicItemID(item.persistentID.description),
            title: title,
            artistName: artistName,
            albumTitle: item.albumTitle,
            duration: item.playbackDuration > 0 ? item.playbackDuration : nil,
            releaseDate: nil,
            genreNames: item.genre.map { [$0] } ?? [],
            isrc: nil,
            artworkURL: nil
        )
    }
    
    private func updateState(_ newState: BackgroundMonitoringState) {
        state = newState
        monitoringState = monitoringState.withUpdatedState(newState)
        
        NotificationCenter.default.post(
            name: .backgroundMonitoringStateChanged,
            object: nil,
            userInfo: [
                NotificationKeys.BackgroundMonitoring.state: newState.rawValue,
                NotificationKeys.BackgroundMonitoring.timestamp: Date()
            ]
        )
    }
    
    private func updateMonitoringState(
        isTracking: Bool? = nil,
        currentSong: MPMediaItem? = nil,
        playbackState: MPMusicPlaybackState? = nil
    ) {
        let currentUptime = monitoringStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        monitoringState = MonitoringState(
            state: state,
            isTracking: isTracking ?? monitoringState.isTracking,
            currentSong: currentSong ?? monitoringState.currentSong,
            playbackState: playbackState ?? monitoringState.playbackState,
            lastActivity: Date(),
            error: lastError,
            sessionCount: sessionCount,
            uptime: totalUptime + currentUptime
        )
    }
    
    @MainActor
    private func handleError(_ error: AppError) async {
        lastError = error
        updateState(.error)
        
        NotificationCenter.default.post(
            name: .backgroundMonitoringError,
            object: nil,
            userInfo: [
                NotificationKeys.BackgroundMonitoring.error: error,
                NotificationKeys.BackgroundMonitoring.timestamp: Date()
            ]
        )
        
        print("Background monitoring error: \(error.localizedDescription)")
    }
    
    private func startBackgroundTask() {
        guard backgroundTaskIdentifier == .invalid else { return }
        
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "BackgroundMusicMonitoring") { [weak self] in
            self?.stopBackgroundTask()
        }
        
        print("Started background task: \(backgroundTaskIdentifier.rawValue)")
    }
    
    private func stopBackgroundTask() {
        guard backgroundTaskIdentifier != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
        
        print("Stopped background task")
    }
}