import Foundation
import CloudKit
import CoreData
import Observation

@Observable
public final class CloudKitSyncService {
    
    public private(set) var syncStatus: CloudKitSyncStatus = .idle
    public private(set) var lastSyncDate: Date?
    public private(set) var syncError: AppError?
    public private(set) var conflictCount: Int = 0
    public private(set) var isManualSyncInProgress: Bool = false
    
    private let container: CKContainer
    private let database: CKDatabase
    private let persistenceController: PersistenceController
    private var syncObserver: NSObjectProtocol?
    
    public init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.container = CKContainer(identifier: "iCloud.jaba.MusicTracking")
        self.database = container.privateCloudDatabase
        
        setupSyncObserver()
    }
    
    deinit {
        if let observer = syncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupSyncObserver() {
        syncObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitSyncCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSyncEvent(notification)
        }
    }
    
    private func handleSyncEvent(_ notification: Notification) {
        guard let event = notification.object as? NSPersistentCloudKitContainer.Event else {
            return
        }
        
        lastSyncDate = event.endDate ?? Date()
        
        if let error = event.error {
            syncError = AppError.from(musicKitError: error)
            syncStatus = .failed
        } else {
            syncError = nil
            syncStatus = .completed
        }
        
        isManualSyncInProgress = false
        
        NotificationCenter.default.post(name: .cloudKitSyncStatusChanged, object: syncStatus)
    }
    
    @MainActor
    public func triggerManualSync() async throws {
        guard !isManualSyncInProgress else {
            throw AppError.backgroundTaskFailed("Sync already in progress")
        }
        
        isManualSyncInProgress = true
        syncStatus = .syncing
        syncError = nil
        
        do {
            try await performManualSync()
        } catch {
            syncError = error as? AppError ?? AppError.from(musicKitError: error)
            syncStatus = .failed
            isManualSyncInProgress = false
            throw syncError!
        }
    }
    
    private func performManualSync() async throws {
        try await persistenceController.performBackgroundTask { context in
            try context.save()
        }
        
        try await checkAccountStatus()
        try await resolveConflicts()
    }
    
    private func checkAccountStatus() async throws {
        let accountStatus = try await container.accountStatus()
        
        switch accountStatus {
        case .available:
            break
        case .noAccount:
            throw AppError.missingData("iCloud account not signed in")
        case .restricted:
            throw AppError.musicKitNotAvailable
        case .couldNotDetermine:
            throw AppError.networkNotAvailable
        case .temporarilyUnavailable:
            throw AppError.serverError(503, "iCloud temporarily unavailable")
        @unknown default:
            throw AppError.musicKitUnknownError(NSError(domain: "CloudKitSyncService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown account status"]))
        }
    }
    
    private func resolveConflicts() async throws {
        conflictCount = 0
        
        try await persistenceController.performBackgroundTask { [weak self] context in
            let listeningSessionRequest: NSFetchRequest<ListeningSessionEntity> = ListeningSessionEntity.fetchRequest()
            let weeklyStatsRequest: NSFetchRequest<WeeklyStatsEntity> = WeeklyStatsEntity.fetchRequest()
            
            let listeningSessions = try context.fetch(listeningSessionRequest)
            let weeklyStats = try context.fetch(weeklyStatsRequest)
            
            self?.resolveListeningSessionConflicts(listeningSessions, in: context)
            self?.resolveWeeklyStatsConflicts(weeklyStats, in: context)
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func resolveListeningSessionConflicts(_ sessions: [ListeningSessionEntity], in context: NSManagedObjectContext) {
        let groupedSessions = Dictionary(grouping: sessions) { session in
            "\(session.songID)-\(session.timestamp.timeIntervalSince1970)"
        }
        
        for (_, duplicates) in groupedSessions where duplicates.count > 1 {
            let sortedDuplicates = duplicates.sorted { $0.updatedAt > $1.updatedAt }
            let keepSession = sortedDuplicates.first!
            
            for duplicate in sortedDuplicates.dropFirst() {
                context.delete(duplicate)
                conflictCount += 1
            }
            
            if duplicates.allSatisfy({ $0.isComplete }) {
                keepSession.isComplete = true
            }
            
            keepSession.playCount = duplicates.map { Int($0.playCount) }.max() ?? 1
        }
    }
    
    private func resolveWeeklyStatsConflicts(_ stats: [WeeklyStatsEntity], in context: NSManagedObjectContext) {
        let groupedStats = Dictionary(grouping: stats) { stat in
            Calendar.current.dateInterval(of: .weekOfYear, for: stat.weekStartDate)?.start ?? stat.weekStartDate
        }
        
        for (weekStart, duplicates) in groupedStats where duplicates.count > 1 {
            let sortedDuplicates = duplicates.sorted { $0.updatedAt > $1.updatedAt }
            let keepStats = sortedDuplicates.first!
            
            var mergedTopSongs: [TopSongData] = []
            var mergedTopArtists: [TopArtistData] = []
            var totalPlayTime: Double = 0
            var uniqueSongs: Set<String> = []
            
            for duplicate in duplicates {
                totalPlayTime = max(totalPlayTime, duplicate.totalPlayTime)
                mergedTopSongs.append(contentsOf: duplicate.topSongs)
                mergedTopArtists.append(contentsOf: duplicate.topArtists)
                
                for song in duplicate.topSongs {
                    uniqueSongs.insert(song.songID)
                }
            }
            
            keepStats.totalPlayTime = totalPlayTime
            keepStats.uniqueSongsCount = Int32(uniqueSongs.count)
            keepStats.topSongs = Array(mergedTopSongs.prefix(10))
            keepStats.topArtists = Array(mergedTopArtists.prefix(10))
            
            for duplicate in sortedDuplicates.dropFirst() {
                context.delete(duplicate)
                conflictCount += 1
            }
        }
    }
    
    public func getSyncInfo() -> SyncInfo {
        return SyncInfo(
            status: syncStatus,
            lastSyncDate: lastSyncDate,
            error: syncError,
            conflictCount: conflictCount,
            isManualSyncInProgress: isManualSyncInProgress
        )
    }
    
    @MainActor
    public func resetSyncStatus() {
        syncStatus = .idle
        syncError = nil
        conflictCount = 0
        isManualSyncInProgress = false
    }
    
    public func validateCloudKitAvailability() async throws {
        try await checkAccountStatus()
        
        do {
            let _ = try await database.recordType(for: "CD_ListeningSession")
        } catch {
            throw AppError.musicKitRequestFailed("CloudKit schema not found. Please ensure the app has been launched and synced at least once.")
        }
    }
    
    @MainActor
    public func handleCloudKitError(_ error: Error) {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkFailure, .networkUnavailable:
                syncError = AppError.networkNotAvailable
            case .quotaExceeded:
                syncError = AppError.serverError(507, "iCloud storage quota exceeded")
            case .accountTemporarilyUnavailable:
                syncError = AppError.serverError(503, "iCloud account temporarily unavailable")
            case .notAuthenticated:
                syncError = AppError.musicKitNotAuthorized
            default:
                syncError = AppError.from(musicKitError: error)
            }
        } else {
            syncError = AppError.from(musicKitError: error)
        }
        
        syncStatus = .failed
    }
}

