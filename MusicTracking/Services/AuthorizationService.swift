import Foundation
import MusicKit
import Observation

@Observable
public final class AuthorizationService {
    
    public private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    public private(set) var isAuthorized: Bool = false
    public private(set) var lastAuthorizationCheck: Date?
    public private(set) var authorizationError: AppError?
    
    private var authorizationObservationTask: Task<Void, Never>?
    
    public init() {
        Task {
            await checkCurrentStatus()
            await startAuthorizationObservation()
        }
    }
    
    deinit {
        authorizationObservationTask?.cancel()
    }
    
    @MainActor
    public func requestAuthorization() async throws {
        authorizationError = nil
        
        do {
            let status = await MusicAuthorization.request()
            await updateAuthorizationStatus(status)
            
            switch status {
            case .authorized:
                NotificationCenter.default.post(name: .musicKitAuthorizationChanged, object: true)
            case .denied:
                let error = AppError.musicKitPermissionDenied
                authorizationError = error
                NotificationCenter.default.post(name: .musicKitAuthorizationChanged, object: false)
                throw error
            case .notDetermined:
                let error = AppError.musicKitNotAuthorized
                authorizationError = error
                throw error
            case .restricted:
                let error = AppError.musicKitNotAvailable
                authorizationError = error
                throw error
            @unknown default:
                let error = AppError.musicKitUnknownError(
                    NSError(domain: "AuthorizationService", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Unknown authorization status: \(status)"
                    ])
                )
                authorizationError = error
                throw error
            }
        } catch let error as AppError {
            authorizationError = error
            throw error
        } catch {
            let appError = AppError.from(musicKitError: error)
            authorizationError = appError
            throw appError
        }
    }
    
    @MainActor
    public func checkCurrentStatus() async {
        let status = MusicAuthorization.currentStatus
        await updateAuthorizationStatus(status)
        lastAuthorizationCheck = Date()
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
        if requiresReauthorization() || !isAuthorized {
            try await requestAuthorization()
        } else {
            await checkCurrentStatus()
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
        case .denied, .restricted:
            return false
        case .authorized:
            return requiresReauthorization()
        @unknown default:
            return false
        }
    }
    
    private func startAuthorizationObservation() async {
        authorizationObservationTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    Task {
                        await checkCurrentStatus()
                    }
                }
                
                try? await Task.sleep(for: .seconds(30))
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