import Foundation
import MusicKit

public enum AppError: LocalizedError, Equatable {
    case musicKitNotAuthorized
    case musicKitPermissionDenied
    case musicKitNotAvailable
    case musicKitTokenExpired
    case musicKitTokenRefreshFailed
    case musicKitRequestFailed(String)
    case musicKitNetworkError(Error)
    case musicKitUnknownError(Error)
    
    case coreDataSaveFailed(Error)
    case coreDataFetchFailed(Error)
    case coreDataContextNotFound
    case coreDataModelNotFound
    
    case backgroundTaskFailed(String)
    case backgroundTaskFailedWithDiagnostics([String: Any])
    case backgroundTaskExpired
    
    case invalidData(String)
    case missingData(String)
    case parsingError(String)
    
    case networkNotAvailable
    case networkUnavailable
    case requestTimeout
    case serverError(Int, String?)
    
    case cloudKitSyncFailed(String)
    case cloudKitNotAvailable
    
    public var errorDescription: String? {
        switch self {
        case .musicKitNotAuthorized:
            return "Apple Music access is not authorized. Please grant permission in Settings."
        case .musicKitPermissionDenied:
            return "Apple Music permission was denied. Enable access in Settings to track your listening history."
        case .musicKitNotAvailable:
            return "Apple Music is not available on this device or in this region."
        case .musicKitTokenExpired:
            return "Apple Music authorization has expired. Please re-authorize the app."
        case .musicKitTokenRefreshFailed:
            return "Failed to refresh Apple Music authorization. Please re-authorize the app."
        case .musicKitRequestFailed(let message):
            return "Apple Music request failed: \(message)"
        case .musicKitNetworkError(let error):
            return "Network error while accessing Apple Music: \(error.localizedDescription)"
        case .musicKitUnknownError(let error):
            return "Unexpected Apple Music error: \(error.localizedDescription)"
            
        case .coreDataSaveFailed(let error):
            return "Failed to save data: \(error.localizedDescription)"
        case .coreDataFetchFailed(let error):
            return "Failed to load data: \(error.localizedDescription)"
        case .coreDataContextNotFound:
            return "Database context is not available."
        case .coreDataModelNotFound:
            return "Database model could not be loaded."
            
        case .backgroundTaskFailed(let message):
            return "Background task failed: \(message)"
        case .backgroundTaskFailedWithDiagnostics(let userInfo):
            if let diagnosis = userInfo["diagnosis"] as? String {
                return diagnosis
            } else {
                return "Background monitoring is not available on this device."
            }
        case .backgroundTaskExpired:
            return "Background task expired before completion."
            
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .missingData(let message):
            return "Missing required data: \(message)"
        case .parsingError(let message):
            return "Failed to parse data: \(message)"
            
        case .networkNotAvailable:
            return "Network connection is not available."
        case .networkUnavailable:
            return "Network is currently unavailable."
        case .requestTimeout:
            return "Request timed out. Please try again."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
            
        case .cloudKitSyncFailed(let message):
            return "CloudKit sync failed: \(message)"
        case .cloudKitNotAvailable:
            return "CloudKit is not available."
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .musicKitNotAuthorized, .musicKitPermissionDenied:
            return "The app needs Apple Music permission to track your listening history."
        case .musicKitNotAvailable:
            return "Apple Music service is not accessible."
        case .musicKitTokenExpired, .musicKitTokenRefreshFailed:
            return "Apple Music authorization needs to be renewed."
        case .musicKitRequestFailed, .musicKitNetworkError, .musicKitUnknownError:
            return "Communication with Apple Music failed."
            
        case .coreDataSaveFailed, .coreDataFetchFailed:
            return "Local database operation failed."
        case .coreDataContextNotFound, .coreDataModelNotFound:
            return "Database is not properly configured."
            
        case .backgroundTaskFailed, .backgroundTaskFailedWithDiagnostics, .backgroundTaskExpired:
            return "Background processing encountered an issue."
            
        case .invalidData, .missingData, .parsingError:
            return "Data processing failed."
            
        case .networkNotAvailable, .networkUnavailable, .requestTimeout, .serverError:
            return "Network communication failed."
            
        case .cloudKitSyncFailed, .cloudKitNotAvailable:
            return "iCloud synchronization failed."
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .musicKitNotAuthorized, .musicKitPermissionDenied:
            return "Go to Settings > Privacy & Security > Media & Apple Music to enable access for this app."
        case .musicKitNotAvailable:
            return "Ensure you have an active Apple Music subscription and your device supports Apple Music."
        case .musicKitTokenExpired, .musicKitTokenRefreshFailed:
            return "Try logging out and back into Apple Music, or restart the app."
        case .musicKitNetworkError, .networkNotAvailable, .networkUnavailable, .requestTimeout:
            return "Check your internet connection and try again."
        case .musicKitRequestFailed, .musicKitUnknownError:
            return "Try again later or restart the app."
            
        case .coreDataSaveFailed, .coreDataFetchFailed:
            return "Restart the app or free up device storage."
        case .coreDataContextNotFound, .coreDataModelNotFound:
            return "Reinstall the app to fix database issues."
            
        case .backgroundTaskFailed, .backgroundTaskExpired:
            return "The app will retry the operation when possible."
        case .backgroundTaskFailedWithDiagnostics(let userInfo):
            if let troubleshootingSteps = userInfo["troubleshootingSteps"] as? [String], !troubleshootingSteps.isEmpty {
                return troubleshootingSteps.joined(separator: "\n• ")
            } else {
                return "Check Settings > General > Background App Refresh and ensure it's enabled for this app."
            }
            
        case .invalidData, .missingData, .parsingError:
            return "This may be a temporary issue. Try again later."
            
        case .serverError:
            return "This is likely a temporary server issue. Try again later."
            
        case .cloudKitSyncFailed, .cloudKitNotAvailable:
            return "Check your iCloud settings and internet connection. Make sure you're signed into iCloud."
        }
    }
    
