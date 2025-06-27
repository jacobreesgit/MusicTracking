import SwiftUI

struct ContentView: View {
    @State private var appStateManager = AppStateManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HeaderView()
                
                if appStateManager.isInitialized {
                    MainContentView()
                } else {
                    InitializationView()
                }
                
                Spacer()
                
                FooterView()
            }
            .padding()
            .navigationTitle("Music Tracking")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            if !appStateManager.isInitialized {
                await appStateManager.initialize()
            }
        }
    }
}

private struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Music Tracking")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Track your Apple Music listening history")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct MainContentView: View {
    @State private var appStateManager = AppStateManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            StatusCardView()
            
            if appStateManager.authorizationService.isAuthorized {
                AuthorizedContentView()
            } else {
                UnauthorizedContentView()
            }
        }
    }
}

private struct StatusCardView: View {
    @State private var appStateManager = AppStateManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: appStateManager.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(appStateManager.isHealthy ? .green : .orange)
                
                Text("Status: \(appStateManager.getAppStatus().statusDescription)")
                    .fontWeight(.medium)
                
                Spacer()
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

private struct AuthorizedContentView: View {
    @State private var appStateManager = AppStateManager.shared
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                Text("Apple Music Connected")
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            if appStateManager.musicKitService.isTracking {
                HStack {
                    Image(systemName: "record.circle.fill")
                        .foregroundColor(.red)
                    
                    Text("Listening tracking active")
                        .font(.caption)
                    
                    Spacer()
                }
            }
            
            if let currentSong = appStateManager.musicKitService.currentSong {
                CurrentSongView(song: currentSong)
            }
        }
        .padding()
        .background(Color(.systemGreen).opacity(0.1))
        .cornerRadius(12)
    }
}

private struct UnauthorizedContentView: View {
    @State private var appStateManager = AppStateManager.shared
    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "music.mic")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                
                Text("Apple Music Access Required")
                    .fontWeight(.medium)
                
                Text("Grant permission to track your listening history")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: requestAuthorization) {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "music.note")
                    }
                    
                    Text(isRequesting ? "Requesting..." : "Connect Apple Music")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isRequesting)
        }
        .padding()
        .background(Color(.systemOrange).opacity(0.1))
        .cornerRadius(12)
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
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Initializing Music Tracking...")
                .font(.headline)
            
            Text("Setting up Apple Music integration")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct FooterView: View {
    var body: some View {
        Text("Apple Music integration powered by MusicKit")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

#Preview {
    ContentView()
}