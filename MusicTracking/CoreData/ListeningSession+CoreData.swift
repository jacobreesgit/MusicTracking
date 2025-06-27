import Foundation
import CoreData
import MusicKit

@objc(ListeningSessionEntity)
public class ListeningSessionEntity: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ListeningSessionEntity> {
        return NSFetchRequest<ListeningSessionEntity>(entityName: "ListeningSession")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var songTitle: String
    @NSManaged public var artist: String
    @NSManaged public var album: String?
    @NSManaged public var songID: String
    @NSManaged public var timestamp: Date
    @NSManaged public var duration: Double
    @NSManaged public var playCount: Int32
    @NSManaged public var wasSkipped: Bool
    @NSManaged public var skipTime: Double
    @NSManaged public var isComplete: Bool
    @NSManaged public var genreNames: [String]?
    @NSManaged public var artworkURL: String?
    @NSManaged public var isExplicit: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
}

extension ListeningSessionEntity {
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        let now = Date()
        id = UUID()
        timestamp = now
        createdAt = now
        updatedAt = now
        playCount = 1
        wasSkipped = false
        isComplete = false
        skipTime = 0
        duration = 0
        isExplicit = false
    }
    
    public override func willSave() {
        super.willSave()
        
        if isUpdated {
            updatedAt = Date()
        }
    }
    
    public convenience init(context: NSManagedObjectContext, from session: ListeningSession) {
        self.init(context: context)
        
        self.id = session.id
        self.songTitle = session.song.title
        self.artist = session.song.artistName
        self.album = session.song.albumTitle
        self.songID = session.song.id.rawValue
        self.timestamp = session.startTime
        self.duration = session.duration
        self.playCount = Int32(session.playCount)
        self.wasSkipped = session.wasSkipped
        self.skipTime = session.skipTime ?? 0
        self.isComplete = session.isComplete
        self.genreNames = session.song.genreNames
        self.artworkURL = session.song.artworkURL?.absoluteString
        self.isExplicit = session.song.isExplicit
        
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
    
    public func toDomainModel() -> ListeningSession {
        let song = Song(
            id: MusicItemID(songID),
            title: songTitle,
            artistName: artist,
            albumTitle: album,
            duration: duration > 0 ? duration : nil,
            isExplicit: isExplicit,
            genreNames: genreNames ?? [],
            releaseDate: nil,
            artworkURL: artworkURL != nil ? URL(string: artworkURL!) : nil
        )
        
        return ListeningSession(
            id: id,
            song: song,
            startTime: timestamp,
            endTime: isComplete ? timestamp.addingTimeInterval(duration) : nil,
            duration: duration,
            playCount: Int(playCount),
            wasSkipped: wasSkipped,
            skipTime: skipTime > 0 ? skipTime : nil
        )
    }
    
    public func updateFromDomainModel(_ session: ListeningSession) {
        self.songTitle = session.song.title
        self.artist = session.song.artistName
        self.album = session.song.albumTitle
        self.songID = session.song.id.rawValue
        self.timestamp = session.startTime
        self.duration = session.duration
        self.playCount = Int32(session.playCount)
        self.wasSkipped = session.wasSkipped
        self.skipTime = session.skipTime ?? 0
        self.isComplete = session.isComplete
        self.genreNames = session.song.genreNames
        self.artworkURL = session.song.artworkURL?.absoluteString
        self.isExplicit = session.song.isExplicit
        self.updatedAt = Date()
    }
}

extension ListeningSessionEntity {
    
