import Foundation
import Observation

@Observable
public final class RecentlyPlayedViewModel {
    
    public private(set) var recentSessions: [DomainListeningSession] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isLoadingMore: Bool = false
    public private(set) var error: AppError?
    public private(set) var hasMoreData: Bool = true
    public private(set) var lastUpdated: Date?
    
    private let appStateManager: AppStateManager
    private let pageSize: Int = 50
    private var currentPage: Int = 0
    private var notificationObservers: [NSObjectProtocol] = []
    private var realtimeUpdatesEnabled: Bool = true
    
    public init(appStateManager: AppStateManager) {
        self.appStateManager = appStateManager
        setupRealtimeUpdates()
    }
    
    deinit {
        cleanupNotificationObservers()
    }
    
    @MainActor
    public func loadRecentSessions() async {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        currentPage = 0
        
        do {
            let sessions = try await appStateManager.getRecentListeningSessions(limit: pageSize)
            recentSessions = sessions
            hasMoreData = sessions.count >= pageSize
            lastUpdated = Date()
            
        } catch {
            self.error = error as? AppError ?? AppError.from(musicKitError: error)
            recentSessions = []
        }
        
        isLoading = false
    }
    
    @MainActor
    public func loadMoreSessions() async {
        guard !isLoadingMore && hasMoreData && !isLoading else { return }
        
        isLoadingMore = true
        
        do {
            let _ = (currentPage + 1) * pageSize
            let endDate = recentSessions.last?.startTime ?? Date()
            
            let olderSessions = try await appStateManager.repository.fetchListeningSessions(
                from: Calendar.current.date(byAdding: .year, value: -1, to: endDate) ?? endDate,
                to: endDate
            )
            
            let newSessions = Array(olderSessions.dropFirst(recentSessions.count).prefix(pageSize))
            
            if !newSessions.isEmpty {
                recentSessions.append(contentsOf: newSessions)
                currentPage += 1
                hasMoreData = newSessions.count >= pageSize
            } else {
                hasMoreData = false
            }
            
        } catch {
            self.error = error as? AppError ?? AppError.from(musicKitError: error)
        }
        
        isLoadingMore = false
    }
    
    @MainActor
    public func refreshData() async {
        await loadRecentSessions()
    }
    
