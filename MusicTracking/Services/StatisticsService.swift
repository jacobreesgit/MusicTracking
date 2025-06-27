import Foundation
import CoreData
import Observation

@Observable
public final class StatisticsService {
    
    public static let shared = StatisticsService()
    
    public private(set) var isCalculating: Bool = false
    public private(set) var lastCalculationDate: Date?
    public private(set) var calculationError: AppError?
    public private(set) var cachedStats: CachedStatistics?
    
    private let persistenceController: PersistenceController
    private let repository: MusicDataRepositoryProtocol
    private var calculationTask: Task<Void, Never>?
    
    public init(
        persistenceController: PersistenceController = .shared,
        repository: MusicDataRepositoryProtocol
    ) {
        self.persistenceController = persistenceController
        self.repository = repository
        
        print("StatisticsService initialized")
    }
    
    deinit {
        calculationTask?.cancel()
    }
    
    // MARK: - Top Songs
    
    public func getTopSongs(timeframe: TimeInterval, limit: Int = 50) async throws -> [(Song, Int)] {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-timeframe)
        
        return try await performCoreDataQuery { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ListeningSessionEntity")
            
            // Filter by date range
            request.predicate = NSPredicate(
                format: "startTime >= %@ AND startTime <= %@",
                startDate as NSDate,
                endDate as NSDate
            )
            
            // Expression for counting sessions per song
            let songExpression = NSExpressionDescription()
            songExpression.name = "songID"
            songExpression.expression = NSExpression(forKeyPath: "songID")
            songExpression.expressionResultType = .stringAttributeType
            
            let countExpression = NSExpressionDescription()
            countExpression.name = "playCount"
            countExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "songID")])
            countExpression.expressionResultType = .integer32AttributeType
            
            // Additional song info expressions
            let titleExpression = NSExpressionDescription()
            titleExpression.name = "songTitle"
            titleExpression.expression = NSExpression(forKeyPath: "songTitle")
            titleExpression.expressionResultType = .stringAttributeType
            
            let artistExpression = NSExpressionDescription()
            artistExpression.name = "artistName"
            artistExpression.expression = NSExpression(forKeyPath: "artistName")
            artistExpression.expressionResultType = .stringAttributeType
            
            let albumExpression = NSExpressionDescription()
            albumExpression.name = "albumTitle"
            albumExpression.expression = NSExpression(forKeyPath: "albumTitle")
            albumExpression.expressionResultType = .stringAttributeType
            
            let durationExpression = NSExpressionDescription()
            durationExpression.name = "songDuration"
            durationExpression.expression = NSExpression(forKeyPath: "songDuration")
            durationExpression.expressionResultType = .doubleAttributeType
            
            request.propertiesToFetch = [
                songExpression,
                countExpression,
                titleExpression,
                artistExpression,
                albumExpression,
                durationExpression
            ]
            request.propertiesToGroupBy = ["songID", "songTitle", "artistName", "albumTitle", "songDuration"]
            request.resultType = .dictionaryResultType
            request.fetchLimit = limit
            
            // Sort by play count descending
            request.sortDescriptors = [
                NSSortDescriptor(key: "playCount", ascending: false)
            ]
            
            let results = try context.fetch(request)
            
            return results.compactMap { result -> (Song, Int)? in
                guard let dict = result as? [String: Any],
                      let songID = dict["songID"] as? String,
                      let playCount = dict["playCount"] as? Int,
                      let title = dict["songTitle"] as? String,
                      let artist = dict["artistName"] as? String else {
                    return nil
                }
                
                let song = Song(
                    id: MusicItemID(songID),
                    title: title,
                    artistName: artist,
                    albumTitle: dict["albumTitle"] as? String,
                    duration: dict["songDuration"] as? TimeInterval,
                    releaseDate: nil,
                    genreNames: [],
                    isrc: nil,
                    artworkURL: nil
                )
                
                return (song, playCount)
            }
        }
    }
    
    // MARK: - Top Artists
    
    public func getTopArtists(timeframe: TimeInterval, limit: Int = 50) async throws -> [(String, Int)] {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-timeframe)
        
        return try await performCoreDataQuery { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ListeningSessionEntity")
            
            request.predicate = NSPredicate(
                format: "startTime >= %@ AND startTime <= %@",
                startDate as NSDate,
                endDate as NSDate
            )
            
            let artistExpression = NSExpressionDescription()
            artistExpression.name = "artistName"
            artistExpression.expression = NSExpression(forKeyPath: "artistName")
            artistExpression.expressionResultType = .stringAttributeType
            
            let countExpression = NSExpressionDescription()
            countExpression.name = "playCount"
            countExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "artistName")])
            countExpression.expressionResultType = .integer32AttributeType
            
            request.propertiesToFetch = [artistExpression, countExpression]
            request.propertiesToGroupBy = ["artistName"]
            request.resultType = .dictionaryResultType
            request.fetchLimit = limit
            request.sortDescriptors = [
                NSSortDescriptor(key: "playCount", ascending: false)
            ]
            
            let results = try context.fetch(request)
            
            return results.compactMap { result -> (String, Int)? in
                guard let dict = result as? [String: Any],
                      let artistName = dict["artistName"] as? String,
                      let playCount = dict["playCount"] as? Int else {
                    return nil
                }
                return (artistName, playCount)
            }
        }
    }
    
    // MARK: - Top Albums
    
    public func getTopAlbums(timeframe: TimeInterval, limit: Int = 50) async throws -> [(String, String, Int)] {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-timeframe)
        
        return try await performCoreDataQuery { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ListeningSessionEntity")
            
            request.predicate = NSPredicate(
                format: "startTime >= %@ AND startTime <= %@ AND albumTitle != nil",
                startDate as NSDate,
                endDate as NSDate
            )
            
            let albumExpression = NSExpressionDescription()
            albumExpression.name = "albumTitle"
            albumExpression.expression = NSExpression(forKeyPath: "albumTitle")
            albumExpression.expressionResultType = .stringAttributeType
            
            let artistExpression = NSExpressionDescription()
            artistExpression.name = "artistName"
            artistExpression.expression = NSExpression(forKeyPath: "artistName")
            artistExpression.expressionResultType = .stringAttributeType
            
            let countExpression = NSExpressionDescription()
            countExpression.name = "playCount"
            countExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "albumTitle")])
            countExpression.expressionResultType = .integer32AttributeType
            
            request.propertiesToFetch = [albumExpression, artistExpression, countExpression]
            request.propertiesToGroupBy = ["albumTitle", "artistName"]
            request.resultType = .dictionaryResultType
            request.fetchLimit = limit
            request.sortDescriptors = [
                NSSortDescriptor(key: "playCount", ascending: false)
            ]
            
            let results = try context.fetch(request)
            
            return results.compactMap { result -> (String, String, Int)? in
                guard let dict = result as? [String: Any],
                      let albumTitle = dict["albumTitle"] as? String,
                      let artistName = dict["artistName"] as? String,
                      let playCount = dict["playCount"] as? Int else {
                    return nil
                }
                return (albumTitle, artistName, playCount)
            }
        }
    }
    
    // MARK: - Listening Trends
    
    public func getListeningTrends(days: Int = 30) async throws -> [DailyListeningTime] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        
        return try await performCoreDataQuery { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ListeningSessionEntity")
            
            request.predicate = NSPredicate(
                format: "startTime >= %@ AND startTime <= %@",
                startDate as NSDate,
                endDate as NSDate
            )
            
            // Group by day
            let dayExpression = NSExpressionDescription()
            dayExpression.name = "day"
            dayExpression.expression = NSExpression(
                forFunction: "castObject:toType:",
                arguments: [
                    NSExpression(forFunction: "truncateTowardZero:", arguments: [
                        NSExpression(forFunction: "divide:by:", arguments: [
                            NSExpression(forKeyPath: "startTime.timeIntervalSince1970"),
                            NSExpression(forConstantValue: 86400.0)
                        ])
                    ]),
                    NSExpression(forConstantValue: "NSNumber")
                ]
            )
            dayExpression.expressionResultType = .doubleAttributeType
            
            let totalTimeExpression = NSExpressionDescription()
            totalTimeExpression.name = "totalTime"
            totalTimeExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "duration")])
            totalTimeExpression.expressionResultType = .doubleAttributeType
            
            let sessionCountExpression = NSExpressionDescription()
            sessionCountExpression.name = "sessionCount"
            sessionCountExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "duration")])
            sessionCountExpression.expressionResultType = .integer32AttributeType
            
            request.propertiesToFetch = [dayExpression, totalTimeExpression, sessionCountExpression]
            request.propertiesToGroupBy = ["day"]
            request.resultType = .dictionaryResultType
            request.sortDescriptors = [
                NSSortDescriptor(key: "day", ascending: true)
            ]
            
            let results = try context.fetch(request)
            
            return results.compactMap { result -> DailyListeningTime? in
                guard let dict = result as? [String: Any],
                      let dayTimestamp = dict["day"] as? Double,
                      let totalTime = dict["totalTime"] as? TimeInterval,
                      let sessionCount = dict["sessionCount"] as? Int else {
                    return nil
                }
                
                let date = Date(timeIntervalSince1970: dayTimestamp * 86400.0)
                return DailyListeningTime(
                    date: date,
                    totalTime: totalTime,
                    sessionCount: sessionCount
                )
            }
        }
    }
    
    // MARK: - Peak Listening Times
    
    public func getMostPlayedTimeOfDay() async throws -> DateComponents {
        return try await performCoreDataQuery { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ListeningSessionEntity")
            
            // Group by hour of day
            let hourExpression = NSExpressionDescription()
            hourExpression.name = "hour"
            hourExpression.expression = NSExpression(
                forFunction: "modulus:by:",
                arguments: [
                    NSExpression(forFunction: "truncateTowardZero:", arguments: [
                        NSExpression(forFunction: "divide:by:", arguments: [
                            NSExpression(forKeyPath: "startTime.timeIntervalSince1970"),
                            NSExpression(forConstantValue: 3600.0)
                        ])
                    ]),
                    NSExpression(forConstantValue: 24)
                ]
            )
            hourExpression.expressionResultType = .integer32AttributeType
            
            let sessionCountExpression = NSExpressionDescription()
            sessionCountExpression.name = "sessionCount"
            sessionCountExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "startTime")])
            sessionCountExpression.expressionResultType = .integer32AttributeType
            
            request.propertiesToFetch = [hourExpression, sessionCountExpression]
            request.propertiesToGroupBy = ["hour"]
            request.resultType = .dictionaryResultType
            request.sortDescriptors = [
                NSSortDescriptor(key: "sessionCount", ascending: false)
            ]
            request.fetchLimit = 1
            
            let results = try context.fetch(request)
            
            if let firstResult = results.first as? [String: Any],
               let hour = firstResult["hour"] as? Int {
                return DateComponents(hour: hour)
            }
            
            return DateComponents(hour: 12) // Default to noon
        }
    }
    
    // MARK: - Listening Patterns
    
    public func getListeningPatterns(timeframe: TimeInterval) async throws -> ListeningPatterns {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-timeframe)
        
        return try await performCoreDataQuery { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ListeningSessionEntity")
            
            request.predicate = NSPredicate(
                format: "startTime >= %@ AND startTime <= %@",
                startDate as NSDate,
                endDate as NSDate
            )
            
            // Get hourly distribution
            let hourlyDistribution = try await getHourlyDistribution(context: context, startDate: startDate, endDate: endDate)
            
            // Get daily distribution
            let dailyDistribution = try await getDailyDistribution(context: context, startDate: startDate, endDate: endDate)
            
            // Get average session length
            let avgSessionLength = try await getAverageSessionLength(context: context, startDate: startDate, endDate: endDate)
            
            // Get skip rate
            let skipRate = try await getSkipRate(context: context, startDate: startDate, endDate: endDate)
            
            return ListeningPatterns(
                hourlyDistribution: hourlyDistribution,
                dailyDistribution: dailyDistribution,
                averageSessionLength: avgSessionLength,
                skipRate: skipRate,
                timeframe: timeframe
            )
        }
    }
    
    // MARK: - Weekly Stats Generation
    
    public func generateWeeklyStats(for weekStart: Date) async throws -> WeeklyStats {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        
        print("Generating weekly stats for week starting: \(weekStart.mediumString)")
        
        isCalculating = true
        calculationError = nil
        
        defer {
            isCalculating = false
            lastCalculationDate = Date()
        }
        
        do {
            let sessions = try await repository.fetchListeningSessions(from: weekStart, to: weekEnd)
            
            let topSongs = try await getTopSongs(
                timeframe: weekEnd.timeIntervalSince(weekStart),
                limit: 10
            ).filter { _, count in count > 0 }
            
            let topArtists = try await getTopArtists(
                timeframe: weekEnd.timeIntervalSince(weekStart),
                limit: 10
            ).filter { _, count in count > 0 }
            
            let totalPlayTime = sessions.reduce(0) { $0 + $1.duration }
            let totalSessions = sessions.count
            let uniqueSongs = Set(sessions.map { $0.song.id }).count
            let uniqueArtists = Set(sessions.map { $0.song.artistName }).count
            let averageSessionLength = totalSessions > 0 ? totalPlayTime / Double(totalSessions) : 0
            let skippedSessions = sessions.filter { $0.wasSkipped }.count
            let skipRate = totalSessions > 0 ? Double(skippedSessions) / Double(totalSessions) : 0
            
            let weeklyStats = WeeklyStats(
                weekStartDate: weekStart,
                totalPlayTime: totalPlayTime,
                totalSessions: totalSessions,
                uniqueSongs: uniqueSongs,
                uniqueArtists: uniqueArtists,
                averageSessionLength: averageSessionLength,
                skipRate: skipRate,
                topSongs: topSongs.map { $0.0 },
                topArtists: topArtists.map { $0.0 },
                dailyBreakdown: calculateDailyBreakdown(sessions: sessions, weekStart: weekStart),
                generatedAt: Date()
            )
            
            try await repository.saveWeeklyStats(weeklyStats)
            
            print("Weekly stats generated successfully: \(totalSessions) sessions, \(totalPlayTime.formattedDurationMedium) total time")
            
            return weeklyStats
            
        } catch {
            let appError = AppError.backgroundTaskFailed("Failed to generate weekly stats: \(error.localizedDescription)")
            calculationError = appError
            throw appError
        }
    }
    
    // MARK: - Statistics Summary
    
    public func getStatisticsSummary(timeframe: TimeInterval) async throws -> StatisticsSummary {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-timeframe)
        
        let sessions = try await repository.fetchListeningSessions(from: startDate, to: endDate)
        let topSongs = try await getTopSongs(timeframe: timeframe, limit: 5)
        let topArtists = try await getTopArtists(timeframe: timeframe, limit: 5)
        let trends = try await getListeningTrends(days: min(30, Int(timeframe / 86400)))
        
        return StatisticsSummary(
            timeframe: timeframe,
            totalSessions: sessions.count,
            totalPlayTime: sessions.reduce(0) { $0 + $1.duration },
            uniqueSongs: Set(sessions.map { $0.song.id }).count,
            uniqueArtists: Set(sessions.map { $0.song.artistName }).count,
            topSongs: topSongs,
            topArtists: topArtists,
            trends: trends,
            generatedAt: Date()
        )
    }
    
    // MARK: - Cache Management
    
    public func refreshCachedStatistics() async {
        calculationTask?.cancel()
        
        calculationTask = Task {
            do {
                let weeklyStats = try await getStatisticsSummary(timeframe: 7 * 24 * 60 * 60) // 1 week
                let monthlyStats = try await getStatisticsSummary(timeframe: 30 * 24 * 60 * 60) // 1 month
                let yearlyStats = try await getStatisticsSummary(timeframe: 365 * 24 * 60 * 60) // 1 year
                
                await MainActor.run {
                    cachedStats = CachedStatistics(
                        weekly: weeklyStats,
                        monthly: monthlyStats,
                        yearly: yearlyStats,
                        lastUpdated: Date()
                    )
                }
                
                print("Cached statistics refreshed successfully")
                
            } catch {
                await MainActor.run {
                    calculationError = error as? AppError ?? AppError.backgroundTaskFailed("Failed to refresh cached statistics")
                }
                print("Failed to refresh cached statistics: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func performCoreDataQuery<T>(_ query: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            persistenceController.performBackgroundTask { context in
                do {
                    let result = try query(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func getHourlyDistribution(context: NSManagedObjectContext, startDate: Date, endDate: Date) async throws -> [Int: Int] {
        // Implementation for hourly distribution
        return [:]
    }
    
    private func getDailyDistribution(context: NSManagedObjectContext, startDate: Date, endDate: Date) async throws -> [Int: Int] {
        // Implementation for daily distribution (0 = Sunday, 1 = Monday, etc.)
        return [:]
    }
    
    private func getAverageSessionLength(context: NSManagedObjectContext, startDate: Date, endDate: Date) async throws -> TimeInterval {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ListeningSessionEntity")
        request.predicate = NSPredicate(
            format: "startTime >= %@ AND startTime <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        let avgExpression = NSExpressionDescription()
        avgExpression.name = "averageDuration"
        avgExpression.expression = NSExpression(forFunction: "average:", arguments: [NSExpression(forKeyPath: "duration")])
        avgExpression.expressionResultType = .doubleAttributeType
        
        request.propertiesToFetch = [avgExpression]
        request.resultType = .dictionaryResultType
        
        let results = try context.fetch(request)
        
        if let firstResult = results.first as? [String: Any],
           let average = firstResult["averageDuration"] as? TimeInterval {
            return average
        }
        
        return 0
    }
    
    private func getSkipRate(context: NSManagedObjectContext, startDate: Date, endDate: Date) async throws -> Double {
        let totalRequest = NSFetchRequest<NSManagedObject>(entityName: "ListeningSessionEntity")
        totalRequest.predicate = NSPredicate(
            format: "startTime >= %@ AND startTime <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        let totalCountExpression = NSExpressionDescription()
        totalCountExpression.name = "totalCount"
        totalCountExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "startTime")])
        totalCountExpression.expressionResultType = .integer32AttributeType
        
        totalRequest.propertiesToFetch = [totalCountExpression]
        totalRequest.resultType = .dictionaryResultType
        
        let totalResults = try context.fetch(totalRequest)
        guard let totalDict = totalResults.first as? [String: Any],
              let totalCount = totalDict["totalCount"] as? Int,
              totalCount > 0 else {
            return 0
        }
        
        let skippedRequest = NSFetchRequest<NSManagedObject>(entityName: "ListeningSessionEntity")
        skippedRequest.predicate = NSPredicate(
            format: "startTime >= %@ AND startTime <= %@ AND wasSkipped == YES",
            startDate as NSDate,
            endDate as NSDate
        )
        
        let skippedCountExpression = NSExpressionDescription()
        skippedCountExpression.name = "skippedCount"
        skippedCountExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "startTime")])
        skippedCountExpression.expressionResultType = .integer32AttributeType
        
        skippedRequest.propertiesToFetch = [skippedCountExpression]
        skippedRequest.resultType = .dictionaryResultType
        
        let skippedResults = try context.fetch(skippedRequest)
        let skippedCount = (skippedResults.first as? [String: Any])?["skippedCount"] as? Int ?? 0
        
        return Double(skippedCount) / Double(totalCount)
    }
    
    private func calculateDailyBreakdown(sessions: [ListeningSession], weekStart: Date) -> [Date: DailyStats] {
        let calendar = Calendar.current
        var dailyBreakdown: [Date: DailyStats] = [:]
        
        for day in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: day, to: weekStart) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            
            let dailySessions = sessions.filter { session in
                calendar.isDate(session.startTime, inSameDayAs: dayStart)
            }
            
            let totalTime = dailySessions.reduce(0) { $0 + $1.duration }
            let sessionCount = dailySessions.count
            let uniqueSongs = Set(dailySessions.map { $0.song.id }).count
            let uniqueArtists = Set(dailySessions.map { $0.song.artistName }).count
            
            dailyBreakdown[dayStart] = DailyStats(
                date: dayStart,
                totalTime: totalTime,
                sessionCount: sessionCount,
                uniqueSongs: uniqueSongs,
                uniqueArtists: uniqueArtists
            )
        }
        
        return dailyBreakdown
    }
}

