import Foundation
import CoreData
import MusicKit

public protocol MusicDataRepositoryProtocol {
    func saveListeningSession(_ session: DomainListeningSession) async throws
    func fetchListeningSessions(from startDate: Date, to endDate: Date) async throws -> [DomainListeningSession]
    func fetchListeningSessions(for songID: MusicItemID, limit: Int) async throws -> [DomainListeningSession]
    func fetchRecentListeningSessions(limit: Int) async throws -> [DomainListeningSession]
    func deleteListeningSession(withID id: UUID) async throws
    func deleteAllListeningSessions() async throws
    
    func saveWeeklyStats(_ stats: DomainWeeklyStats) async throws
    func fetchWeeklyStats(for weekStartDate: Date) async throws -> DomainWeeklyStats?
    func fetchAllWeeklyStats() async throws -> [DomainWeeklyStats]
    func deleteWeeklyStats(for weekStartDate: Date) async throws
    func deleteAllWeeklyStats() async throws
    
    func getTotalListeningTime(from startDate: Date, to endDate: Date) async throws -> TimeInterval
    func getUniquesongsCount(from startDate: Date, to endDate: Date) async throws -> Int
    func getTopSongs(from startDate: Date, to endDate: Date, limit: Int) async throws -> [(Song, Int)]
    func getTopArtists(from startDate: Date, to endDate: Date, limit: Int) async throws -> [(String, Int)]
    func getListeningStreaks() async throws -> [ListeningStreak]
    
    func performCleanup() async throws
    func getStorageInfo() async throws -> StorageInfo
}

public struct DomainWeeklyStats {
    public let id: UUID
    public let weekStartDate: Date
    public let totalPlayTime: TimeInterval
    public let uniqueSongsCount: Int
    public let topSongs: [TopSongData]
    public let topArtists: [TopArtistData]
    public let createdAt: Date
    public let updatedAt: Date
    
    public init(id: UUID = UUID(), weekStartDate: Date, totalPlayTime: TimeInterval, uniqueSongsCount: Int, topSongs: [TopSongData] = [], topArtists: [TopArtistData] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.weekStartDate = weekStartDate
        self.totalPlayTime = totalPlayTime
        self.uniqueSongsCount = uniqueSongsCount
        self.topSongs = topSongs
        self.topArtists = topArtists
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TopSongData: Codable {
    public let songID: String
    public let title: String
    public let artistName: String
    public let playCount: Int
    public let totalPlayTime: TimeInterval
    
    public init(songID: String, title: String, artistName: String, playCount: Int, totalPlayTime: TimeInterval) {
        self.songID = songID
        self.title = title
        self.artistName = artistName
        self.playCount = playCount
        self.totalPlayTime = totalPlayTime
    }
}

public struct TopArtistData: Codable {
    public let artistName: String
    public let playCount: Int
    public let totalPlayTime: TimeInterval
    public let uniqueSongsCount: Int
    
    public init(artistName: String, playCount: Int, totalPlayTime: TimeInterval, uniqueSongsCount: Int) {
        self.artistName = artistName
        self.playCount = playCount
        self.totalPlayTime = totalPlayTime
        self.uniqueSongsCount = uniqueSongsCount
    }
}

public struct ListeningStreak {
    public let startDate: Date
    public let endDate: Date
    public let daysCount: Int
    public let totalPlayTime: TimeInterval
    public let averageDailyPlayTime: TimeInterval
    
    public init(startDate: Date, endDate: Date, daysCount: Int, totalPlayTime: TimeInterval) {
        self.startDate = startDate
        self.endDate = endDate
        self.daysCount = daysCount
        self.totalPlayTime = totalPlayTime
        self.averageDailyPlayTime = totalPlayTime / Double(max(daysCount, 1))
    }
}

public struct StorageInfo {
    public let totalSessions: Int
    public let totalWeeklyStats: Int
    public let oldestSessionDate: Date?
    public let newestSessionDate: Date?
    public let estimatedSizeInBytes: Int64
    public let databasePath: String?
    
    public init(totalSessions: Int, totalWeeklyStats: Int, oldestSessionDate: Date?, newestSessionDate: Date?, estimatedSizeInBytes: Int64, databasePath: String?) {
        self.totalSessions = totalSessions
        self.totalWeeklyStats = totalWeeklyStats
        self.oldestSessionDate = oldestSessionDate
        self.newestSessionDate = newestSessionDate
        self.estimatedSizeInBytes = estimatedSizeInBytes
        self.databasePath = databasePath
    }
    
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: estimatedSizeInBytes)
    }
}

extension DomainWeeklyStats: Equatable {
    public static func == (lhs: DomainWeeklyStats, rhs: DomainWeeklyStats) -> Bool {
        lhs.id == rhs.id
    }
}

extension DomainWeeklyStats: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension TopSongData: Equatable {
    public static func == (lhs: TopSongData, rhs: TopSongData) -> Bool {
        lhs.songID == rhs.songID
    }
}

extension TopSongData: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(songID)
    }
}

extension TopArtistData: Equatable {
    public static func == (lhs: TopArtistData, rhs: TopArtistData) -> Bool {
        lhs.artistName == rhs.artistName
    }
}

extension TopArtistData: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(artistName)
    }
}

extension ListeningStreak: Equatable {
    public static func == (lhs: ListeningStreak, rhs: ListeningStreak) -> Bool {
        lhs.startDate == rhs.startDate && lhs.endDate == rhs.endDate
    }
}

extension ListeningStreak: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(startDate)
        hasher.combine(endDate)
    }
}