import Foundation
import BackgroundTasks
import Observation

@Observable
public final class BackgroundTaskManager {
    
    public static let shared = BackgroundTaskManager()
    
    public private(set) var isRegistered: Bool = false
    public private(set) var lastError: AppError?
    public private(set) var activeTaskCount: Int = 0
    public private(set) var taskHistory: [BackgroundTaskExecution] = []
    
    private let backgroundMusicMonitor: BackgroundMusicMonitor
    private let repository: MusicDataRepositoryProtocol
    
    private var registeredTaskIdentifiers: Set<String> = []
    
    public init(
        backgroundMusicMonitor: BackgroundMusicMonitor = .shared,
        repository: MusicDataRepositoryProtocol
    ) {
        self.backgroundMusicMonitor = backgroundMusicMonitor
        self.repository = repository
        
        print("BackgroundTaskManager initialized")
    }
    
    public func registerBackgroundTasks() {
        guard !isRegistered else {
            print("Background tasks already registered")
            return
        }
        
        registerMusicMonitoringTask()
        registerCleanupTask()
        registerStatsCalculationTask()
        
        isRegistered = true
        lastError = nil
        
        NotificationCenter.default.post(
            name: .backgroundTaskRegistered,
            object: nil,
            userInfo: [
                NotificationKeys.BackgroundTask.taskType: "all_tasks",
                NotificationKeys.BackgroundTask.isSuccessful: true
            ]
        )
        
        print("All background tasks registered successfully")
    }
    
    public func scheduleBackgroundTasks() {
        scheduleCleanupTask()
        scheduleStatsCalculationTask()
        print("Background tasks scheduled")
    }
    
    public func getTaskExecutionHistory() -> [BackgroundTaskExecution] {
        return taskHistory.sorted { $0.startTime > $1.startTime }
    }
    
    public func clearTaskHistory() {
        taskHistory.removeAll()
        print("Task execution history cleared")
    }
    
    private func registerMusicMonitoringTask() {
        let identifier = BackgroundTaskIdentifiers.musicMonitoring
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            self?.handleMusicMonitoringTask(task as! BGProcessingTask)
        }
        
