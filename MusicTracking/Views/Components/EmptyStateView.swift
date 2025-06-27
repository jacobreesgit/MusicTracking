import SwiftUI

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    public init(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


public struct ErrorStateView: View {
    let error: AppError
    let retryAction: (() -> Void)?
    
    public init(error: AppError, retryAction: (() -> Void)? = nil) {
        self.error = error
        self.retryAction = retryAction
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: errorIcon)
                    .font(.system(size: 60))
                    .foregroundColor(errorColor)
                
                VStack(spacing: 8) {
                    Text(errorTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(error.localizedDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            
            VStack(spacing: 12) {
                if error.isRetryable, let retryAction = retryAction {
                    Button(action: retryAction) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Try Again")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                }
                
                if error.requiresUserAction {
                    Button(action: openSettings) {
                        HStack(spacing: 8) {
                            Image(systemName: "gear")
                            Text("Open Settings")
                        }
                        .font(.callout)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var errorIcon: String {
        switch error {
        case .musicKitNotAuthorized, .musicKitPermissionDenied:
            return "music.note.list"
        case .cloudKitSyncFailed, .cloudKitNotAvailable:
            return "icloud.slash"
        case .networkUnavailable:
            return "wifi.slash"
        case .backgroundTaskFailed, .backgroundTaskExpired:
            return "exclamationmark.triangle"
        default:
            return "exclamationmark.circle"
        }
    }
    
    private var errorColor: Color {
        switch error {
        case .musicKitNotAuthorized, .musicKitPermissionDenied:
            return .orange
        case .cloudKitSyncFailed, .cloudKitNotAvailable:
            return .blue
        case .networkUnavailable:
            return .gray
        case .backgroundTaskFailed, .backgroundTaskExpired:
            return .red
        default:
            return .red
        }
    }
    
    private var errorTitle: String {
        switch error {
        case .musicKitNotAuthorized, .musicKitPermissionDenied:
            return "Music Access Required"
        case .cloudKitSyncFailed, .cloudKitNotAvailable:
            return "Sync Issue"
        case .networkUnavailable:
            return "No Internet Connection"
        case .backgroundTaskFailed, .backgroundTaskExpired:
            return "Background Task Failed"
        default:
            return "Something Went Wrong"
        }
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

public struct NoDataView: View {
    let icon: String
    let title: String
    let subtitle: String
    let suggestions: [String]
    let actionTitle: String?
    let action: (() -> Void)?
    
    public init(
        icon: String,
        title: String,
        subtitle: String,
        suggestions: [String] = [],
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.suggestions = suggestions
        self.actionTitle = actionTitle
        self.action = action
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Try this:")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(.blue)
                                    .fontWeight(.bold)
                                
                                Text(suggestion)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct SearchEmptyView: View {
    let searchTerm: String
    let onClearSearch: () -> Void
    
    public init(searchTerm: String, onClearSearch: @escaping () -> Void) {
        self.searchTerm = searchTerm
        self.onClearSearch = onClearSearch
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    Text("No Results")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("No results found for \"\(searchTerm)\"")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Search suggestions:")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                VStack(alignment: .leading, spacing: 8) {
                    SuggestionRow(text: "Check your spelling")
                    SuggestionRow(text: "Try broader search terms")
                    SuggestionRow(text: "Search for artist or song names")
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            
            Button(action: onClearSearch) {
                Text("Clear Search")
                    .font(.callout)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SuggestionRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.blue)
                .fontWeight(.bold)
            
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Specialized Empty States

public struct MusicEmptyStateView: View {
    let onRefresh: () -> Void
    
    public init(onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh
    }
    
    public var body: some View {
        NoDataView(
            icon: "music.note.house",
            title: "No Music Data",
            subtitle: "Start listening to music to see your stats here",
            suggestions: [
                "Open Apple Music and play some songs",
                "Make sure background monitoring is enabled",
                "Check your Apple Music permissions"
            ],
            actionTitle: "Refresh",
            action: onRefresh
        )
    }
}

public struct WeeklyEmptyStateView: View {
    let onRefresh: () -> Void
    
    public init(onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh
    }
    
    public var body: some View {
        NoDataView(
            icon: "calendar",
            title: "No Weekly Data",
            subtitle: "Listen to music throughout the week to see your weekly stats",
            suggestions: [
                "Play music regularly throughout the week",
                "Let the app track in the background",
                "Weekly stats generate automatically"
            ],
            actionTitle: "Refresh",
            action: onRefresh
        )
    }
}

public struct TopSongsEmptyStateView: View {
    let timeframe: String
    let onRefresh: () -> Void
    
    public init(timeframe: String, onRefresh: @escaping () -> Void) {
        self.timeframe = timeframe
        self.onRefresh = onRefresh
    }
    
    public var body: some View {
        NoDataView(
            icon: "music.note.list",
            title: "No Top Songs",
            subtitle: "No songs played during \(timeframe.lowercased())",
            suggestions: [
                "Start listening to build your top songs list",
                "Play songs completely for better tracking",
                "Check back after listening to more music"
            ],
            actionTitle: "Refresh",
            action: onRefresh
        )
    }
}

#Preview("Empty State") {
    EmptyStateView(
        icon: "music.note.list",
        title: "No Music Data",
        subtitle: "Start listening to music to see your stats here",
        actionTitle: "Get Started",
        action: { print("Action tapped") }
    )
}

#Preview("Loading View") {
    LoadingView(message: "Loading your music data...")
}

#Preview("Error State") {
    ErrorStateView(
        error: AppError.musicKitNotAuthorized,
        retryAction: { print("Retry tapped") }
    )
}

#Preview("No Data View") {
    NoDataView(
        icon: "music.note.house",
        title: "No Music Data",
        subtitle: "Start listening to music to see your stats here",
        suggestions: [
            "Open Apple Music and play some songs",
            "Make sure background monitoring is enabled",
            "Check your Apple Music permissions"
        ],
        actionTitle: "Refresh",
        action: { print("Refresh tapped") }
    )
}

#Preview("Search Empty") {
    SearchEmptyView(
        searchTerm: "Unknown Artist",
        onClearSearch: { print("Clear search tapped") }
    )
}