import Foundation
import MusicKit
import Observation

@Observable
public final class TokenManager {
    
    public private(set) var tokenExpiration: Date?
    public private(set) var isTokenValid: Bool = false
    public private(set) var lastRefreshAttempt: Date?
    public private(set) var refreshError: AppError?
    
    private let tokenValidityBuffer: TimeInterval = 7 * 24 * 60 * 60 // 7 days buffer
    private let maxRetryAttempts = 3
    private var refreshTask: Task<Void, Never>?
    
    public init() {
        Task {
            await checkTokenValidity()
            await schedulePeriodicCheck()
        }
    }
    
    deinit {
        refreshTask?.cancel()
    }
    
    @MainActor
    public func checkTokenValidity() async {
        let authStatus = MusicAuthorization.currentStatus
        
        if authStatus == .authorized {
            isTokenValid = true
            
            if let expiration = tokenExpiration {
                let bufferDate = expiration.addingTimeInterval(-tokenValidityBuffer)
                isTokenValid = Date() < bufferDate
            } else {
                setDefaultTokenExpiration()
            }
        } else {
            isTokenValid = false
            tokenExpiration = nil
        }
    }
    
    @MainActor
    public func refreshTokenIfNeeded() async throws {
        guard !isTokenValid || shouldRefreshProactively() else {
            return
        }
        
        try await refreshToken()
    }
    
    @MainActor
    public func refreshToken() async throws {
        refreshError = nil
        lastRefreshAttempt = Date()
        
        var retryCount = 0
        
        while retryCount < maxRetryAttempts {
            do {
                let status = await MusicAuthorization.request()
                
                switch status {
                case .authorized:
                    await updateTokenAfterRefresh()
                    NotificationCenter.default.post(name: .tokenRefreshSucceeded, object: nil)
                    return
                    
                case .denied:
                    let error = AppError.musicKitPermissionDenied
                    refreshError = error
                    throw error
                    
                case .notDetermined:
                    let error = AppError.musicKitNotAuthorized
                    refreshError = error
                    throw error
                    
                case .restricted:
                    let error = AppError.musicKitNotAvailable
                    refreshError = error
                    throw error
                    
                @unknown default:
                    let error = AppError.musicKitUnknownError(
                        NSError(domain: "TokenManager", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "Unknown authorization status during refresh"
                        ])
                    )
                    refreshError = error
                    throw error
                }
                
            } catch let error as AppError {
                refreshError = error
                
                if !error.isRetryable {
                    throw error
                }
                
            } catch {
                let appError = AppError.from(musicKitError: error)
                refreshError = appError
                
                if !appError.isRetryable {
                    throw appError
                }
            }
            
            retryCount += 1
            
            if retryCount < maxRetryAttempts {
                let backoffDelay = TimeInterval(retryCount * retryCount * 2)
                try? await Task.sleep(for: .seconds(backoffDelay))
            }
        }
        
        let finalError = AppError.musicKitTokenRefreshFailed
        refreshError = finalError
        NotificationCenter.default.post(name: .tokenRefreshFailed, object: finalError)
        throw finalError
    }
    
    @MainActor
    private func updateTokenAfterRefresh() async {
        setDefaultTokenExpiration()
        isTokenValid = true
        refreshError = nil
    }
    
    @MainActor
    private func setDefaultTokenExpiration() {
        tokenExpiration = Calendar.current.date(byAdding: .month, value: 6, to: Date())
    }
    
    private func shouldRefreshProactively() -> Bool {
        guard let expiration = tokenExpiration else { return true }
        
        let proactiveRefreshDate = expiration.addingTimeInterval(-tokenValidityBuffer)
        return Date() >= proactiveRefreshDate
    }
    
    public func getTimeUntilExpiration() -> TimeInterval? {
        guard let expiration = tokenExpiration else { return nil }
        return expiration.timeIntervalSinceNow
    }
    
    public func getTimeUntilProactiveRefresh() -> TimeInterval? {
        guard let expiration = tokenExpiration else { return nil }
        
        let proactiveRefreshDate = expiration.addingTimeInterval(-tokenValidityBuffer)
        return proactiveRefreshDate.timeIntervalSinceNow
    }
    
    public func getTokenStatus() -> TokenStatus {
        return TokenStatus(
            isValid: isTokenValid,
            expiration: tokenExpiration,
            timeUntilExpiration: getTimeUntilExpiration(),
            timeUntilProactiveRefresh: getTimeUntilProactiveRefresh(),
            shouldRefresh: shouldRefreshProactively(),
            lastRefreshAttempt: lastRefreshAttempt,
            refreshError: refreshError
        )
    }
    
    private func schedulePeriodicCheck() async {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600)) // 1 hour
                
                _ = await MainActor.run {
                    Task {
                        await checkTokenValidity()
                        
                        if shouldRefreshProactively() {
                            do {
                                try await refreshTokenIfNeeded()
                            } catch {
                                print("Periodic token refresh failed: \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    public func handleAuthorizationChange(isAuthorized: Bool) async {
        if isAuthorized {
            setDefaultTokenExpiration()
            isTokenValid = true
            refreshError = nil
        } else {
            isTokenValid = false
            tokenExpiration = nil
        }
    }
    
    @MainActor
    public func reset() async {
        isTokenValid = false
        tokenExpiration = nil
        refreshError = nil
        lastRefreshAttempt = nil
    }
}

public struct TokenStatus {
    public let isValid: Bool
    public let expiration: Date?
    public let timeUntilExpiration: TimeInterval?
    public let timeUntilProactiveRefresh: TimeInterval?
    public let shouldRefresh: Bool
    public let lastRefreshAttempt: Date?
    public let refreshError: AppError?
    
    public var isHealthy: Bool {
        return isValid && refreshError == nil && !shouldRefresh
    }
    
    public var formattedTimeUntilExpiration: String? {
        guard let timeInterval = timeUntilExpiration, timeInterval > 0 else { return nil }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        
        return formatter.string(from: timeInterval)
    }
    
    public var expirationDescription: String {
        if let expiration = expiration {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Expires: \(formatter.string(from: expiration))"
        } else {
            return "No expiration date"
        }
    }
}

extension Notification.Name {
    public static let tokenRefreshSucceeded = Notification.Name("tokenRefreshSucceeded")
    public static let tokenRefreshFailed = Notification.Name("tokenRefreshFailed")
    public static let tokenWillExpireSoon = Notification.Name("tokenWillExpireSoon")
}