        registeredTaskIdentifiers.insert(identifier)
        print("Registered music monitoring background task: \(identifier)")
    }
    
    private func registerCleanupTask() {
        let identifier = BackgroundTaskIdentifiers.cleanup
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            self?.handleCleanupTask(task as! BGProcessingTask)
        }
        
        registeredTaskIdentifiers.insert(identifier)
        print("Registered cleanup background task: \(identifier)")
    }
    
    private func registerStatsCalculationTask() {
        let identifier = BackgroundTaskIdentifiers.statsCalculation
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            self?.handleStatsCalculationTask(task as! BGProcessingTask)
        }
        
        registeredTaskIdentifiers.insert(identifier)
        print("Registered stats calculation background task: \(identifier)")
    }
    
    private func handleMusicMonitoringTask(_ task: BGProcessingTask) {
        let execution = BackgroundTaskExecution(
            taskType: .musicMonitoring,
            identifier: task.identifier,
            startTime: Date()
        )
        
        addTaskExecution(execution)
        incrementActiveTaskCount()
        
        NotificationCenter.default.post(
            name: .backgroundTaskStarted,
            object: nil,
            userInfo: [
                NotificationKeys.BackgroundTask.taskIdentifier: task.identifier,
                NotificationKeys.BackgroundTask.taskType: "music_monitoring"
            ]
        )
        
        print("Started music monitoring background task: \(task.identifier)")
        
        let monitoringOperation = Task {
            do {
                try await backgroundMusicMonitor.startMonitoring()
                
                await Task.sleep(nanoseconds: 25_000_000_000) // 25 seconds
                
                await backgroundMusicMonitor.stopMonitoring()
                
                await MainActor.run {
                    updateTaskExecution(execution, success: true, error: nil)
                    task.setTaskCompleted(success: true)
                }
                
            } catch {
                let appError = AppError.backgroundTaskFailed("Music monitoring task failed: \(error.localizedDescription)")
                
                await MainActor.run {
                    updateTaskExecution(execution, success: false, error: appError)
                    task.setTaskCompleted(success: false)
                }
            }
            
            await MainActor.run {
                decrementActiveTaskCount()
            }
        }
        
        task.expirationHandler = {
            monitoringOperation.cancel()
            
            Task { @MainActor in
                await self.backgroundMusicMonitor.stopMonitoring()
                self.updateTaskExecution(execution, success: false, error: AppError.backgroundTaskExpired)
                self.decrementActiveTaskCount()
            }
            
            task.setTaskCompleted(success: false)
            
            print("Music monitoring background task expired: \(task.identifier)")
        }
    }
    
    private func handleCleanupTask(_ task: BGProcessingTask) {
        let execution = BackgroundTaskExecution(
            taskType: .cleanup,
            identifier: task.identifier,
            startTime: Date()
        )
        
        addTaskExecution(execution)
        incrementActiveTaskCount()
        
        NotificationCenter.default.post(
            name: .backgroundTaskStarted,
            object: nil,
            userInfo: [
                NotificationKeys.BackgroundTask.taskIdentifier: task.identifier,
                NotificationKeys.BackgroundTask.taskType: "cleanup"
            ]
        )
        
        print("Started cleanup background task: \(task.identifier)")
        
        let cleanupOperation = Task {
            do {
                try await performCleanupOperations()
                
                await MainActor.run {
                    updateTaskExecution(execution, success: true, error: nil)
                    task.setTaskCompleted(success: true)
                }
                
            } catch {
                let appError = AppError.backgroundTaskFailed("Cleanup task failed: \(error.localizedDescription)")
                
                await MainActor.run {
                    updateTaskExecution(execution, success: false, error: appError)
                    task.setTaskCompleted(success: false)
                }
            }
            
            await MainActor.run {
                decrementActiveTaskCount()
            }
        }
        
        task.expirationHandler = {
            cleanupOperation.cancel()
            
            Task { @MainActor in
                self.updateTaskExecution(execution, success: false, error: AppError.backgroundTaskExpired)
                self.decrementActiveTaskCount()
            }
            
            task.setTaskCompleted(success: false)
            
            print("Cleanup background task expired: \(task.identifier)")
        }
        
        scheduleNextCleanupTask()
    }
    
    private func handleStatsCalculationTask(_ task: BGProcessingTask) {
        let execution = BackgroundTaskExecution(
            taskType: .statsCalculation,
            identifier: task.identifier,
            startTime: Date()
        )
        
        addTaskExecution(execution)
        incrementActiveTaskCount()
        
        NotificationCenter.default.post(
            name: .backgroundTaskStarted,
            object: nil,
            userInfo: [
                NotificationKeys.BackgroundTask.taskIdentifier: task.identifier,
                NotificationKeys.BackgroundTask.taskType: "stats_calculation"
            ]
        )
        
        print("Started stats calculation background task: \(task.identifier)")
        
        let statsOperation = Task {
            do {
                try await performStatsCalculation()
                
                await MainActor.run {
                    updateTaskExecution(execution, success: true, error: nil)
                    task.setTaskCompleted(success: true)
                }
                
            } catch {
                let appError = AppError.backgroundTaskFailed("Stats calculation task failed: \(error.localizedDescription)")
                
                await MainActor.run {
                    updateTaskExecution(execution, success: false, error: appError)
                    task.setTaskCompleted(success: false)
                }
            }
            
            await MainActor.run {
                decrementActiveTaskCount()
            }
        }
        
        task.expirationHandler = {
            statsOperation.cancel()
            
            Task { @MainActor in
                self.updateTaskExecution(execution, success: false, error: AppError.backgroundTaskExpired)
                self.decrementActiveTaskCount()
            }
            
            task.setTaskCompleted(success: false)
            
            print("Stats calculation background task expired: \(task.identifier)")
        }
        
        scheduleNextStatsCalculationTask()
    }
    
    private func performCleanupOperations() async throws {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        
        try await repository.deleteListeningSessions(olderThan: thirtyDaysAgo)
        
        let orphanedSongs = try await repository.fetchOrphanedSongs()
        for song in orphanedSongs {
            try await repository.deleteSong(song)
        }
        
        print("Cleanup operations completed successfully")
    }
    
    private func performStatsCalculation() async throws {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        
        let sessions = try await repository.fetchListeningSessions(from: startDate, to: endDate)
        
        for session in sessions {
            try await repository.updateSessionStatistics(session)
        }
        
        try await repository.calculateWeeklyStatistics(for: startDate...endDate)
        
        print("Stats calculation completed for \(sessions.count) sessions")
    }
    
    private func scheduleCleanupTask() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskIdentifiers.cleanup)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60) // 24 hours
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Cleanup task scheduled successfully")
        } catch {
            let appError = AppError.backgroundTaskFailed("Failed to schedule cleanup task: \(error.localizedDescription)")
            handleSchedulingError(appError)
        }
    }
    
    private func scheduleStatsCalculationTask() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskIdentifiers.statsCalculation)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60) // 6 hours
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Stats calculation task scheduled successfully")
        } catch {
            let appError = AppError.backgroundTaskFailed("Failed to schedule stats calculation task: \(error.localizedDescription)")
            handleSchedulingError(appError)
        }
    }
    
    private func scheduleNextCleanupTask() {
        scheduleCleanupTask()
    }
    
    private func scheduleNextStatsCalculationTask() {
        scheduleStatsCalculationTask()
    }
    
    private func addTaskExecution(_ execution: BackgroundTaskExecution) {
        taskHistory.append(execution)
        
        if taskHistory.count > 50 {
            taskHistory.removeFirst(taskHistory.count - 50)
        }
    }
    
    private func updateTaskExecution(
        _ execution: BackgroundTaskExecution,
        success: Bool,
        error: AppError?
    ) {
        if let index = taskHistory.firstIndex(where: { $0.id == execution.id }) {
            let updatedExecution = BackgroundTaskExecution(
                id: execution.id,
                taskType: execution.taskType,
                identifier: execution.identifier,
                startTime: execution.startTime,
                endTime: Date(),
                success: success,
                error: error
            )
            
            taskHistory[index] = updatedExecution
            
            NotificationCenter.default.post(
                name: .backgroundTaskCompleted,
                object: nil,
                userInfo: [
                    NotificationKeys.BackgroundTask.taskIdentifier: execution.identifier,
                    NotificationKeys.BackgroundTask.taskType: execution.taskType.rawValue,
                    NotificationKeys.BackgroundTask.isSuccessful: success,
                    NotificationKeys.BackgroundTask.error: error as Any
                ]
            )
        }
    }
    
    private func incrementActiveTaskCount() {
        activeTaskCount += 1
    }
    
    private func decrementActiveTaskCount() {
        activeTaskCount = max(0, activeTaskCount - 1)
    }
    
    private func handleSchedulingError(_ error: AppError) {
        lastError = error
        print("Background task scheduling error: \(error.localizedDescription)")
    }
}