// MARK: - Supporting Types

public struct DailyListeningTime {
    public let date: Date
    public let totalTime: TimeInterval
    public let sessionCount: Int
    
    public var averageSessionLength: TimeInterval {
        return sessionCount > 0 ? totalTime / Double(sessionCount) : 0
    }
}

public struct ListeningPatterns {
    public let hourlyDistribution: [Int: Int] // Hour (0-23) -> Session count
    public let dailyDistribution: [Int: Int] // Day of week (0-6) -> Session count
    public let averageSessionLength: TimeInterval
    public let skipRate: Double
    public let timeframe: TimeInterval
}

public struct StatisticsSummary {
    public let timeframe: TimeInterval
    public let totalSessions: Int
    public let totalPlayTime: TimeInterval
    public let uniqueSongs: Int
    public let uniqueArtists: Int
    public let topSongs: [(Song, Int)]
    public let topArtists: [(String, Int)]
    public let trends: [DailyListeningTime]
    public let generatedAt: Date
}

public struct CachedStatistics {
    public let weekly: StatisticsSummary
    public let monthly: StatisticsSummary
    public let yearly: StatisticsSummary
    public let lastUpdated: Date
    
    public var isExpired: Bool {
        Date().timeIntervalSince(lastUpdated) > 3600 // 1 hour
    }
}

public struct DailyStats {
    public let date: Date
    public let totalTime: TimeInterval
    public let sessionCount: Int
    public let uniqueSongs: Int
    public let uniqueArtists: Int
}