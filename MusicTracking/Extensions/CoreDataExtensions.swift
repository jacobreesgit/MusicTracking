import Foundation
import CoreData
import MusicKit

extension NSManagedObjectContext {
    
    public func saveIfChanged() throws {
        guard hasChanges else { return }
        try save()
    }
    
    public func performAndSave<T>(_ block: () throws -> T) throws -> T {
        let result = try block()
        try saveIfChanged()
        return result
    }
    
    public func performAndSaveAsync<T>(_ block: @escaping () throws -> T) async throws -> T {
        return try await perform {
            let result = try block()
            try self.saveIfChanged()
            return result
        }
    }
    
    public func findOrCreate<T: NSManagedObject>(
        entity: T.Type,
        predicate: NSPredicate
    ) throws -> T {
        let request = NSFetchRequest<T>(entityName: String(describing: entity))
        request.predicate = predicate
        request.fetchLimit = 1
        
        if let existingObject = try fetch(request).first {
            return existingObject
        } else {
            return T(context: self)
        }
    }
    
    public func countObjects<T: NSManagedObject>(
        ofType entity: T.Type,
        matching predicate: NSPredicate? = nil
    ) throws -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: entity))
        request.predicate = predicate
        request.includesSubentities = false
        request.includesPropertyValues = false
        
        return try count(for: request)
    }
    
    public func deleteAllObjects<T: NSManagedObject>(ofType entity: T.Type) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: entity))
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        
        let result = try execute(deleteRequest) as? NSBatchDeleteResult
        let objectIDArray = result?.result as? [NSManagedObjectID]
        let changes = [NSDeletedObjectsKey: objectIDArray ?? []]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
    }
}

extension Calendar {
    
    public func startOfWeek(for date: Date) -> Date {
        let interval = dateInterval(of: .weekOfYear, for: date)
        return interval?.start ?? date
    }
    
    public func endOfWeek(for date: Date) -> Date {
        let interval = dateInterval(of: .weekOfYear, for: date)
        return interval?.end?.addingTimeInterval(-1) ?? date
    }
    
    public func weekOfYear(for date: Date) -> Int {
        return component(.weekOfYear, from: date)
    }
    
    public func isInCurrentWeek(_ date: Date) -> Bool {
        return isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    public func weeksAgo(_ weeksAgo: Int, from date: Date = Date()) -> Date {
        return self.date(byAdding: .weekOfYear, value: -weeksAgo, to: date) ?? date
    }
}

extension Date {
    
    public var startOfWeek: Date {
        return Calendar.current.startOfWeek(for: self)
    }
    
    public var endOfWeek: Date {
        return Calendar.current.endOfWeek(for: self)
    }
    
    public var startOfDay: Date {
        return Calendar.current.startOfDay(for: self)
    }
    
    public var endOfDay: Date {
        let startOfDay = self.startOfDay
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) ?? self
    }
    
    public func isSameWeek(as otherDate: Date) -> Bool {
        return Calendar.current.isDate(self, equalTo: otherDate, toGranularity: .weekOfYear)
    }
    
    public func isSameDay(as otherDate: Date) -> Bool {
        return Calendar.current.isDate(self, equalTo: otherDate, toGranularity: .day)
    }
    
    public func daysFromNow() -> Int {
        return Calendar.current.dateComponents([.day], from: self, to: Date()).day ?? 0
    }
    
    public func weeksFromNow() -> Int {
        return Calendar.current.dateComponents([.weekOfYear], from: self, to: Date()).weekOfYear ?? 0
    }
}

extension TimeInterval {
    
    public var formattedDuration: String {
        let hours = Int(self / 3600)
        let minutes = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(self.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    public var formattedDurationShort: String {
        let hours = Int(self / 3600)
        let minutes = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    public var formattedDurationMedium: String {
        let hours = Int(self / 3600)
        let minutes = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) minutes"
        }
    }
}

extension Array where Element == TopSongData {
    
