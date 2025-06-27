import Foundation
import AVFoundation
import Observation

@Observable
public final class AudioSessionManager {
    
    public static let shared = AudioSessionManager()
    
    public private(set) var isConfigured: Bool = false
    public private(set) var isActive: Bool = false
    public private(set) var currentCategory: AVAudioSession.Category = .ambient
    public private(set) var currentOptions: AVAudioSession.CategoryOptions = []
    public private(set) var lastError: AppError?
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var notificationObservers: [NSObjectProtocol] = []
    
    private init() {
        setupNotificationObservers()
    }
    
    deinit {
        cleanupNotificationObservers()
    }
    
    public func configureForBackgroundMonitoring() throws {
        do {
            try audioSession.setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers, .allowAirPlay, .allowBluetoothA2DP]
            )
            
            currentCategory = .ambient
            currentOptions = [.mixWithOthers, .allowAirPlay, .allowBluetoothA2DP]
            isConfigured = true
            lastError = nil
            
            print("Audio session configured for background monitoring")
            
            NotificationCenter.default.post(
                name: .audioSessionActivated,
                object: nil,
                userInfo: [
                    NotificationKeys.AudioSession.category: currentCategory.rawValue,
                    NotificationKeys.AudioSession.options: currentOptions.rawValue,
                    NotificationKeys.AudioSession.isActive: isActive
                ]
            )
            
        } catch {
            let appError = AppError.backgroundTaskFailed("Failed to configure audio session: \(error.localizedDescription)")
            lastError = appError
            isConfigured = false
            throw appError
        }
    }
    
    public func activateSession() throws {
        guard isConfigured else {
            throw AppError.backgroundTaskFailed("Audio session not configured")
        }
        
        do {
            try audioSession.setActive(true)
            isActive = true
            lastError = nil
            
            print("Audio session activated")
            
            NotificationCenter.default.post(
                name: .audioSessionActivated,
                object: nil,
                userInfo: [NotificationKeys.AudioSession.isActive: true]
            )
            
        } catch {
            let appError = AppError.backgroundTaskFailed("Failed to activate audio session: \(error.localizedDescription)")
            lastError = appError
            isActive = false
            throw appError
        }
    }
    
    public func deactivateSession() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
            lastError = nil
            
            print("Audio session deactivated")
            
            NotificationCenter.default.post(
                name: .audioSessionDeactivated,
                object: nil,
                userInfo: [NotificationKeys.AudioSession.isActive: false]
            )
            
        } catch {
            let appError = AppError.backgroundTaskFailed("Failed to deactivate audio session: \(error.localizedDescription)")
            lastError = appError
            print("Audio session deactivation error: \(appError)")
        }
    }
    
    public func requestRecordPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    public func getAudioSessionInfo() -> AudioSessionInfo {
        return AudioSessionInfo(
            isConfigured: isConfigured,
            isActive: isActive,
            category: currentCategory,
            options: currentOptions,
            sampleRate: audioSession.sampleRate,
            inputNumberOfChannels: audioSession.inputNumberOfChannels,
            outputNumberOfChannels: audioSession.outputNumberOfChannels,
            lastError: lastError
        )
    }
    
    private func setupNotificationObservers() {
        let center = NotificationCenter.default
        
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleAudioSessionInterruption(notification)
            }
        )
        
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleAudioSessionRouteChange(notification)
            }
        )
        
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereLostNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleMediaServicesLost(notification)
            }
        )
        
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleMediaServicesReset(notification)
            }
        )
    }
    
    private func cleanupNotificationObservers() {
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
    
    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("Audio session interruption began")
            isActive = false
            
        case .ended:
            print("Audio session interruption ended")
            
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    do {
                        try activateSession()
                    } catch {
                        print("Failed to resume audio session after interruption: \(error)")
                    }
                }
            }
            
        @unknown default:
            print("Unknown audio session interruption type")
        }
        
        NotificationCenter.default.post(
            name: .audioSessionInterrupted,
            object: nil,
            userInfo: [NotificationKeys.AudioSession.interruptionType: type.rawValue]
        )
    }
    
    private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        print("Audio session route changed: \(reason)")
        
        NotificationCenter.default.post(
            name: .audioSessionRouteChanged,
            object: nil,
            userInfo: [NotificationKeys.AudioSession.routeChangeReason: reason.rawValue]
        )
    }
    
    private func handleMediaServicesLost(_ notification: Notification) {
        print("Media services were lost")
        isActive = false
        isConfigured = false
        lastError = AppError.backgroundTaskFailed("Media services were lost")
    }
    
    private func handleMediaServicesReset(_ notification: Notification) {
        print("Media services were reset")
        isActive = false
        isConfigured = false
        
        Task {
            do {
                try configureForBackgroundMonitoring()
                try activateSession()
            } catch {
                print("Failed to reconfigure audio session after reset: \(error)")
            }
        }
    }
}

public struct AudioSessionInfo {
    public let isConfigured: Bool
    public let isActive: Bool
    public let category: AVAudioSession.Category
    public let options: AVAudioSession.CategoryOptions
    public let sampleRate: Double
    public let inputNumberOfChannels: Int
    public let outputNumberOfChannels: Int
    public let lastError: AppError?
    
    public var isHealthy: Bool {
        return isConfigured && isActive && lastError == nil
    }
    
    public var statusDescription: String {
        if let error = lastError {
            return "Error: \(error.localizedDescription)"
        } else if !isConfigured {
            return "Not configured"
        } else if !isActive {
            return "Configured but inactive"
        } else {
            return "Active (\(category.rawValue))"
        }
    }
    
    public var detailedInfo: [String: Any] {
        return [
            "isConfigured": isConfigured,
            "isActive": isActive,
            "category": category.rawValue,
            "options": options.rawValue,
            "sampleRate": sampleRate,
            "inputChannels": inputNumberOfChannels,
            "outputChannels": outputNumberOfChannels,
            "error": lastError?.localizedDescription ?? "None"
        ]
    }
}