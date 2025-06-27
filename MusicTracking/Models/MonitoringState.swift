import Foundation
import MediaPlayer

public struct MonitoringState {
    public let state: BackgroundMonitoringState
    public let isTracking: Bool
    public let currentSong: MPMediaItem?
    public let playbackState: MPMusicPlaybackState
    public let lastActivity: Date?
    public let error: AppError?
    public let sessionCount: Int
    public let uptime: TimeInterval
    
    public init(
        state: BackgroundMonitoringState = .inactive,
        isTracking: Bool = false,
        currentSong: MPMediaItem? = nil,
        playbackState: MPMusicPlaybackState = .stopped,
        lastActivity: Date? = nil,
        error: AppError? = nil,
        sessionCount: Int = 0,
        uptime: TimeInterval = 0
    ) {
        self.state = state
        self.isTracking = isTracking
        self.currentSong = currentSong
        self.playbackState = playbackState
        self.lastActivity = lastActivity
        self.error = error
        self.sessionCount = sessionCount
        self.uptime = uptime
    }
    
    public var isHealthy: Bool {
        return state.isActive && error == nil
    }
    
    public var statusDescription: String {
        if let error = error {
            return "Error: \(error.localizedDescription)"
        }
        
        switch state {
        case .inactive:
            return "Background monitoring is inactive"
        case .starting:
            return "Starting background monitoring..."
        case .active:
            if isTracking {
                return "Actively tracking music"
            } else {
                return "Monitoring in background"
            }
        case .paused:
            return "Monitoring paused"
        case .stopping:
            return "Stopping background monitoring..."
        case .error:
            return "Background monitoring error"
        }
    }
    
    public var detailedStatus: String {
        var components: [String] = [statusDescription]
        
        if let lastActivity = lastActivity {
            components.append("Last activity: \(lastActivity.relativeString)")
        }
        
        if sessionCount > 0 {
            components.append("\(sessionCount) sessions tracked")
        }
        
        if uptime > 0 {
            components.append("Uptime: \(uptime.formattedDurationShort)")
        }
        
        return components.joined(separator: " • ")
    }
    
    public var playbackStateDescription: String {
        switch playbackState {
        case .stopped:
            return "Stopped"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .interrupted:
            return "Interrupted"
        case .seekingForward:
            return "Seeking Forward"
        case .seekingBackward:
            return "Seeking Backward"
        @unknown default:
            return "Unknown"
        }
    }
    
    public var currentSongInfo: (title: String, artist: String)? {
        guard let song = currentSong else { return nil }
        
        let title = song.title ?? "Unknown Title"
        let artist = song.artist ?? "Unknown Artist"
        
        return (title: title, artist: artist)
    }
    
    public func withUpdatedState(_ newState: BackgroundMonitoringState) -> MonitoringState {
        return MonitoringState(
            state: newState,
            isTracking: isTracking,
            currentSong: currentSong,
            playbackState: playbackState,
            lastActivity: lastActivity,
            error: error,
            sessionCount: sessionCount,
            uptime: uptime
        )
    }
    
    public func withError(_ error: AppError) -> MonitoringState {
        return MonitoringState(
            state: .error,
            isTracking: isTracking,
            currentSong: currentSong,
            playbackState: playbackState,
            lastActivity: lastActivity,
            error: error,
            sessionCount: sessionCount,
            uptime: uptime
        )
    }
    
    public func withCurrentSong(_ song: MPMediaItem?) -> MonitoringState {
        return MonitoringState(
            state: state,
            isTracking: isTracking,
            currentSong: song,
            playbackState: playbackState,
            lastActivity: Date(),
            error: error,
            sessionCount: sessionCount,
            uptime: uptime
        )
    }
    
    public func withPlaybackState(_ playbackState: MPMusicPlaybackState) -> MonitoringState {
        return MonitoringState(
            state: state,
            isTracking: playbackState == .playing,
            currentSong: currentSong,
            playbackState: playbackState,
            lastActivity: Date(),
            error: error,
            sessionCount: sessionCount,
            uptime: uptime
        )
    }
    
    public func withIncrementedSessionCount() -> MonitoringState {
        return MonitoringState(
            state: state,
            isTracking: isTracking,
            currentSong: currentSong,
            playbackState: playbackState,
            lastActivity: lastActivity,
            error: error,
            sessionCount: sessionCount + 1,
            uptime: uptime
        )
    }
    
    public func withUpdatedUptime(_ uptime: TimeInterval) -> MonitoringState {
        return MonitoringState(
            state: state,
            isTracking: isTracking,
            currentSong: currentSong,
            playbackState: playbackState,
            lastActivity: lastActivity,
            error: error,
            sessionCount: sessionCount,
            uptime: uptime
        )
    }
}

extension MonitoringState: Equatable {
    public static func == (lhs: MonitoringState, rhs: MonitoringState) -> Bool {
        return lhs.state == rhs.state &&
               lhs.isTracking == rhs.isTracking &&
               lhs.currentSong?.persistentID == rhs.currentSong?.persistentID &&
               lhs.playbackState == rhs.playbackState &&
               lhs.sessionCount == rhs.sessionCount
    }
}

public struct MonitoringMetrics {
    public let totalUptime: TimeInterval
    public let totalSessions: Int
    public let averageSessionDuration: TimeInterval
    public let lastError: AppError?
    public let lastErrorDate: Date?
    public let backgroundTime: TimeInterval
    public let foregroundTime: TimeInterval
    
    public init(
        totalUptime: TimeInterval = 0,
        totalSessions: Int = 0,
        averageSessionDuration: TimeInterval = 0,
        lastError: AppError? = nil,
        lastErrorDate: Date? = nil,
        backgroundTime: TimeInterval = 0,
        foregroundTime: TimeInterval = 0
    ) {
        self.totalUptime = totalUptime
        self.totalSessions = totalSessions
        self.averageSessionDuration = averageSessionDuration
        self.lastError = lastError
        self.lastErrorDate = lastErrorDate
        self.backgroundTime = backgroundTime
        self.foregroundTime = foregroundTime
    }
    
    public var backgroundPercentage: Double {
        guard totalUptime > 0 else { return 0 }
        return (backgroundTime / totalUptime) * 100
    }
    
    public var foregroundPercentage: Double {
        guard totalUptime > 0 else { return 0 }
        return (foregroundTime / totalUptime) * 100
    }
    
    public var successRate: Double {
        guard lastError == nil else { return 0.8 }
        return 1.0
    }
    
    public var formattedMetrics: (uptime: String, sessions: String, avgDuration: String, successRate: String) {
        return (
            uptime: totalUptime.formattedDurationMedium,
            sessions: "\(totalSessions)",
            avgDuration: averageSessionDuration.formattedDurationShort,
            successRate: "\(Int(successRate * 100))%"
        )
    }
}