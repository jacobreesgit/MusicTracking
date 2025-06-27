import Foundation

public extension Notification.Name {
    
    // MARK: - Music Tracking Events
    static let listeningSessionStarted = Notification.Name("listeningSessionStarted")
    static let listeningSessionCompleted = Notification.Name("listeningSessionCompleted")
    static let listeningSessionPaused = Notification.Name("listeningSessionPaused")
    static let listeningSessionResumed = Notification.Name("listeningSessionResumed")
    static let listeningSessionSkipped = Notification.Name("listeningSessionSkipped")
    
    // MARK: - Background Monitoring Events
    static let backgroundMonitoringStarted = Notification.Name("backgroundMonitoringStarted")
    static let backgroundMonitoringStopped = Notification.Name("backgroundMonitoringStopped")
    static let backgroundMonitoringStateChanged = Notification.Name("backgroundMonitoringStateChanged")
    static let backgroundMonitoringError = Notification.Name("backgroundMonitoringError")
    
    // MARK: - Music Player Events
    static let musicPlayerSongChanged = Notification.Name("musicPlayerSongChanged")
    static let musicPlayerPlaybackStateChanged = Notification.Name("musicPlayerPlaybackStateChanged")
    static let musicPlayerPlaybackTimeChanged = Notification.Name("musicPlayerPlaybackTimeChanged")
    static let musicPlayerVolumeChanged = Notification.Name("musicPlayerVolumeChanged")
    
    // MARK: - Authorization Events
    static let musicKitAuthorizationChanged = Notification.Name("musicKitAuthorizationChanged")
    
    // MARK: - Background Task Events
    static let backgroundTaskRegistered = Notification.Name("backgroundTaskRegistered")
    static let backgroundTaskStarted = Notification.Name("backgroundTaskStarted")
    static let backgroundTaskCompleted = Notification.Name("backgroundTaskCompleted")
    static let backgroundTaskExpired = Notification.Name("backgroundTaskExpired")
    
    // MARK: - Core Data Events
    // Note: Core Data notifications are declared in their respective service files
    
    // MARK: - App State Events
    static let appHealthStatusChanged = Notification.Name("appHealthStatusChanged")
    static let appInitializationCompleted = Notification.Name("appInitializationCompleted")
    static let appInitializationFailed = Notification.Name("appInitializationFailed")
    
    // MARK: - Audio Session Events
    static let audioSessionActivated = Notification.Name("audioSessionActivated")
    static let audioSessionDeactivated = Notification.Name("audioSessionDeactivated")
    static let audioSessionInterrupted = Notification.Name("audioSessionInterrupted")
    static let audioSessionRouteChanged = Notification.Name("audioSessionRouteChanged")
    
    // MARK: - Real-time Update Events
    static let realtimeSessionUpdate = Notification.Name("realtimeSessionUpdate")
    static let realtimeStatsUpdate = Notification.Name("realtimeStatsUpdate")
    static let realtimeDataRefresh = Notification.Name("realtimeDataRefresh")
}

public struct NotificationKeys {
    
    public struct BackgroundMonitoring {
        public static let state = "monitoringState"
        public static let error = "error"
        public static let isActive = "isActive"
        public static let timestamp = "timestamp"
    }
    
    public struct MusicPlayer {
        public static let song = "song"
        public static let playbackState = "playbackState"
        public static let playbackTime = "playbackTime"
        public static let volume = "volume"
        public static let previousSong = "previousSong"
    }
    
    public struct ListeningSession {
        public static let session = "session"
        public static let sessionID = "sessionID"
        public static let song = "song"
        public static let startTime = "startTime"
        public static let endTime = "endTime"
        public static let duration = "duration"
        public static let wasSkipped = "wasSkipped"
    }
    
    public struct Authorization {
        public static let isAuthorized = "isAuthorized"
        public static let status = "status"
        public static let error = "error"
    }
    
    public struct BackgroundTask {
        public static let taskIdentifier = "taskIdentifier"
        public static let taskType = "taskType"
        public static let isSuccessful = "isSuccessful"
        public static let error = "error"
    }
    
    public struct AudioSession {
        public static let category = "category"
        public static let options = "options"
        public static let isActive = "isActive"
        public static let interruptionType = "interruptionType"
        public static let routeChangeReason = "routeChangeReason"
    }
    
    public struct RealtimeUpdate {
        public static let sessions = "sessions"
        public static let stats = "stats"
        public static let updateType = "updateType"
        public static let affectedDate = "affectedDate"
    }
}

public enum BackgroundMonitoringState: String, CaseIterable {
    case inactive = "inactive"
    case starting = "starting"
    case active = "active"
    case paused = "paused"
    case stopping = "stopping"
    case error = "error"
    
    public var isActive: Bool {
        return self == .active
    }
    
    public var canStart: Bool {
        return self == .inactive || self == .error
    }
    
    public var canStop: Bool {
        return self == .active || self == .paused || self == .starting
    }
    
    public var displayName: String {
        switch self {
        case .inactive:
            return "Inactive"
        case .starting:
            return "Starting..."
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        case .stopping:
            return "Stopping..."
        case .error:
            return "Error"
        }
    }
}

public enum RealtimeUpdateType: String, CaseIterable {
    case sessionAdded = "sessionAdded"
    case sessionUpdated = "sessionUpdated"
    case sessionCompleted = "sessionCompleted"
    case statsCalculated = "statsCalculated"
    case dataRefreshed = "dataRefreshed"
    
    public var priority: Int {
        switch self {
        case .sessionAdded, .sessionCompleted:
            return 3
        case .sessionUpdated:
            return 2
        case .statsCalculated, .dataRefreshed:
            return 1
        }
    }
}