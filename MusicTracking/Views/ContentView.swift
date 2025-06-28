import SwiftUI
import MusicKit

struct ContentView: View {
    @State private var appStateManager = AppStateManager.shared
    @State private var showOnboarding = false
    
    var body: some View {
        NavigationStack {
            if showOnboarding {
                OnboardingView()
            } else if appStateManager.isInitialized {
                if appStateManager.authorizationService.isAuthorized {
                    AuthorizedAppView()
                } else {
                    WelcomeView()
                }
            } else {
                InitializationView()
            }
        }
        .task {
            if !appStateManager.isInitialized {
                await appStateManager.initialize()
            }
            
            // Show onboarding for first-time users
            if appStateManager.isInitialized && appStateManager.authorizationService.isFirstTimeUser() {
                showOnboarding = true
            }
        }
    }
}

private struct OnboardingView: View {
    @State private var appStateManager = AppStateManager.shared
    @State private var currentStep = 0
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("Music Tracking")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Get insights into your Apple Music listening habits")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 20) {
                FeatureRow(
                    icon: "chart.bar.fill",
                    title: "Weekly Statistics",
                    description: "See your top songs and artists each week"
                )
                
                FeatureRow(
                    icon: "clock.fill",
                    title: "Listening History",
                    description: "Track your music sessions automatically"
                )
                
                FeatureRow(
                    icon: "icloud.fill",
                    title: "Sync Across Devices",
                    description: "Your data stays in sync with iCloud"
                )
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button("Get Started") {
                Task {
                    try? await appStateManager.requestMusicAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Text("Apple Music subscription required")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
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
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

private struct WelcomeView: View {
    @State private var appStateManager = AppStateManager.shared
    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "music.mic")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Connect Apple Music")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("To start tracking your listening history, we need access to your Apple Music library.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: requestAuthorization) {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "music.note")
                    }
                    
                    Text(isRequesting ? "Requesting Access..." : "Connect Apple Music")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isRequesting)
            
            Text("Your music data stays private and secure")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Welcome")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func requestAuthorization() {
        isRequesting = true
        
        Task {
            do {
                try await appStateManager.requestMusicAuthorization()
            } catch {
                print("Authorization failed: \(error)")
            }
            
            await MainActor.run {
                isRequesting = false
            }
        }
    }
}

private struct AuthorizedAppView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Image(systemName: "chart.bar")
                    Text("Dashboard")
                }
            
            Text("Recent")
                .tabItem {
                    Image(systemName: "clock")
                    Text("Recent")
                }
            
            Text("Settings")
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
    }
}

private struct DashboardView: View {
    @State private var appStateManager = AppStateManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    StatusCardView()
                    
                    if appStateManager.musicKitService.isTracking {
                        TrackingActiveView()
                    }
                    
                    if let currentSong = appStateManager.musicKitService.currentSong {
                        CurrentSongView(song: currentSong)
                    }
                }
                .padding()
            }
            .navigationTitle("Music Tracking")
            .refreshable {
                await appStateManager.performHealthCheck()
            }
        }
    }
}

private struct TrackingActiveView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                Text("Tracking Active")
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            HStack {
                Image(systemName: "record.circle.fill")
                    .foregroundColor(.red)
                
                Text("Your listening sessions are being recorded")
                    .font(.caption)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGreen).opacity(0.1))
        .cornerRadius(12)
    }
}

private struct StatusCardView: View {
    @State private var appStateManager = AppStateManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: appStateManager.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(appStateManager.isHealthy ? .green : .orange)
                
                Text("System Status")
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(appStateManager.isHealthy ? "Healthy" : "Issues")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(appStateManager.isHealthy ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .cornerRadius(8)
            }
            
            if let lastCheck = appStateManager.lastHealthCheck {
                Text("Last checked: \(lastCheck, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}


private struct CurrentSongView: View {
    let song: Song
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Now Playing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(song.title)
                .fontWeight(.medium)
            
            Text(song.artistName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

private struct InitializationView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                ProgressView()
                    .scaleEffect(1.2)
                
                Text("Setting up Music Tracking")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("Preparing your personalized music experience")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}


#Preview {
    ContentView()
}