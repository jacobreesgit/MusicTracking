import Foundation
import CoreData

@objc(WeeklyStatsEntity)
public class WeeklyStatsEntity: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<WeeklyStatsEntity> {
        return NSFetchRequest<WeeklyStatsEntity>(entityName: "WeeklyStats")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var weekStartDate: Date
    @NSManaged public var totalPlayTime: Double
    @NSManaged public var uniqueSongsCount: Int32
    @NSManaged public var topSongsData: Data?
    @NSManaged public var topArtistsData: Data?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var totalSessions: Int32
    @NSManaged public var averageSessionDuration: Double
    @NSManaged public var mostActiveDay: String?
    @NSManaged public var longestStreak: Int32
}

extension WeeklyStatsEntity {
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        let now = Date()
        id = UUID()
        weekStartDate = now
        createdAt = now
        updatedAt = now
        totalPlayTime = 0
        uniqueSongsCount = 0
        totalSessions = 0
        averageSessionDuration = 0
        longestStreak = 0
    }
    
    public override func willSave() {
        super.willSave()
        
        if isUpdated {
            updatedAt = Date()
        }
    }
    
    public convenience init(context: NSManagedObjectContext, from stats: DomainWeeklyStats) {
        self.init(context: context)
        
        self.id = stats.id
        self.weekStartDate = stats.weekStartDate
        self.totalPlayTime = stats.totalPlayTime
        self.uniqueSongsCount = Int32(stats.uniqueSongsCount)
        
        if !stats.topSongs.isEmpty {
            self.topSongsData = try? JSONEncoder().encode(stats.topSongs)
        }
        
        if !stats.topArtists.isEmpty {
            self.topArtistsData = try? JSONEncoder().encode(stats.topArtists)
        }
        
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
    
    public func toDomainModel() -> DomainWeeklyStats {
        var topSongs: [TopSongData] = []
        var topArtists: [TopArtistData] = []
        
        if let data = topSongsData {
            topSongs = (try? JSONDecoder().decode([TopSongData].self, from: data)) ?? []
        }
        
        if let data = topArtistsData {
            topArtists = (try? JSONDecoder().decode([TopArtistData].self, from: data)) ?? []
        }
        
        return DomainWeeklyStats(
            id: id,
            weekStartDate: weekStartDate,
            totalPlayTime: totalPlayTime,
            uniqueSongsCount: Int(uniqueSongsCount),
            topSongs: topSongs,
            topArtists: topArtists,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    public func updateFromDomainModel(_ stats: DomainWeeklyStats) {
        self.weekStartDate = stats.weekStartDate
        self.totalPlayTime = stats.totalPlayTime
        self.uniqueSongsCount = Int32(stats.uniqueSongsCount)
        
        if !stats.topSongs.isEmpty {
            self.topSongsData = try? JSONEncoder().encode(stats.topSongs)
        }
        
        if !stats.topArtists.isEmpty {
            self.topArtistsData = try? JSONEncoder().encode(stats.topArtists)
        }
        
        self.updatedAt = Date()
    }
    
    public var topSongs: [TopSongData] {
        get {
            guard let data = topSongsData else { return [] }
            return (try? JSONDecoder().decode([TopSongData].self, from: data)) ?? []
        }
        set {
            topSongsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    public var topArtists: [TopArtistData] {
        get {
            guard let data = topArtistsData else { return [] }
            return (try? JSONDecoder().decode([TopArtistData].self, from: data)) ?? []
        }
        set {
            topArtistsData = try? JSONEncoder().encode(newValue)
        }
    }
}

extension WeeklyStatsEntity {
    
    public static func fetchStatsForWeek(
        startDate: Date,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<WeeklyStatsEntity> {
        let request: NSFetchRequest<WeeklyStatsEntity> = fetchRequest()
        
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start ?? startDate
        
        request.predicate = NSPredicate(format: "weekStartDate == %@", weekStart as NSDate)
        return request
    }
    
    public static func fetchAllStats(
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<WeeklyStatsEntity> {
        let request: NSFetchRequest<WeeklyStatsEntity> = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WeeklyStatsEntity.weekStartDate, ascending: false)]
        return request
    }
    
    public static func fetchRecentStats(
        limit: Int = 12,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<WeeklyStatsEntity> {
        let request: NSFetchRequest<WeeklyStatsEntity> = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WeeklyStatsEntity.weekStartDate, ascending: false)]
        request.fetchLimit = limit
        return request
    }
    
    public static func fetchStatsInDateRange(
        from startDate: Date,
        to endDate: Date,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<WeeklyStatsEntity> {
        let request: NSFetchRequest<WeeklyStatsEntity> = fetchRequest()
        request.predicate = NSPredicate(
            format: "weekStartDate >= %@ AND weekStartDate <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WeeklyStatsEntity.weekStartDate, ascending: false)]
        return request
    }
    
    public static func fetchStatsWithMinimumPlayTime(
        minimumHours: Double,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<WeeklyStatsEntity> {
        let request: NSFetchRequest<WeeklyStatsEntity> = fetchRequest()
        request.predicate = NSPredicate(format: "totalPlayTime >= %f", minimumHours * 3600)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WeeklyStatsEntity.totalPlayTime, ascending: false)]
        return request
    }
    
    public static func calculateAverageWeeklyPlayTime(
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<NSDictionary> {
        let request = NSFetchRequest<NSDictionary>(entityName: "WeeklyStats")
        request.resultType = .dictionaryResultType
        
        let avgExpression = NSExpression(forFunction: "average:", arguments: [NSExpression(forKeyPath: "totalPlayTime")])
        let avgExpressionDescription = NSExpressionDescription()
        avgExpressionDescription.name = "averagePlayTime"
        avgExpressionDescription.expression = avgExpression
        avgExpressionDescription.expressionResultType = .doubleAttributeType
        
        request.propertiesToFetch = [avgExpressionDescription]
        
        return request
    }
    
    public static func findPeakWeek(
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<WeeklyStatsEntity> {
        let request: NSFetchRequest<WeeklyStatsEntity> = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WeeklyStatsEntity.totalPlayTime, ascending: false)]
        request.fetchLimit = 1
        return request
    }
    
    public static func countWeeksWithActivity(
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<WeeklyStatsEntity> {
        let request: NSFetchRequest<WeeklyStatsEntity> = fetchRequest()
        request.predicate = NSPredicate(format: "totalPlayTime > 0")
        request.includesSubentities = false
        request.includesPropertyValues = false
        return request
    }
}

extension WeeklyStatsEntity {
    
    public func calculateWeeklyGrowth(compared previousWeek: WeeklyStatsEntity?) -> WeeklyGrowthStats {
        guard let previous = previousWeek else {
            return WeeklyGrowthStats(
                playTimeChange: 0,
                songsChange: 0,
                playTimePercentChange: 0,
                songsPercentChange: 0
            )
        }
        
        let playTimeChange = totalPlayTime - previous.totalPlayTime
        let songsChange = Int(uniqueSongsCount - previous.uniqueSongsCount)
        
        let playTimePercentChange = previous.totalPlayTime > 0 ? (playTimeChange / previous.totalPlayTime) * 100 : 0
        let songsPercentChange = previous.uniqueSongsCount > 0 ? (Double(songsChange) / Double(previous.uniqueSongsCount)) * 100 : 0
        
        return WeeklyGrowthStats(
            playTimeChange: playTimeChange,
            songsChange: songsChange,
            playTimePercentChange: playTimePercentChange,
            songsPercentChange: songsPercentChange
        )
    }
    
    public var weekEndDate: Date {
        return Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }
    
    public var isCurrentWeek: Bool {
        let calendar = Calendar.current
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return calendar.isDate(weekStartDate, inSameDayAs: currentWeekStart)
    }
    
    public var formattedWeekRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        let startString = formatter.string(from: weekStartDate)
        let endString = formatter.string(from: weekEndDate)
        
        return "\(startString) - \(endString)"
    }
    
    public var formattedPlayTime: String {
        let hours = Int(totalPlayTime / 3600)
        let minutes = Int((totalPlayTime.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

public struct WeeklyGrowthStats {
    public let playTimeChange: Double
    public let songsChange: Int
    public let playTimePercentChange: Double
    public let songsPercentChange: Double
    
    public var hasPositiveGrowth: Bool {
        return playTimeChange > 0 || songsChange > 0
    }
    
    public var hasSignificantChange: Bool {
        return abs(playTimePercentChange) > 10 || abs(songsPercentChange) > 10
    }
}