public enum CloudKitSyncStatus: String, CaseIterable {
    case idle = "idle"
    case syncing = "syncing"
    case completed = "completed"
    case failed = "failed"
    
    public var displayName: String {
        switch self {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .completed:
            return "Synced"
        case .failed:
            return "Sync Failed"
        }
    }
    
    public var isActive: Bool {
        return self == .syncing
    }
    
    public var requiresAttention: Bool {
        return self == .failed
    }
}

public struct SyncInfo {
    public let status: CloudKitSyncStatus
    public let lastSyncDate: Date?
    public let error: AppError?
    public let conflictCount: Int
    public let isManualSyncInProgress: Bool
    
    public var isHealthy: Bool {
        return status != .failed && error == nil
    }
    
    public var timeSinceLastSync: TimeInterval? {
        guard let lastSyncDate = lastSyncDate else { return nil }
        return Date().timeIntervalSince(lastSyncDate)
    }
    
    public var formattedLastSync: String {
        guard let lastSyncDate = lastSyncDate else { return "Never" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSyncDate, relativeTo: Date())
    }
    
    public var needsSync: Bool {
        guard let timeSince = timeSinceLastSync else { return true }
        return timeSince > 3600 // More than 1 hour
    }
}

extension Notification.Name {
    public static let cloudKitSyncStatusChanged = Notification.Name("cloudKitSyncStatusChanged")
    public static let cloudKitConflictsResolved = Notification.Name("cloudKitConflictsResolved")
}