    public static func fetchSessionsInDateRange(
        from startDate: Date,
        to endDate: Date,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<ListeningSessionEntity> {
        let request: NSFetchRequest<ListeningSessionEntity> = fetchRequest()
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ListeningSessionEntity.timestamp, ascending: false)]
        return request
    }
    
    public static func fetchSessionsForSong(
        songID: String,
        limit: Int = 100,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<ListeningSessionEntity> {
        let request: NSFetchRequest<ListeningSessionEntity> = fetchRequest()
        request.predicate = NSPredicate(format: "songID == %@", songID)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ListeningSessionEntity.timestamp, ascending: false)]
        request.fetchLimit = limit
        return request
    }
    
    public static func fetchRecentSessions(
        limit: Int = 50,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<ListeningSessionEntity> {
        let request: NSFetchRequest<ListeningSessionEntity> = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ListeningSessionEntity.timestamp, ascending: false)]
        request.fetchLimit = limit
        return request
    }
    
    public static func fetchSessionsForArtist(
        artistName: String,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<ListeningSessionEntity> {
        let request: NSFetchRequest<ListeningSessionEntity> = fetchRequest()
        request.predicate = NSPredicate(format: "artist == %@", artistName)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ListeningSessionEntity.timestamp, ascending: false)]
        return request
    }
    
    public static func countSessionsInDateRange(
        from startDate: Date,
        to endDate: Date,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<ListeningSessionEntity> {
        let request = fetchSessionsInDateRange(from: startDate, to: endDate, in: context)
        request.includesSubentities = false
        request.includesPropertyValues = false
        return request
    }
    
    public static func fetchTopSongsInDateRange(
        from startDate: Date,
        to endDate: Date,
        limit: Int = 10,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<NSDictionary> {
        let request = NSFetchRequest<NSDictionary>(entityName: "ListeningSession")
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        request.propertiesToFetch = [
            "songID",
            "songTitle",
            "artist"
        ]
        
        request.propertiesToGroupBy = ["songID", "songTitle", "artist"]
        request.resultType = .dictionaryResultType
        request.fetchLimit = limit
        
        let countExpression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "songID")])
        let countExpressionDescription = NSExpressionDescription()
        countExpressionDescription.name = "playCount"
        countExpressionDescription.expression = countExpression
        countExpressionDescription.expressionResultType = .integer32AttributeType
        
        request.propertiesToFetch?.append(countExpressionDescription)
        request.sortDescriptors = [NSSortDescriptor(key: "playCount", ascending: false)]
        
        return request
    }
    
    public static func fetchTopArtistsInDateRange(
        from startDate: Date,
        to endDate: Date,
        limit: Int = 10,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<NSDictionary> {
        let request = NSFetchRequest<NSDictionary>(entityName: "ListeningSession")
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        request.propertiesToFetch = ["artist"]
        request.propertiesToGroupBy = ["artist"]
        request.resultType = .dictionaryResultType
        request.fetchLimit = limit
        
        let countExpression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "artist")])
        let countExpressionDescription = NSExpressionDescription()
        countExpressionDescription.name = "playCount"
        countExpressionDescription.expression = countExpression
        countExpressionDescription.expressionResultType = .integer32AttributeType
        
        let sumExpression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "duration")])
        let sumExpressionDescription = NSExpressionDescription()
        sumExpressionDescription.name = "totalPlayTime"
        sumExpressionDescription.expression = sumExpression
        sumExpressionDescription.expressionResultType = .doubleAttributeType
        
        request.propertiesToFetch?.append(contentsOf: [countExpressionDescription, sumExpressionDescription])
        request.sortDescriptors = [NSSortDescriptor(key: "playCount", ascending: false)]
        
        return request
    }
    
    public static func calculateTotalListeningTime(
        from startDate: Date,
        to endDate: Date,
        in context: NSManagedObjectContext
    ) -> NSFetchRequest<NSDictionary> {
        let request = NSFetchRequest<NSDictionary>(entityName: "ListeningSession")
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        request.resultType = .dictionaryResultType
        
        let sumExpression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "duration")])
        let sumExpressionDescription = NSExpressionDescription()
        sumExpressionDescription.name = "totalDuration"
        sumExpressionDescription.expression = sumExpression
        sumExpressionDescription.expressionResultType = .doubleAttributeType
        
        request.propertiesToFetch = [sumExpressionDescription]
        
        return request
    }
}