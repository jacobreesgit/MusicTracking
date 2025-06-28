import Foundation
import MusicKit
import Observation

@Observable
public final class AuthorizationService {
    
    public private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    public private(set) var isAuthorized: Bool = false
    public private(set) var lastAuthorizationCheck: Date?
    public private(set) var authorizationError: AppError?
    public private(set) var isInitialCheckComplete: Bool = false
    
    private var authorizationObservationTask: Task<Void, Never>?
    private var initializationTask: Task<Void, Never>?
    
    public init() {
        // Don't start automatic checking immediately - wait for explicit initialization
        print("AuthorizationService initialized - waiting for explicit start")
    }
    
    deinit {
        authorizationObservationTask?.cancel()
        initializationTask?.cancel()
    }
    
    @MainActor
    public func requestAuthorization() async throws {
        authorizationError = nil
        print("Requesting MusicKit authorization...")
        
        // Mark that we've attempted authorization at least once
        UserDefaults.standard.set(true, forKey: "HasAttemptedMusicKitAuthorization")
        
        do {
            let status = await MusicAuthorization.request()
            print("MusicKit authorization result: \(status)")
            
            // Wait for the authorization dialog to fully complete
            try await Task.sleep(for: .milliseconds(500))
            
            // Re-check the actual current status after dialog completion
            let currentStatus = MusicAuthorization.currentStatus
            await updateAuthorizationStatus(currentStatus)
            
            print("Final authorization status after dialog: \(currentStatus), isAuthorized: \(isAuthorized)")
            
            switch currentStatus {
            case .authorized:
                UserDefaults.standard.set(true, forKey: "MusicKitAuthorizationGranted")
                NotificationCenter.default.post(name: .musicKitAuthorizationChanged, object: true)
                print("✓ MusicKit authorization successful")
            case .denied:
                UserDefaults.standard.set(false, forKey: "MusicKitAuthorizationGranted")
                let error = AppError.musicKitPermissionDenied
                authorizationError = error
                NotificationCenter.default.post(name: .musicKitAuthorizationChanged, object: false)
                print("❌ MusicKit authorization denied")
                throw error
            case .notDetermined:
                let error = AppError.musicKitNotAuthorized
                authorizationError = error
                print("❌ MusicKit authorization not determined")
                throw error
            case .restricted:
                let error = AppError.musicKitNotAvailable
                authorizationError = error
                print("❌ MusicKit authorization restricted")
                throw error
            @unknown default:
                let error = AppError.musicKitUnknownError(
                    NSError(domain: "AuthorizationService", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Unknown authorization status: \(currentStatus)"
                    ])
                )
                authorizationError = error
                print("❌ MusicKit authorization unknown status: \(currentStatus)")
                throw error
            }
        } catch let error as AppError {
            authorizationError = error
            throw error
        } catch {
            let appError = AppError.from(musicKitError: error)
            authorizationError = appError
            print("❌ MusicKit authorization error: \(appError)")
            throw appError
        }
    }
    
    @MainActor
    public func checkCurrentStatus() async {
        let status = MusicAuthorization.currentStatus
        await updateAuthorizationStatus(status)
        lastAuthorizationCheck = Date()
        isInitialCheckComplete = true
        print("Authorization status checked: \(status), isAuthorized: \(isAuthorized)")
    }
    
    @MainActor
    private func updateAuthorizationStatus(_ status: MusicAuthorization.Status) async {
        authorizationStatus = status
        isAuthorized = status == .authorized
        
        if status == .authorized {
            authorizationError = nil
        }
    }
    
    public func requiresReauthorization() -> Bool {
        guard let lastCheck = lastAuthorizationCheck else { return true }
        
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        return lastCheck < sixMonthsAgo
    }
    
    @MainActor
    public func refreshAuthorizationIfNeeded() async throws {
        // Always check current status first, especially for production installs
        await checkCurrentStatus()
        
        // Wait a brief moment for authorization status to settle in production
        try await Task.sleep(for: .milliseconds(200))
        
        // Re-check after delay to handle production timing issues
        await checkCurrentStatus()
        
        if requiresReauthorization() || !isAuthorized {
            try await requestAuthorization()
        }
    }
    
    public func getAuthorizationStatusDescription() -> String {
        switch authorizationStatus {
        case .notDetermined:
            return "Authorization not requested"
        case .denied:
            return "Authorization denied"
        case .restricted:
            return "Authorization restricted"
        case .authorized:
            return "Authorized"
        @unknown default:
            return "Unknown authorization status"
        }
    }
    
    public func canRequestAuthorization() -> Bool {
        switch authorizationStatus {
        case .notDetermined:
            return true
        case .denied:
            // Allow retry for denied status in case user wants to change their mind
            return true
        case .restricted:
            return false
        case .authorized:
            return requiresReauthorization()
        @unknown default:
            return false
        }
    }
    
    public func isFirstTimeUser() -> Bool {
        return !UserDefaults.standard.bool(forKey: "HasAttemptedMusicKitAuthorization")
    }
    
    public func hasBeenPreviouslyAuthorized() -> Bool {
        return UserDefaults.standard.bool(forKey: "MusicKitAuthorizationGranted")
    }
    
    @MainActor
    public func startInitialization() async {
        guard initializationTask == nil else { return }
        
        initializationTask = Task {
            // Perform initial status check
            await checkCurrentStatus()
            
            // Wait for authorization to settle, especially important for production installs
            try? await Task.sleep(for: .milliseconds(500))
            
            // Check again after delay
            await checkCurrentStatus()
            
            // Start periodic observation only after initial check is complete
            await startAuthorizationObservation()
        }
        
        await initializationTask?.value
    }
    
    @MainActor
    public func waitForInitialCheck() async {
        while !isInitialCheckComplete {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
    
    private func startAuthorizationObservation() async {
        // Only start observation if not already running
        guard authorizationObservationTask == nil else { return }
        
        authorizationObservationTask = Task {
            // Wait before starting periodic checks to avoid interference
            try? await Task.sleep(for: .seconds(5))
            
            while !Task.isCancelled {
                _ = await MainActor.run {
                    Task {
                        await checkCurrentStatus()
                    }
                }
                
                // Use longer intervals to reduce interference
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
    
    @MainActor
    public func handleAuthorizationError(_ error: Error) {
        if let appError = error as? AppError {
            authorizationError = appError
        } else {
            authorizationError = AppError.from(musicKitError: error)
        }
        
        isAuthorized = false
        authorizationStatus = .denied
    }
    
    @MainActor
    public func clearAuthorizationError() {
        authorizationError = nil
    }
    
    public func getDetailedAuthorizationInfo() -> AuthorizationInfo {
        return AuthorizationInfo(
            status: authorizationStatus,
            isAuthorized: isAuthorized,
            lastCheck: lastAuthorizationCheck,
            requiresReauthorization: requiresReauthorization(),
            canRequest: canRequestAuthorization(),
            error: authorizationError,
            description: getAuthorizationStatusDescription()
        )
    }
}

public struct AuthorizationInfo {
    public let status: MusicAuthorization.Status
    public let isAuthorized: Bool
    public let lastCheck: Date?
    public let requiresReauthorization: Bool
    public let canRequest: Bool
    public let error: AppError?
    public let description: String
    
    public var isHealthy: Bool {
        return isAuthorized && !requiresReauthorization && error == nil
    }
    
    public var needsUserAction: Bool {
        return !isAuthorized || requiresReauthorization || (error?.requiresUserAction == true)
    }
}