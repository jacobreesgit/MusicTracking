import SwiftUI

public struct LoadingView: View {
    let message: String
    
    public init(message: String = "Loading...") {
        self.message = message
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

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
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

public struct ErrorStateView: View {
    let error: Error
    let retryAction: (() -> Void)?
    
    public init(error: Error, retryAction: (() -> Void)? = nil) {
        self.error = error
        self.retryAction = retryAction
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Something went wrong")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if let retryAction = retryAction {
                Button(action: retryAction) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

public struct PullToRefreshModifier: ViewModifier {
    let action: () async -> Void
    
    public func body(content: Content) -> some View {
        content
            .refreshable {
                await action()
            }
    }
}

extension View {
    public func pullToRefresh(action: @escaping () async -> Void) -> some View {
        modifier(PullToRefreshModifier(action: action))
    }
}

public struct LoadingRowView: View {
    public init() {}
    
    public var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 14)
                    .frame(maxWidth: 120, alignment: .leading)
            }
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 40, height: 16)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
    }
}

public struct SectionLoadingView: View {
    let title: String
    let itemCount: Int
    
    public init(title: String, itemCount: Int = 5) {
        self.title = title
        self.itemCount = itemCount
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding(.horizontal)
            
            ForEach(0..<itemCount, id: \.self) { _ in
                LoadingRowView()
            }
        }
    }
}

public struct StatusBannerView: View {
    let message: String
    let type: BannerType
    let action: (() -> Void)?
    
    public enum BannerType {
        case info
        case warning
        case error
        case success
        
        var color: Color {
            switch self {
            case .info:
                return .blue
            case .warning:
                return .orange
            case .error:
                return .red
            case .success:
                return .green
            }
        }
        
        var icon: String {
            switch self {
            case .info:
                return "info.circle"
            case .warning:
                return "exclamationmark.triangle"
            case .error:
                return "xmark.circle"
            case .success:
                return "checkmark.circle"
            }
        }
    }
    
    public init(message: String, type: BannerType, action: (() -> Void)? = nil) {
        self.message = message
        self.type = type
        self.action = action
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
            
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            if let action = action {
                Button("Fix", action: action)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(type.color)
            }
        }
        .padding()
        .background(type.color.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

#Preview("Loading View") {
    LoadingView(message: "Loading your music...")
}

#Preview("Empty State") {
    EmptyStateView(
        icon: "music.note",
        title: "No Music Found",
        subtitle: "Start listening to music to see your stats here",
        actionTitle: "Open Apple Music",
        action: {}
    )
}

#Preview("Error State") {
    ErrorStateView(
        error: NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to load music data"]),
        retryAction: {}
    )
}

#Preview("Loading Row") {
    LoadingRowView()
}