    public var isRetryable: Bool {
        switch self {
        case .musicKitNetworkError, .musicKitRequestFailed, .networkNotAvailable, .networkUnavailable, .requestTimeout, .serverError:
            return true
        case .cloudKitSyncFailed, .cloudKitNotAvailable:
            return true
        case .backgroundTaskExpired, .backgroundTaskFailed, .backgroundTaskFailedWithDiagnostics:
            return true
        case .coreDataSaveFailed, .coreDataFetchFailed:
            return true
        default:
            return false
        }
    }
    
    public var requiresUserAction: Bool {
        switch self {
        case .musicKitNotAuthorized, .musicKitPermissionDenied, .musicKitTokenExpired, .musicKitTokenRefreshFailed:
            return true
        case .musicKitNotAvailable:
            return true
        case .coreDataModelNotFound, .coreDataContextNotFound:
            return true
        default:
            return false
        }
    }
    
    public static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.musicKitNotAuthorized, .musicKitNotAuthorized),
             (.musicKitPermissionDenied, .musicKitPermissionDenied),
             (.musicKitNotAvailable, .musicKitNotAvailable),
             (.musicKitTokenExpired, .musicKitTokenExpired),
             (.musicKitTokenRefreshFailed, .musicKitTokenRefreshFailed),
             (.coreDataContextNotFound, .coreDataContextNotFound),
             (.coreDataModelNotFound, .coreDataModelNotFound),
             (.backgroundTaskExpired, .backgroundTaskExpired),
             (.networkNotAvailable, .networkNotAvailable),
             (.networkUnavailable, .networkUnavailable),
             (.requestTimeout, .requestTimeout),
             (.cloudKitNotAvailable, .cloudKitNotAvailable):
            return true
        case (.musicKitRequestFailed(let lhsMessage), .musicKitRequestFailed(let rhsMessage)),
             (.backgroundTaskFailed(let lhsMessage), .backgroundTaskFailed(let rhsMessage)),
             (.invalidData(let lhsMessage), .invalidData(let rhsMessage)),
             (.missingData(let lhsMessage), .missingData(let rhsMessage)),
             (.parsingError(let lhsMessage), .parsingError(let rhsMessage)),
             (.cloudKitSyncFailed(let lhsMessage), .cloudKitSyncFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.serverError(let lhsCode, let lhsMessage), .serverError(let rhsCode, let rhsMessage)):
            return lhsCode == rhsCode && lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

extension AppError {
    public static func from(musicKitError error: Error) -> AppError {
        if error is URLError {
            return .musicKitNetworkError(error)
        } else {
            return .musicKitUnknownError(error)
        }
    }
}