import Foundation
import Observation

@Observable
public final class WeeklyTopViewModel {
    
    public private(set) var weeklyStats: WeeklyStats?
    public private(set) var topSongs: [(Song, Int)] = []
    public private(set) var isLoading: Bool = false
    public private(set) var error: AppError?
    public private(set) var selectedWeek: WeekSelection = WeekSelection.currentWeek()
    public private(set) var availableWeeks: [WeekSelection] = []
    public private(set) var lastUpdated: Date?
    
    private let appStateManager: AppStateManager
    
    public init(appStateManager: AppStateManager) {
        self.appStateManager = appStateManager
        generateAvailableWeeks()
    }
    
    @MainActor
    public func loadWeeklyData() async {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            weeklyStats = try await appStateManager.getWeeklyStats(for: selectedWeek.startDate)
            
            if weeklyStats == nil {
                try await appStateManager.repository.generateWeeklyStatsForWeek(selectedWeek.startDate)
                weeklyStats = try await appStateManager.getWeeklyStats(for: selectedWeek.startDate)
            }
            
            if let stats = weeklyStats {
                topSongs = stats.topSongs.map { topSongData in
                    let song = Song(
                        id: MusicItemID(topSongData.songID),
                        title: topSongData.title,
                        artistName: topSongData.artistName
                    )
                    return (song, topSongData.playCount)
                }
            } else {
                topSongs = try await appStateManager.getTopSongs(
                    limit: 10,
                    timeframe: DateInterval(start: selectedWeek.startDate, end: selectedWeek.endDate)
                )
            }
            
            lastUpdated = Date()
            
        } catch {
            self.error = error as? AppError ?? AppError.from(musicKitError: error)
            weeklyStats = nil
            topSongs = []
        }
        
        isLoading = false
    }
    
    @MainActor
    public func refreshData() async {
        await loadWeeklyData()
    }
    
    @MainActor
    public func selectWeek(_ week: WeekSelection) async {
        guard week != selectedWeek else { return }
        
        selectedWeek = week
        await loadWeeklyData()
    }
    
    @MainActor
    public func goToPreviousWeek() async {
        let previousWeek = selectedWeek.previous()
        await selectWeek(previousWeek)
    }
    
    @MainActor
    public func goToNextWeek() async {
        let nextWeek = selectedWeek.next()
        await selectWeek(nextWeek)
    }
    
    @MainActor
    public func goToCurrentWeek() async {
        let currentWeek = WeekSelection.currentWeek()
        await selectWeek(currentWeek)
    }
    
    private func generateAvailableWeeks() {
        let calendar = Calendar.current
        let currentDate = Date()
        var weeks: [WeekSelection] = []
        
        for weekOffset in 0..<12 {
            let weekDate = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: currentDate) ?? currentDate
            weeks.append(WeekSelection(date: weekDate))
        }
        
        availableWeeks = weeks
    }
    
    public func getTopArtists() -> [(String, Int)] {
        guard let stats = weeklyStats else { return [] }
        return stats.topArtists.map { ($0.artistName, $0.playCount) }
    }
    
    public func getListeningTimeForDay(_ dayIndex: Int) -> TimeInterval {
        return 0
    }
    
    public func getDailyBreakdown() -> [DayStats] {
        let calendar = Calendar.current
        var dayStats: [DayStats] = []
        
        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: selectedWeek.startDate) ?? selectedWeek.startDate
            
            dayStats.append(DayStats(
                date: date,
                dayName: date.dayString,
                listeningTime: getListeningTimeForDay(dayOffset),
                sessionCount: 0
            ))
        }
        
        return dayStats
    }
    
    public func compareWithPreviousWeek() -> WeekComparison? {
        guard let currentStats = weeklyStats else { return nil }
        
        let previousWeek = selectedWeek.previous()
        
        return WeekComparison(
            currentWeek: selectedWeek,
            previousWeek: previousWeek,
            playTimeChange: 0,
            songsChange: 0,
            playTimePercentChange: 0,
            songsPercentChange: 0
        )
    }
    
    public var hasData: Bool {
        return weeklyStats != nil || !topSongs.isEmpty
    }
    
    public var isEmpty: Bool {
        return !isLoading && weeklyStats == nil && topSongs.isEmpty && error == nil
    }
    
    public var canGoNext: Bool {
        return !selectedWeek.isCurrentWeek
    }
    
    public var canGoPrevious: Bool {
        return availableWeeks.last?.startDate != selectedWeek.startDate
    }
    
    public var formattedStats: (playTime: String, songs: String, artists: String, avgSession: String) {
        guard let stats = weeklyStats else {
            return (
                playTime: "0m",
                songs: "0",
                artists: "0",
                avgSession: "0m"
            )
        }
        
        let topArtistsCount = stats.topArtists.count
        let avgSessionDuration = stats.averageSessionDuration
        
        return (
            playTime: stats.totalPlayTime.formattedDurationMedium,
            songs: "\(stats.uniqueSongsCount)",
            artists: "\(topArtistsCount)",
            avgSession: avgSessionDuration.formattedDurationShort
        )
    }
    
    public var weekDisplayName: String {
        if selectedWeek.isCurrentWeek {
            return "This Week"
        } else {
            return selectedWeek.displayName
        }
    }
    
    public var weekProgress: Double {
        guard selectedWeek.isCurrentWeek else { return 1.0 }
        
        let calendar = Calendar.current
        let now = Date()
        let weekStart = selectedWeek.startDate
        let weekEnd = selectedWeek.endDate
        
        let totalDuration = weekEnd.timeIntervalSince(weekStart)
        let elapsed = now.timeIntervalSince(weekStart)
        
        return min(elapsed / totalDuration, 1.0)
    }
}

public struct DayStats {
    public let date: Date
    public let dayName: String
    public let listeningTime: TimeInterval
    public let sessionCount: Int
    
    public var formattedListeningTime: String {
        return listeningTime.formattedDurationShort
    }
    
    public var isToday: Bool {
        return date.isToday
    }
}

public struct WeekComparison {
    public let currentWeek: WeekSelection
    public let previousWeek: WeekSelection
    public let playTimeChange: TimeInterval
    public let songsChange: Int
    public let playTimePercentChange: Double
    public let songsPercentChange: Double
    
    public var hasPositiveChange: Bool {
        return playTimeChange > 0 || songsChange > 0
    }
    
    public var hasSignificantChange: Bool {
        return abs(playTimePercentChange) > 10 || abs(songsPercentChange) > 10
    }
    
    public var formattedPlayTimeChange: String {
        let prefix = playTimeChange >= 0 ? "+" : ""
        return "\(prefix)\(playTimeChange.formattedDurationShort)"
    }
    
    public var formattedSongsChange: String {
        let prefix = songsChange >= 0 ? "+" : ""
        return "\(prefix)\(songsChange)"
    }
    
    public var formattedPlayTimePercentChange: String {
        let prefix = playTimePercentChange >= 0 ? "+" : ""
        return "\(prefix)\(Int(playTimePercentChange))%"
    }
    
    public var formattedSongsPercentChange: String {
        let prefix = songsPercentChange >= 0 ? "+" : ""
        return "\(prefix)\(Int(songsPercentChange))%"
    }
}