public struct BackgroundTaskIdentifiers {
    public static let musicMonitoring = "jaba.MusicTracking.monitoring"
    public static let cleanup = "jaba.MusicTracking.cleanup"
    public static let statsCalculation = "jaba.MusicTracking.stats"
}

public struct BackgroundTaskExecution {
    public let id: UUID
    public let taskType: BackgroundTaskType
    public let identifier: String
    public let startTime: Date
    public let endTime: Date?
    public let success: Bool?
    public let error: AppError?
    
    public init(
        id: UUID = UUID(),
        taskType: BackgroundTaskType,
        identifier: String,
        startTime: Date,
        endTime: Date? = nil,
        success: Bool? = nil,
        error: AppError? = nil
    ) {
        self.id = id
        self.taskType = taskType
        self.identifier = identifier
        self.startTime = startTime
        self.endTime = endTime
        self.success = success
        self.error = error
    }
    
    public var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    public var status: String {
        if let success = success {
            return success ? "Completed" : "Failed"
        } else {
            return "Running"
        }
    }
    
    public var statusDescription: String {
        if let error = error {
            return "Failed: \(error.localizedDescription)"
        } else if let success = success {
            if let duration = duration {
                return success ? "Completed in \(duration.formattedDurationShort)" : "Failed"
            } else {
                return success ? "Completed" : "Failed"
            }
        } else {
            let runningTime = Date().timeIntervalSince(startTime)
            return "Running for \(runningTime.formattedDurationShort)"
        }
    }
}

public enum BackgroundTaskType: String, CaseIterable {
    case musicMonitoring = "music_monitoring"
    case cleanup = "cleanup"
    case statsCalculation = "stats_calculation"
    
    public var displayName: String {
        switch self {
        case .musicMonitoring:
            return "Music Monitoring"
        case .cleanup:
            return "Data Cleanup"
        case .statsCalculation:
            return "Statistics Calculation"
        }
    }
    
    public var description: String {
        switch self {
        case .musicMonitoring:
            return "Tracks music playback in the background"
        case .cleanup:
            return "Removes old data and optimizes storage"
        case .statsCalculation:
            return "Calculates listening statistics and trends"
        }
    }
}