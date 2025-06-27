import Foundation
import CoreData
import CloudKit
import Observation

@Observable
public final class PersistenceController {
    
    public static let shared = PersistenceController()
    
    public let container: NSPersistentCloudKitContainer
    public private(set) var isLoaded: Bool = false
    public private(set) var loadError: Error?
    public private(set) var lastSyncDate: Date?
    public private(set) var isSyncing: Bool = false
    
    private var syncObserver: NSObjectProtocol?
    
    public init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "MusicTracking")
        
        setupPersistentStore(inMemory: inMemory)
        setupNotificationObservers()
    }
    
    deinit {
        if let observer = syncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupPersistentStore(inMemory: Bool) {
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            configureCloudKitStore()
        }
        
        container.loadPersistentStores { [weak self] storeDescription, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.loadError = error
                    self?.isLoaded = false
                    print("Core Data error: \(error)")
                } else {
                    self?.isLoaded = true
                    self?.loadError = nil
                    print("Core Data loaded successfully")
                }
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            print("Failed to pin viewContext to current generation: \(error)")
        }
    }
    
    private func configureCloudKitStore() {
        guard let storeDescription = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description")
        }
        
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.jaba.MusicTracking"
        )
        
        storeDescription.cloudKitContainerOptions?.databaseScope = .private
    }
    
    private func setupNotificationObservers() {
        syncObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudKitEvent(notification)
        }
    }
    
    private func handleCloudKitEvent(_ notification: Notification) {
        guard let cloudEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }
        
        switch cloudEvent.type {
        case .setup:
            print("CloudKit setup event")
        case .import:
            isSyncing = true
            print("CloudKit import started")
        case .export:
            isSyncing = true
            print("CloudKit export started")
        @unknown default:
            print("Unknown CloudKit event: \(cloudEvent.type)")
        }
        
        if cloudEvent.endDate != nil {
            isSyncing = false
            lastSyncDate = cloudEvent.endDate
            
            if let error = cloudEvent.error {
                print("CloudKit sync error: \(error)")
            } else {
                print("CloudKit sync completed successfully")
            }
            
            NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: cloudEvent)
        }
    }
    
    public func save() throws {
        let context = container.viewContext
        
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            context.rollback()
            throw AppError.coreDataSaveFailed(error)
        }
    }
    
    public func saveInBackground() async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            guard context.hasChanges else { return }
            
            do {
                try context.save()
            } catch {
                context.rollback()
                throw AppError.coreDataSaveFailed(error)
            }
        }
    }
    
    public func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = container.newBackgroundContext()
        
        return try await context.perform {
            do {
                let result = try block(context)
                
                if context.hasChanges {
                    try context.save()
                }
                
                return result
            } catch {
                context.rollback()
                throw error
            }
        }
    }
    
    public func fetch<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> [T] {
        do {
            return try container.viewContext.fetch(request)
        } catch {
            throw AppError.coreDataFetchFailed(error)
        }
    }
    
    public func count<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> Int {
        do {
            return try container.viewContext.count(for: request)
        } catch {
            throw AppError.coreDataFetchFailed(error)
        }
    }
    
    public func delete(_ object: NSManagedObject) throws {
        container.viewContext.delete(object)
        try save()
    }
    
    public func batchDelete<T: NSManagedObject>(_ fetchRequest: NSFetchRequest<T>) throws {
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest as! NSFetchRequest<NSFetchRequestResult>)
        deleteRequest.resultType = .resultTypeObjectIDs
        
        do {
            let result = try container.viewContext.execute(deleteRequest) as? NSBatchDeleteResult
            let objectIDArray = result?.result as? [NSManagedObjectID]
            let changes = [NSDeletedObjectsKey: objectIDArray ?? []]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [container.viewContext])
        } catch {
            throw AppError.coreDataSaveFailed(error)
        }
    }
    
    public func purgeAllData() async throws {
        try await performBackgroundTask { context in
            let listeningSessionRequest: NSFetchRequest<NSFetchRequestResult> = ListeningSessionEntity.fetchRequest()
            let weeklyStatsRequest: NSFetchRequest<NSFetchRequestResult> = WeeklyStatsEntity.fetchRequest()
            
            let listeningSessionDelete = NSBatchDeleteRequest(fetchRequest: listeningSessionRequest)
            let weeklyStatsDelete = NSBatchDeleteRequest(fetchRequest: weeklyStatsRequest)
            
            try context.execute(listeningSessionDelete)
            try context.execute(weeklyStatsDelete)
        }
    }
    
    public func getStorageInfo() async throws -> StorageInfo {
        return try await performBackgroundTask { context in
            let listeningSessionRequest: NSFetchRequest<ListeningSessionEntity> = ListeningSessionEntity.fetchRequest()
            let weeklyStatsRequest: NSFetchRequest<WeeklyStatsEntity> = WeeklyStatsEntity.fetchRequest()
            
            let totalSessions = try context.count(for: listeningSessionRequest)
            let totalWeeklyStats = try context.count(for: weeklyStatsRequest)
            
            listeningSessionRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ListeningSessionEntity.timestamp, ascending: true)]
            listeningSessionRequest.fetchLimit = 1
            let oldestSessions = try context.fetch(listeningSessionRequest)
            let oldestDate = oldestSessions.first?.timestamp
            
            listeningSessionRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ListeningSessionEntity.timestamp, ascending: false)]
            let newestSessions = try context.fetch(listeningSessionRequest)
            let newestDate = newestSessions.first?.timestamp
            
            let estimatedSize = Int64((totalSessions * 500) + (totalWeeklyStats * 1000))
            
            return StorageInfo(
                totalSessions: totalSessions,
                totalWeeklyStats: totalWeeklyStats,
                oldestSessionDate: oldestDate,
                newestSessionDate: newestDate,
                estimatedSizeInBytes: estimatedSize,
                databasePath: container.persistentStoreDescriptions.first?.url?.path
            )
        }
    }
    
    public func initializeCloudKitSchema() async throws {
        do {
            try await container.initializeCloudKitSchema(options: [])
            print("CloudKit schema initialized successfully")
        } catch {
            print("Failed to initialize CloudKit schema: \(error)")
            throw error
        }
    }
    
    public func getSyncStatus() -> CloudKitSyncStatus {
        return CloudKitSyncStatus(
            isLoaded: isLoaded,
            isSyncing: isSyncing,
            lastSyncDate: lastSyncDate,
            loadError: loadError
        )
    }
}

public struct CloudKitSyncStatus {
    public let isLoaded: Bool
    public let isSyncing: Bool
    public let lastSyncDate: Date?
    public let loadError: Error?
    
    public var isHealthy: Bool {
        return isLoaded && loadError == nil
    }
    
    public var statusDescription: String {
        if !isLoaded {
            return "Loading..."
        } else if isSyncing {
            return "Syncing..."
        } else if loadError != nil {
            return "Error"
        } else {
            return "Ready"
        }
    }
}

extension Notification.Name {
    public static let cloudKitSyncCompleted = Notification.Name("cloudKitSyncCompleted")
    public static let coreDataLoaded = Notification.Name("coreDataLoaded")
    public static let coreDataLoadFailed = Notification.Name("coreDataLoadFailed")
}