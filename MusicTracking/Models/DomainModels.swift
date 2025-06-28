import Foundation
import MusicKit
import UIKit

public struct Song {
    public let id: MusicItemID
    public let title: String
    public let artistName: String
    public let albumTitle: String?
    public let duration: TimeInterval?
    public let isExplicit: Bool
    public let genreNames: [String]
    public let releaseDate: Date?
    public let artworkURL: URL?
    
    public init(from musicKitSong: MusicKit.Song) {
        self.id = musicKitSong.id
        self.title = musicKitSong.title
        self.artistName = musicKitSong.artistName
        self.albumTitle = musicKitSong.albumTitle
        self.duration = musicKitSong.duration
        self.isExplicit = musicKitSong.contentRating == .explicit
        self.genreNames = musicKitSong.genreNames
        self.releaseDate = musicKitSong.releaseDate
        self.artworkURL = musicKitSong.artwork?.url(width: 300, height: 300)
    }
    
    public init(id: MusicItemID, title: String, artistName: String, albumTitle: String? = nil, duration: TimeInterval? = nil, isExplicit: Bool = false, genreNames: [String] = [], releaseDate: Date? = nil, artworkURL: URL? = nil) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.duration = duration
        self.isExplicit = isExplicit
        self.genreNames = genreNames
        self.releaseDate = releaseDate
        self.artworkURL = artworkURL
    }
}

public struct Artist {
    public let id: MusicItemID
    public let name: String
    public let genreNames: [String]
    public let artworkURL: URL?
    
    public init(from musicKitArtist: MusicKit.Artist) {
        self.id = musicKitArtist.id
        self.name = musicKitArtist.name
        self.genreNames = musicKitArtist.genreNames ?? []
        self.artworkURL = musicKitArtist.artwork?.url(width: 300, height: 300)
    }
    
    public init(id: MusicItemID, name: String, genreNames: [String] = [], artworkURL: URL? = nil) {
        self.id = id
        self.name = name
        self.genreNames = genreNames
        self.artworkURL = artworkURL
    }
}

public struct Album {
    public let id: MusicItemID
    public let title: String
    public let artistName: String
    public let releaseDate: Date?
    public let genreNames: [String]
    public let trackCount: Int?
    public let artworkURL: URL?
    public let isExplicit: Bool
    
    public init(from musicKitAlbum: MusicKit.Album) {
        self.id = musicKitAlbum.id
        self.title = musicKitAlbum.title
        self.artistName = musicKitAlbum.artistName
        self.releaseDate = musicKitAlbum.releaseDate
        self.genreNames = musicKitAlbum.genreNames
        self.trackCount = musicKitAlbum.trackCount
        self.artworkURL = musicKitAlbum.artwork?.url(width: 300, height: 300)
        self.isExplicit = musicKitAlbum.contentRating == .explicit
    }
    
    public init(id: MusicItemID, title: String, artistName: String, releaseDate: Date? = nil, genreNames: [String] = [], trackCount: Int? = nil, artworkURL: URL? = nil, isExplicit: Bool = false) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.releaseDate = releaseDate
        self.genreNames = genreNames
        self.trackCount = trackCount
        self.artworkURL = artworkURL
        self.isExplicit = isExplicit
    }
}

public struct DomainListeningSession {
    public let id: UUID
    public let song: Song
    public let startTime: Date
    public let endTime: Date?
    public let duration: TimeInterval
    public let playCount: Int
    public let wasSkipped: Bool
    public let skipTime: TimeInterval?
    
    public var isComplete: Bool {
        endTime != nil
    }
    
    public var actualDuration: TimeInterval {
        if let endTime = endTime {
            return endTime.timeIntervalSince(startTime)
        }
        return duration
    }
    
    public init(id: UUID = UUID(), song: Song, startTime: Date = Date(), endTime: Date? = nil, duration: TimeInterval, playCount: Int = 1, wasSkipped: Bool = false, skipTime: TimeInterval? = nil) {
        self.id = id
        self.song = song
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.playCount = playCount
        self.wasSkipped = wasSkipped
        self.skipTime = skipTime
    }
}

extension Song: Equatable {
    public static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }
}

extension Song: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Artist: Equatable {
    public static func == (lhs: Artist, rhs: Artist) -> Bool {
        lhs.id == rhs.id
    }
}

extension Artist: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Album: Equatable {
    public static func == (lhs: Album, rhs: Album) -> Bool {
        lhs.id == rhs.id
    }
}

extension Album: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension DomainListeningSession: Equatable {
    public static func == (lhs: DomainListeningSession, rhs: DomainListeningSession) -> Bool {
        lhs.id == rhs.id
    }
}

extension DomainListeningSession: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Background Monitoring Diagnostics

public struct BackgroundMonitoringDiagnostics {
    public var backgroundRefreshStatus: UIBackgroundRefreshStatus = .denied
    public var supportsBackgroundMonitoring: Bool = false
    public var isLowPowerModeEnabled: Bool = false
    public var isSimulator: Bool = false
    public var deviceModel: String = ""
    public var iOSVersion: String = ""
    public var applicationState: UIApplication.State = .inactive
    public var availableMemoryMB: Int = 0
    public var usedMemoryMB: Int = 0
    public var backgroundModes: [String] = []
    public var backgroundTaskIdentifiers: [String] = []
    public var userFriendlyDiagnosis: String = ""
    public var troubleshootingSteps: [String] = []
    
    public init() {}
    
    public var backgroundRefreshStatusDescription: String {
        switch backgroundRefreshStatus {
        case .available:
            return "Available"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown (\(backgroundRefreshStatus.rawValue))"
        }
    }
    
    public var applicationStateDescription: String {
        switch applicationState {
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        case .background:
            return "Background"
        @unknown default:
            return "Unknown (\(applicationState.rawValue))"
        }
    }
    
    public var summary: String {
        return """
        Background Monitoring Diagnostics:
        • Status: \(backgroundRefreshStatusDescription)
        • Supported: \(supportsBackgroundMonitoring ? "Yes" : "No")
        • Low Power Mode: \(isLowPowerModeEnabled ? "Enabled" : "Disabled")
        • Device: \(deviceModel) (iOS \(iOSVersion))
        • Environment: \(isSimulator ? "Simulator" : "Physical Device")
        • Memory: \(usedMemoryMB)MB used, \(availableMemoryMB)MB available
        """
    }
}