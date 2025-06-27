import SwiftUI

public struct MainTabView: View {
    @State private var appStateManager = AppStateManager.shared
    @State private var selectedTab: Tab = .topPlayed
    @State private var showingSettings = false
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            TopPlayedView()
                .tabItem {
                    Label("Top Played", systemImage: "chart.bar")
                }
                .tag(Tab.topPlayed)
            
            RecentlyPlayedView()
                .tabItem {
                    Label("Recently Played", systemImage: "clock")
                }
                .tag(Tab.recentlyPlayed)
            
            WeeklyTopView()
                .tabItem {
                    Label("Weekly Top", systemImage: "calendar")
                }
                .tag(Tab.weeklyTop)
        }
        .tint(.blue)
        .onAppear {
            if !appStateManager.isInitialized {
                Task {
                    await appStateManager.initialize()
                }
            }
        }
        .overlay(alignment: .top) {
            if appStateManager.getAppStatus().needsUserAttention {
                StatusBanner()
            }
        }
        .overlay(alignment: .topTrailing) {
            SettingsButton()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
    
    @ViewBuilder
    private func SettingsButton() -> some View {
        Button(action: {
            showingSettings = true
        }) {
            Image(systemName: "gear")
                .font(.title2)
                .foregroundColor(.primary)
                .padding(12)
                .background(.regularMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .padding(.trailing, 16)
        .padding(.top, 8)
    }
}

private enum Tab: String, CaseIterable {
    case topPlayed = "topPlayed"
    case recentlyPlayed = "recentlyPlayed"
    case weeklyTop = "weeklyTop"
}

private struct StatusBanner: View {
    @State private var appStateManager = AppStateManager.shared
    @State private var showingAuthSheet = false
    
    var body: some View {
        let status = appStateManager.getAppStatus()
        
        if !status.authorizationInfo.isAuthorized {
            StatusBannerView(
                message: "Apple Music access required to track your listening history",
                type: .warning,
                action: {
                    showingAuthSheet = true
                }
            )
            .sheet(isPresented: $showingAuthSheet) {
                AuthorizationSheet()
            }
        } else if !status.isHealthy {
            StatusBannerView(
                message: status.detailedStatus,
                type: .error,
                action: {
                    Task {
                        try? await appStateManager.refreshServices()
                    }
                }
            )
        }
    }
}

private struct StatusBannerView: View {
    let message: String
    let type: BannerType
    let action: (() -> Void)?
    
    enum BannerType {
        case warning, error, info
        
        var color: Color {
            switch self {
            case .warning: return .orange
            case .error: return .red
            case .info: return .blue
            }
        }
        
        var icon: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
                .font(.headline)
            
            Text(message)
                .font(.callout)
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Spacer()
            
            if let action = action {
                Button("Fix") {
                    action()
                }
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(type.color)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

private struct AuthorizationSheet: View {
    @State private var appStateManager = AppStateManager.shared
    @State private var isRequesting = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)
                    
                    Text("Music Tracking")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Track your Apple Music listening history and discover your music patterns")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 16) {
                    FeatureRow(
                        icon: "chart.bar.fill",
                        title: "Top Played Songs",
                        description: "See your most played tracks over different time periods"
                    )
                    
                    FeatureRow(
                        icon: "clock.fill",
                        title: "Recently Played",
                        description: "View your complete listening history"
                    )
                    
                    FeatureRow(
                        icon: "calendar",
                        title: "Weekly Stats",
                        description: "Track your weekly listening patterns and trends"
                    )
                    
                    FeatureRow(
                        icon: "shield.fill",
                        title: "Privacy Protected",
                        description: "All data stays on your device and syncs via iCloud"
                    )
                }
                .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: requestAuthorization) {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "music.note")
                            }
                            
                            Text(isRequesting ? "Requesting Access..." : "Connect Apple Music")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isRequesting)
                    
                    Button("Maybe Later") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func requestAuthorization() {
        isRequesting = true
        
        Task {
            do {
                try await appStateManager.requestMusicAuthorization()
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("Authorization failed: \(error)")
            }
            
            await MainActor.run {
                isRequesting = false
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    MainTabView()
}