import Foundation
import CoreData
import MusicKit

public final class CoreDataRepository: MusicDataRepositoryProtocol {
    
    private let persistenceController: PersistenceController
    
    public init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
    }
    
    private var context: NSManagedObjectContext {
        return persistenceController.container.viewContext
    }
    
    public func saveListeningSession(_ session: ListeningSession) async throws {
        try await persistenceController.performBackgroundTask { context in
            let predicate = NSPredicate(format: "id == %@", session.id as CVarArg)
            
            let existingSession = try context.findOrCreate(
                entity: ListeningSessionEntity.self,
                predicate: predicate
            )
            
            if existingSession.createdAt == Date(timeIntervalSince1970: 0) {
                _ = ListeningSessionEntity(context: context, from: session)
            } else {
                existingSession.updateFromDomainModel(session)
            }
        }
    }
    
    public func fetchListeningSessions(from startDate: Date, to endDate: Date) async throws -> [ListeningSession] {
        return try await persistenceController.performBackgroundTask { context in
            let request = ListeningSessionEntity.fetchSessionsInDateRange(
                from: startDate,
                to: endDate,
                in: context
            )
            
            let entities = try context.fetch(request)
            return entities.map { $0.toDomainModel() }
        }
    }
    
    public func fetchListeningSessions(for songID: MusicItemID, limit: Int) async throws -> [ListeningSession] {
        return try await persistenceController.performBackgroundTask { context in
            let request = ListeningSessionEntity.fetchSessionsForSong(
                songID: songID.rawValue,
                limit: limit,
                in: context
            )
            
            let entities = try context.fetch(request)
            return entities.map { $0.toDomainModel() }
        }
    }
    
    public func fetchRecentListeningSessions(limit: Int) async throws -> [ListeningSession] {
        return try await persistenceController.performBackgroundTask { context in
            let request = ListeningSessionEntity.fetchRecentSessions(limit: limit, in: context)
            let entities = try context.fetch(request)
            return entities.map { $0.toDomainModel() }
        }
    }
    
    public func deleteListeningSession(withID id: UUID) async throws {
        try await persistenceController.performBackgroundTask { context in
            let request: NSFetchRequest<ListeningSessionEntity> = ListeningSessionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            let sessions = try context.fetch(request)
            for session in sessions {
                context.delete(session)
            }
        }
    }
    
    public func deleteAllListeningSessions() async throws {
        try await persistenceController.performBackgroundTask { context in
            try context.deleteAllObjects(ofType: ListeningSessionEntity.self)
        }
    }
    
    public func saveWeeklyStats(_ stats: WeeklyStats) async throws {
        try await persistenceController.performBackgroundTask { context in
            let weekStart = Calendar.current.startOfWeek(for: stats.weekStartDate)
            let predicate = NSPredicate(format: "weekStartDate == %@", weekStart as NSDate)
            
            let existingStats = try context.findOrCreate(
                entity: WeeklyStatsEntity.self,
                predicate: predicate
            )
            
            if existingStats.createdAt == Date(timeIntervalSince1970: 0) {
                _ = WeeklyStatsEntity(context: context, from: stats)
            } else {
                existingStats.updateFromDomainModel(stats)
            }
        }
    }
    
    public func fetchWeeklyStats(for weekStartDate: Date) async throws -> WeeklyStats? {
        return try await persistenceController.performBackgroundTask { context in
            let request = WeeklyStatsEntity.fetchStatsForWeek(startDate: weekStartDate, in: context)
            let entities = try context.fetch(request)
            return entities.first?.toDomainModel()
        }
    }
    
    public func fetchAllWeeklyStats() async throws -> [WeeklyStats] {
        return try await persistenceController.performBackgroundTask { context in
            let request = WeeklyStatsEntity.fetchAllStats(in: context)
            let entities = try context.fetch(request)
            return entities.map { $0.toDomainModel() }
        }
    }
    
    public func deleteWeeklyStats(for weekStartDate: Date) async throws {
        try await persistenceController.performBackgroundTask { context in
            let weekStart = Calendar.current.startOfWeek(for: weekStartDate)
            let request: NSFetchRequest<WeeklyStatsEntity> = WeeklyStatsEntity.fetchRequest()
            request.predicate = NSPredicate(format: "weekStartDate == %@", weekStart as NSDate)
            
            let stats = try context.fetch(request)
            for stat in stats {
                context.delete(stat)
            }
        }
    }
    
    public func deleteAllWeeklyStats() async throws {
        try await persistenceController.performBackgroundTask { context in
            try context.deleteAllObjects(ofType: WeeklyStatsEntity.self)
        }
    }
    
    public func getTotalListeningTime(from startDate: Date, to endDate: Date) async throws -> TimeInterval {
        return try await persistenceController.performBackgroundTask { context in
            let request = ListeningSessionEntity.calculateTotalListeningTime(
                from: startDate,
                to: endDate,
                in: context
            )
            
            let results = try context.fetch(request)
            guard let result = results.first,
                  let totalDuration = result["totalDuration"] as? Double else {
                return 0
            }
            
            return totalDuration
        }
    }
    
    public func getUniquesongsCount(from startDate: Date, to endDate: Date) async throws -> Int {
        return try await persistenceController.performBackgroundTask { context in
            let request: NSFetchRequest<ListeningSessionEntity> = ListeningSessionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "timestamp >= %@ AND timestamp <= %@",
                startDate as NSDate,
                endDate as NSDate
            )
            request.propertiesToFetch = ["songID"]
            request.returnsDistinctResults = true
            request.resultType = .dictionaryResultType
            
            let results = try context.fetch(request as! NSFetchRequest<NSDictionary>)
            return results.count
        }
    }
    
    public func getTopSongs(from startDate: Date, to endDate: Date, limit: Int) async throws -> [(Song, Int)] {
        return try await persistenceController.performBackgroundTask { context in
            let request = ListeningSessionEntity.fetchTopSongsInDateRange(
                from: startDate,
                to: endDate,
                limit: limit,
                in: context
            )
            
            let results = try context.fetch(request)
            
            return results.compactMap { dict in
                guard let songID = dict["songID"] as? String,
                      let title = dict["songTitle"] as? String,
                      let artist = dict["artist"] as? String,
                      let playCount = dict["playCount"] as? Int else {
                    return nil
                }
                
                let song = Song(
                    id: MusicItemID(songID),
                    title: title,
                    artistName: artist
                )
                
                return (song, playCount)
            }
        }
    }
    
    public func getTopArtists(from startDate: Date, to endDate: Date, limit: Int) async throws -> [(String, Int)] {
        return try await persistenceController.performBackgroundTask { context in
            let request = ListeningSessionEntity.fetchTopArtistsInDateRange(
                from: startDate,
                to: endDate,
                limit: limit,
                in: context
            )
            
            let results = try context.fetch(request)
            
            return results.compactMap { dict in
                guard let artist = dict["artist"] as? String,
                      let playCount = dict["playCount"] as? Int else {
                    return nil
                }
                
                return (artist, playCount)
            }
        }
    }
    
    public func getListeningStreaks() async throws -> [ListeningStreak] {
        return try await persistenceController.performBackgroundTask { context in
            let request: NSFetchRequest<ListeningSessionEntity> = ListeningSessionEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ListeningSessionEntity.timestamp, ascending: true)]
            
            let sessions = try context.fetch(request)
            var streaks: [ListeningStreak] = []
            var currentStreakStart: Date?
            var currentStreakDays: Set<String> = []
            var lastDate: Date?
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            for session in sessions {
                let dayString = dateFormatter.string(from: session.timestamp)
                
                if let last = lastDate,
                   Calendar.current.dateComponents([.day], from: last, to: session.timestamp).day! > 1 {
                    if currentStreakDays.count >= 3 {
                        let streakStart = currentStreakStart ?? last
                        let totalPlayTime = sessions
                            .filter { currentStreakDays.contains(dateFormatter.string(from: $0.timestamp)) }
                            .reduce(0) { $0 + $1.duration }
                        
                        streaks.append(ListeningStreak(
                            startDate: streakStart,
                            endDate: last,
                            daysCount: currentStreakDays.count,
                            totalPlayTime: totalPlayTime
                        ))
                    }
                    
                    currentStreakStart = session.timestamp
                    currentStreakDays = [dayString]
                } else {
                    if currentStreakStart == nil {
                        currentStreakStart = session.timestamp
                    }
                    currentStreakDays.insert(dayString)
                }
                
                lastDate = session.timestamp
            }
            
            if currentStreakDays.count >= 3, let start = currentStreakStart, let end = lastDate {
                let totalPlayTime = sessions
                    .filter { currentStreakDays.contains(dateFormatter.string(from: $0.timestamp)) }
                    .reduce(0) { $0 + $1.duration }
                
                streaks.append(ListeningStreak(
                    startDate: start,
                    endDate: end,
                    daysCount: currentStreakDays.count,
                    totalPlayTime: totalPlayTime
                ))
            }
            
            return streaks.sorted { $0.daysCount > $1.daysCount }
        }
    }
    
    public func performCleanup() async throws {
        try await persistenceController.performBackgroundTask { context in
            let cutoffDate = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
            
            let request: NSFetchRequest<ListeningSessionEntity> = ListeningSessionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
            
            let oldSessions = try context.fetch(request)
            for session in oldSessions {
                context.delete(session)
            }
            
            let statsRequest: NSFetchRequest<WeeklyStatsEntity> = WeeklyStatsEntity.fetchRequest()
            statsRequest.predicate = NSPredicate(format: "weekStartDate < %@", cutoffDate as NSDate)
            
            let oldStats = try context.fetch(statsRequest)
            for stats in oldStats {
                context.delete(stats)
            }
            
            print("Cleaned up \(oldSessions.count) old sessions and \(oldStats.count) old stats")
        }
    }
    
    public func getStorageInfo() async throws -> StorageInfo {
        return try await persistenceController.getStorageInfo()
    }
    
    public func generateWeeklyStatsForWeek(_ weekStartDate: Date) async throws {
        let weekStart = Calendar.current.startOfWeek(for: weekStartDate)
        let weekEnd = Calendar.current.endOfWeek(for: weekStartDate)
        
        let sessions = try await fetchListeningSessions(from: weekStart, to: weekEnd)
        
        guard !sessions.isEmpty else { return }
        
        let totalPlayTime = sessions.reduce(0) { $0 + $1.duration }
        let uniqueSongs = Set(sessions.map { $0.song.id })
        
        let songPlayCounts = Dictionary(grouping: sessions) { $0.song.id }
            .mapValues { $0.count }
        
        let topSongs = songPlayCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { (songID, playCount) in
                let session = sessions.first { $0.song.id == songID }!
                return TopSongData(
                    songID: songID.rawValue,
                    title: session.song.title,
                    artistName: session.song.artistName,
                    playCount: playCount,
                    totalPlayTime: sessions
                        .filter { $0.song.id == songID }
                        .reduce(0) { $0 + $1.duration }
                )
            }
        
        let artistPlayCounts = Dictionary(grouping: sessions) { $0.song.artistName }
            .mapValues { sessions in
                (
                    playCount: sessions.count,
                    totalPlayTime: sessions.reduce(0) { $0 + $1.duration },
                    uniqueSongs: Set(sessions.map { $0.song.id }).count
                )
            }
        
        let topArtists = artistPlayCounts
            .sorted { $0.value.playCount > $1.value.playCount }
            .prefix(10)
            .map { (artistName, data) in
                TopArtistData(
                    artistName: artistName,
                    playCount: data.playCount,
                    totalPlayTime: data.totalPlayTime,
                    uniqueSongsCount: data.uniqueSongs
                )
            }
        
        let weeklyStats = WeeklyStats(
            weekStartDate: weekStart,
            totalPlayTime: totalPlayTime,
            uniqueSongsCount: uniqueSongs.count,
            topSongs: Array(topSongs),
            topArtists: Array(topArtists)
        )
        
        try await saveWeeklyStats(weeklyStats)
    }
    
    public func updateAllWeeklyStats() async throws {
        let allSessions = try await fetchListeningSessions(
            from: Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date(),
            to: Date()
        )
        
        let groupedByWeek = Dictionary(grouping: allSessions) { session in
            Calendar.current.startOfWeek(for: session.startTime)
        }
        
        for (weekStart, _) in groupedByWeek {
            try await generateWeeklyStatsForWeek(weekStart)
        }
    }
}