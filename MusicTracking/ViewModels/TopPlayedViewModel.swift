import Foundation
import Observation

@Observable
public final class TopPlayedViewModel {
    
    public private(set) var topSongs: [(Song, Int)] = []
    public private(set) var topArtists: [(String, Int)] = []
    public private(set) var topAlbums: [(String, String, Int)] = []
    public private(set) var isLoading: Bool = false
    public private(set) var error: AppError?
    public private(set) var timeframe: TopPlayedTimeframe = .allTime
    public private(set) var totalSongs: Int = 0
    public private(set) var totalPlayTime: TimeInterval = 0
    public private(set) var uniqueArtists: Int = 0
    public private(set) var lastUpdated: Date?
    
    private let appStateManager: AppStateManager
    private let statisticsService: StatisticsService
    
    public init(appStateManager: AppStateManager) {
        self.appStateManager = appStateManager
        self.statisticsService = StatisticsService.shared
    }
    
    @MainActor
    public func loadTopSongs() async {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            let timeInterval = timeframe.timeInterval
            
            // Load top songs using StatisticsService
            let songs = try await statisticsService.getTopSongs(
                timeframe: timeInterval,
                limit: 50
            )
            
            // Load top artists
            let artists = try await statisticsService.getTopArtists(
                timeframe: timeInterval,
                limit: 20
            )
            
            // Load top albums
            let albums = try await statisticsService.getTopAlbums(
                timeframe: timeInterval,
                limit: 20
            )
            
            // Calculate additional statistics
            let summary = try await statisticsService.getStatisticsSummary(timeframe: timeInterval)
            
            topSongs = songs
            topArtists = artists
            topAlbums = albums
            totalSongs = summary.uniqueSongs
            totalPlayTime = summary.totalPlayTime
            uniqueArtists = summary.uniqueArtists
            lastUpdated = Date()
            
        } catch {
            self.error = error as? AppError ?? AppError.from(musicKitError: error)
            topSongs = []
            topArtists = []
            topAlbums = []
        }
        
        isLoading = false
    }
    
    @MainActor
    public func refreshData() async {
        await loadTopSongs()
    }
    
    @MainActor
    public func changeTimeframe(_ newTimeframe: TopPlayedTimeframe) async {
        guard newTimeframe != timeframe else { return }
        
        timeframe = newTimeframe
        await loadTopSongs()
    }
    
    public func getTopGenres() -> [String] {
        let allGenres = topSongs.flatMap { $0.0.genreNames }
        let genreCounts = Dictionary(grouping: allGenres) { $0 }
            .mapValues { $0.count }
        
        return genreCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
    
    public func getAveragePlayCount() -> Double {
        guard !topSongs.isEmpty else { return 0 }
        
        let totalPlays = topSongs.reduce(0) { $0 + $1.1 }
        return Double(totalPlays) / Double(topSongs.count)
    }
    
    public func getSongRank(for song: Song) -> Int? {
        return topSongs.firstIndex { $0.0.id == song.id }.map { $0 + 1 }
    }
    
    public func getArtistRank(for artistName: String) -> Int? {
        return topArtists.firstIndex { $0.0 == artistName }.map { $0 + 1 }
    }
    
    public func getTopArtistsSummary() -> [(String, Int)] {
        return Array(topArtists.prefix(10))
    }
    
    public func getTopAlbumsSummary() -> [(String, String, Int)] {
        return Array(topAlbums.prefix(10))
    }
    
    public func getListeningTrends() async throws -> [DailyListeningTime] {
        let days = min(30, Int(timeframe.timeInterval / 86400))
        return try await statisticsService.getListeningTrends(days: days)
    }
    
    public func getListeningPatterns() async throws -> ListeningPatterns {
        return try await statisticsService.getListeningPatterns(timeframe: timeframe.timeInterval)
    }
    
    public var hasData: Bool {
        return !topSongs.isEmpty
    }
    
    public var isEmpty: Bool {
        return !isLoading && topSongs.isEmpty && error == nil
    }
    
    public var hasTrendData: Bool {
        return timeframe != .allTime && hasData
    }
    
    public var formattedStats: (songs: String, playTime: String, artists: String, avgPlays: String) {
        return (
            songs: "\(totalSongs)",
            playTime: totalPlayTime.formattedDurationMedium,
            artists: "\(uniqueArtists)",
            avgPlays: String(format: "%.1f", getAveragePlayCount())
        )
    }
    
    public var timeframeDescription: String {
        switch timeframe {
        case .lastWeek:
            return "Past 7 days"
        case .lastMonth:
            return "Past 30 days"
        case .last3Months:
            return "Past 3 months"
        case .last6Months:
            return "Past 6 months"
        case .lastYear:
            return "Past year"
        case .allTime:
            return "All time"
        }
    }
}

public enum TopPlayedTimeframe: String, CaseIterable {
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"
    case last3Months = "Last 3 Months"
    case last6Months = "Last 6 Months"
    case lastYear = "Last Year"
    case allTime = "All Time"
    
    public var timeInterval: TimeInterval {
        switch self {
        case .lastWeek:
            return 7 * 24 * 60 * 60
        case .lastMonth:
            return 30 * 24 * 60 * 60
        case .last3Months:
            return 90 * 24 * 60 * 60
        case .last6Months:
            return 180 * 24 * 60 * 60
        case .lastYear:
            return 365 * 24 * 60 * 60
        case .allTime:
            return 10 * 365 * 24 * 60 * 60 // 10 years as "all time"
        }
    }
    
    public var dateInterval: DateInterval? {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .lastWeek:
            let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return DateInterval(start: weekAgo, end: now)
        case .lastMonth:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return DateInterval(start: monthAgo, end: now)
        case .last3Months:
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return DateInterval(start: threeMonthsAgo, end: now)
        case .last6Months:
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return DateInterval(start: sixMonthsAgo, end: now)
        case .lastYear:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return DateInterval(start: yearAgo, end: now)
        case .allTime:
            return nil
        }
    }
    
    public var shortDescription: String {
        switch self {
        case .lastWeek:
            return "7d"
        case .lastMonth:
            return "30d"
        case .last3Months:
            return "3m"
        case .last6Months:
            return "6m"
        case .lastYear:
            return "1y"
        case .allTime:
            return "All"
        }
    }
    
    public var icon: String {
        switch self {
        case .lastWeek:
            return "calendar"
        case .lastMonth:
            return "calendar.badge.clock"
        case .last3Months, .last6Months:
            return "calendar.badge.plus"
        case .lastYear:
            return "calendar.circle"
        case .allTime:
            return "infinity"
        }
    }
}