    public func merged() -> [TopSongData] {
        let grouped = Dictionary(grouping: self) { $0.songID }
        
        return grouped.compactMap { (songID, songs) in
            guard let first = songs.first else { return nil }
            
            let totalPlayCount = songs.reduce(0) { $0 + $1.playCount }
            let totalPlayTime = songs.reduce(0) { $0 + $1.totalPlayTime }
            
            return TopSongData(
                songID: songID,
                title: first.title,
                artistName: first.artistName,
                playCount: totalPlayCount,
                totalPlayTime: totalPlayTime
            )
        }
        .sorted { $0.playCount > $1.playCount }
    }
}

extension Array where Element == TopArtistData {
    
    public func merged() -> [TopArtistData] {
        let grouped = Dictionary(grouping: self) { $0.artistName }
        
        return grouped.compactMap { (artistName, artists) in
            guard !artists.isEmpty else { return nil }
            
            let totalPlayCount = artists.reduce(0) { $0 + $1.playCount }
            let totalPlayTime = artists.reduce(0) { $0 + $1.totalPlayTime }
            let uniqueSongsCount = artists.reduce(0) { max($0, $1.uniqueSongsCount) }
            
            return TopArtistData(
                artistName: artistName,
                playCount: totalPlayCount,
                totalPlayTime: totalPlayTime,
                uniqueSongsCount: uniqueSongsCount
            )
        }
        .sorted { $0.playCount > $1.playCount }
    }
}

extension ListeningSession {
    
    public func createCoreDataEntity(in context: NSManagedObjectContext) -> ListeningSessionEntity {
        return ListeningSessionEntity(context: context, from: self)
    }
    
    public var isValidSession: Bool {
        return duration > 5.0 && !song.title.isEmpty && !song.artistName.isEmpty
    }
    
    public var completionPercentage: Double {
        guard let songDuration = song.duration, songDuration > 0 else { return 0 }
        return min(duration / songDuration, 1.0) * 100
    }
    
    public var isSignificantListen: Bool {
        guard let songDuration = song.duration else { return duration > 30 }
        return duration >= (songDuration * 0.3)
    }
}

extension WeeklyStats {
    
    public func createCoreDataEntity(in context: NSManagedObjectContext) -> WeeklyStatsEntity {
        return WeeklyStatsEntity(context: context, from: self)
    }
    
    public var averageSessionDuration: TimeInterval {
        guard topSongs.count > 0 else { return 0 }
        let totalSessions = topSongs.reduce(0) { $0 + $1.playCount }
        return totalSessions > 0 ? totalPlayTime / Double(totalSessions) : 0
    }
    
    public var topGenres: [String] {
        return Array(Set(topSongs.flatMap { _ in ["Pop", "Rock"] })).prefix(5).map { $0 }
    }
    
    public var isActiveWeek: Bool {
        return totalPlayTime > 0 && uniqueSongsCount > 0
    }
    
    public var weekRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        let endDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
        
        return "\(formatter.string(from: weekStartDate)) - \(formatter.string(from: endDate))"
    }
}

extension Song {
    
    public var safeTitle: String {
        return title.isEmpty ? "Unknown Title" : title
    }
    
    public var safeArtistName: String {
        return artistName.isEmpty ? "Unknown Artist" : artistName
    }
    
    public var displayName: String {
        return "\(safeTitle) - \(safeArtistName)"
    }
    
    public var hasArtwork: Bool {
        return artworkURL != nil
    }
}

extension NSFetchRequest {
    
    public func withLimit(_ limit: Int) -> Self {
        fetchLimit = limit
        return self
    }
    
    public func withPredicate(_ predicate: NSPredicate) -> Self {
        self.predicate = predicate
        return self
    }
    
    public func withSortDescriptors(_ descriptors: [NSSortDescriptor]) -> Self {
        sortDescriptors = descriptors
        return self
    }
    
    public func optimizedForCounting() -> Self {
        includesSubentities = false
        includesPropertyValues = false
        return self
    }
}