    public func getSessionsGroupedByDate() -> [(Date, [DomainListeningSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: recentSessions) { session in
            calendar.startOfDay(for: session.startTime)
        }
        
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date, sessions) in
                (date, sessions.sorted { $0.startTime > $1.startTime })
            }
    }
    
    public func getSessionsForToday() -> [DomainListeningSession] {
        let calendar = Calendar.current
        return recentSessions.filter { calendar.isDateInToday($0.startTime) }
    }
    
    public func getSessionsForYesterday() -> [DomainListeningSession] {
        let calendar = Calendar.current
        return recentSessions.filter { calendar.isDateInYesterday($0.startTime) }
    }
    
    public func getSessionsForThisWeek() -> [DomainListeningSession] {
        let calendar = Calendar.current
        return recentSessions.filter { calendar.isDate($0.startTime, equalTo: Date(), toGranularity: .weekOfYear) }
    }
    
    public func getTotalListeningTime(for date: Date) -> TimeInterval {
        let calendar = Calendar.current
        return recentSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: date) }
            .reduce(0) { $0 + $1.duration }
    }
    
    public func getUniqueArtistsCount(for date: Date) -> Int {
        let calendar = Calendar.current
        let artistsForDate = Set(recentSessions
            .filter { calendar.isDate($0.startTime, inSameDayAs: date) }
            .map { $0.song.artistName })
        return artistsForDate.count
    }
    
    public func getMostPlayedArtist(for date: Date) -> String? {
        let calendar = Calendar.current
        let sessionsForDate = recentSessions.filter { calendar.isDate($0.startTime, inSameDayAs: date) }
        
        let artistCounts = Dictionary(grouping: sessionsForDate) { $0.song.artistName }
            .mapValues { $0.count }
        
        return artistCounts.max { $0.value < $1.value }?.key
    }
    
    public func getListeningStreak() -> Int {
        let calendar = Calendar.current
        let today = Date()
        var streak = 0
        
        for dayOffset in 0..<365 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            let hasListening = recentSessions.contains { calendar.isDate($0.startTime, inSameDayAs: date) }
            
            if hasListening {
                streak += 1
            } else if dayOffset > 0 {
                break
            } else {
                break
            }
        }
        
        return streak
    }
    
    public var hasData: Bool {
        return !recentSessions.isEmpty
    }
    
    public var isEmpty: Bool {
        return !isLoading && recentSessions.isEmpty && error == nil
    }
    
    public var totalSessionsCount: Int {
        return recentSessions.count
    }
    
    public var totalListeningTime: TimeInterval {
        return recentSessions.reduce(0) { $0 + $1.duration }
    }
    
    public var uniqueArtistsCount: Int {
        return Set(recentSessions.map { $0.song.artistName }).count
    }
    
    public var uniqueSongsCount: Int {
        return Set(recentSessions.map { $0.song.id }).count
    }
    
    public var averageSessionDuration: TimeInterval {
        guard !recentSessions.isEmpty else { return 0 }
        return totalListeningTime / Double(recentSessions.count)
    }
    
    public var formattedStats: (sessions: String, time: String, artists: String, songs: String) {
        return (
            sessions: "\(totalSessionsCount)",
            time: totalListeningTime.formattedDurationMedium,
            artists: "\(uniqueArtistsCount)",
            songs: "\(uniqueSongsCount)"
        )
    }
    
    public func shouldLoadMore(for session: DomainListeningSession) -> Bool {
        guard let lastSession = recentSessions.last else { return false }
        return session.id == lastSession.id && hasMoreData && !isLoadingMore
    }
    
    @MainActor
    public func enableRealtimeUpdates() {
        realtimeUpdatesEnabled = true
        print("Real-time updates enabled for RecentlyPlayedViewModel")
    }
    
    @MainActor
    public func disableRealtimeUpdates() {
        realtimeUpdatesEnabled = false
        print("Real-time updates disabled for RecentlyPlayedViewModel")
    }
    
    private func setupRealtimeUpdates() {
        let center = NotificationCenter.default
        
        notificationObservers.append(
            center.addObserver(
                forName: .listeningSessionCompleted,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    await self?.handleSessionCompleted(notification)
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(
                forName: .realtimeSessionUpdate,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    await self?.handleRealtimeSessionUpdate(notification)
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(
                forName: .realtimeDataRefresh,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    await self?.handleRealtimeDataRefresh(notification)
                }
            }
        )
        
        notificationObservers.append(
            center.addObserver(
                forName: .backgroundMonitoringStateChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    await self?.handleBackgroundMonitoringStateChange(notification)
                }
            }
        )
        
        print("Real-time update observers setup for RecentlyPlayedViewModel")
    }
    
    private func cleanupNotificationObservers() {
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
    
    @MainActor
    private func handleSessionCompleted(_ notification: Notification) async {
        guard realtimeUpdatesEnabled else { return }
        
        guard let session = notification.userInfo?[NotificationKeys.ListeningSession.session] as? DomainListeningSession else {
            return
        }
        
        recentSessions.insert(session, at: 0)
        
        if recentSessions.count > pageSize * 3 {
            recentSessions = Array(recentSessions.prefix(pageSize * 2))
        }
        
        lastUpdated = Date()
        
        NotificationCenter.default.post(
            name: .realtimeSessionUpdate,
            object: nil,
            userInfo: [
                NotificationKeys.RealtimeUpdate.updateType: RealtimeUpdateType.sessionAdded.rawValue,
                NotificationKeys.RealtimeUpdate.sessions: [session]
            ]
        )
        
        print("Added new session to recent sessions: \(session.song.title)")
    }
    
    @MainActor
    private func handleRealtimeSessionUpdate(_ notification: Notification) async {
        guard realtimeUpdatesEnabled else { return }
        
        guard let updateTypeString = notification.userInfo?[NotificationKeys.RealtimeUpdate.updateType] as? String,
              let updateType = RealtimeUpdateType(rawValue: updateTypeString) else {
            return
        }
        
        switch updateType {
        case .sessionAdded:
            lastUpdated = Date()
            
        case .sessionUpdated:
            await refreshMostRecentSessions()
            
        case .sessionCompleted:
            lastUpdated = Date()
            
        case .dataRefreshed:
            await loadRecentSessions()
            
        case .statsCalculated:
            lastUpdated = Date()
        }
        
        print("Handled real-time update: \(updateType.rawValue)")
    }
    
    @MainActor
    private func handleRealtimeDataRefresh(_ notification: Notification) async {
        guard realtimeUpdatesEnabled else { return }
        
        let affectedDate = notification.userInfo?[NotificationKeys.RealtimeUpdate.affectedDate] as? Date
        
        if let date = affectedDate {
            let calendar = Calendar.current
            let shouldRefresh = recentSessions.contains { session in
                calendar.isDate(session.startTime, inSameDayAs: date)
            }
            
            if shouldRefresh {
                await loadRecentSessions()
            }
        } else {
            await loadRecentSessions()
        }
        
        print("Handled real-time data refresh")
    }
    
    @MainActor
    private func handleBackgroundMonitoringStateChange(_ notification: Notification) async {
        guard realtimeUpdatesEnabled else { return }
        
        guard let stateString = notification.userInfo?[NotificationKeys.BackgroundMonitoring.state] as? String,
              let state = BackgroundMonitoringState(rawValue: stateString) else {
            return
        }
        
        if state == .active {
            await refreshMostRecentSessions()
        }
        
        print("Background monitoring state changed to: \(state.displayName)")
    }
    
    @MainActor
    private func refreshMostRecentSessions() async {
        do {
            let mostRecentSessions = try await appStateManager.getRecentListeningSessions(limit: 10)
            
            if !mostRecentSessions.isEmpty {
                for session in mostRecentSessions.reversed() {
                    if !recentSessions.contains(where: { $0.id == session.id }) {
                        recentSessions.insert(session, at: 0)
                    }
                }
                
                if recentSessions.count > pageSize * 3 {
                    recentSessions = Array(recentSessions.prefix(pageSize * 2))
                }
                
                lastUpdated = Date()
            }
        } catch {
            print("Failed to refresh most recent sessions: \(error)")
        }
    }
    
    public func getRealtimeStatus() -> (enabled: Bool, lastUpdate: Date?, sessionsCount: Int) {
        return (
            enabled: realtimeUpdatesEnabled,
            lastUpdate: lastUpdated,
            sessionsCount: recentSessions.count
        )
    }
}