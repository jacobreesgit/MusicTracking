import SwiftUI

public struct PrivacyConsentView: View {
    @State private var currentPage = 0
    @State private var hasAgreedToPrivacy = false
    @State private var hasAgreedToDataCollection = false
    @State private var isRequestingPermissions = false
    @State private var permissionError: AppError?
    
    private let onConsentCompleted: () -> Void
    
    public init(onConsentCompleted: @escaping () -> Void) {
        self.onConsentCompleted = onConsentCompleted
    }
    
    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Progress indicator
                ProgressView(value: Double(currentPage + 1), total: 4)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .scaleEffect(y: 2)
                    .padding(.horizontal)
                    .padding(.top)
                
                TabView(selection: $currentPage) {
                    WelcomePage()
                        .tag(0)
                    
                    DataCollectionPage(hasAgreed: $hasAgreedToDataCollection)
                        .tag(1)
                    
                    PrivacyPage(hasAgreed: $hasAgreedToPrivacy)
                        .tag(2)
                    
                    PermissionsPage(
                        isRequesting: $isRequestingPermissions,
                        error: $permissionError,
                        onComplete: onConsentCompleted
                    )
                    .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if currentPage > 0 {
                        Button(action: {
                            withAnimation {
                                currentPage -= 1
                            }
                        }) {
                            Text("Back")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    
                    Button(action: {
                        handleNextButton()
                    }) {
                        Text(nextButtonTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canProceed ? Color.blue : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!canProceed || isRequestingPermissions)
                }
                .padding()
            }
        }
        .errorAlert(error: $permissionError)
    }
    
    private var canProceed: Bool {
        switch currentPage {
        case 0:
            return true
        case 1:
            return hasAgreedToDataCollection
        case 2:
            return hasAgreedToPrivacy
        case 3:
            return !isRequestingPermissions
        default:
            return false
        }
    }
    
    private var nextButtonTitle: String {
        switch currentPage {
        case 0, 1, 2:
            return "Continue"
        case 3:
            return "Get Started"
        default:
            return "Continue"
        }
    }
    
    private func handleNextButton() {
        if currentPage < 3 {
            withAnimation {
                currentPage += 1
            }
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)
                
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Welcome to Music Tracking")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Discover your music patterns and listening habits")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 24) {
                    FeatureRow(
                        icon: "chart.bar.fill",
                        title: "Listening Statistics",
                        description: "Track your top songs, artists, and listening trends"
                    )
                    
                    FeatureRow(
                        icon: "calendar",
                        title: "Weekly Reports",
                        description: "Get insights into your weekly music patterns"
                    )
                    
                    FeatureRow(
                        icon: "icloud.fill",
                        title: "iCloud Sync",
                        description: "Your data syncs securely across all your devices"
                    )
                    
                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "Privacy First",
                        description: "Your data stays private and is never shared"
                    )
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
    }
}

private struct DataCollectionPage: View {
    @Binding var hasAgreed: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 20)
                
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Data Collection")
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                VStack(alignment: .leading, spacing: 20) {
                    Text("What we collect:")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    DataPointRow(
                        icon: "music.note",
                        title: "Song Information",
                        description: "Song titles, artists, albums, and genres"
                    )
                    
                    DataPointRow(
                        icon: "clock",
                        title: "Listening Times",
                        description: "When you start and stop listening to songs"
                    )
                    
                    DataPointRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Play Statistics",
                        description: "Play counts and skip information"
                    )
                    
                    Divider()
                        .padding(.vertical)
                    
                    Text("What we DON'T collect:")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        BulletPoint(text: "Personal information (name, email, contacts)")
                        BulletPoint(text: "Location data")
                        BulletPoint(text: "Device information beyond music preferences")
                        BulletPoint(text: "Any data from other apps")
                    }
                }
                
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Button(action: {
                            hasAgreed.toggle()
                        }) {
                            Image(systemName: hasAgreed ? "checkmark.square.fill" : "square")
                                .font(.title2)
                                .foregroundColor(hasAgreed ? .blue : .secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I agree to the collection of my music listening data as described above")
                                .font(.callout)
                            
                            Text("This data will only be used to provide you with personalized music insights")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hasAgreed.toggle()
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                Spacer(minLength: 20)
            }
            .padding()
        }
    }
}

private struct PrivacyPage: View {
    @Binding var hasAgreed: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 20)
                
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Your Privacy Matters")
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                VStack(alignment: .leading, spacing: 20) {
                    PrivacyPointRow(
                        icon: "lock.fill",
                        title: "Local Storage",
                        description: "All data is stored securely on your device"
                    )
                    
                    PrivacyPointRow(
                        icon: "icloud.fill",
                        title: "iCloud Sync",
                        description: "Data syncs through your personal iCloud account"
                    )
                    
                    PrivacyPointRow(
                        icon: "eye.slash.fill",
                        title: "No Third-Party Sharing",
                        description: "Your data is never shared with anyone else"
                    )
                    
                    PrivacyPointRow(
                        icon: "trash.fill",
                        title: "Full Control",
                        description: "Export or delete your data anytime"
                    )
                    
                    PrivacyPointRow(
                        icon: "shield.checkerboard",
                        title: "No Ads or Tracking",
                        description: "No advertisements or behavioral tracking"
                    )
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Retention:")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("• Data is kept until you choose to delete it\n• Uninstalling the app removes all local data\n• You can export your data before deletion")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Button(action: {
                            hasAgreed.toggle()
                        }) {
                            Image(systemName: hasAgreed ? "checkmark.square.fill" : "square")
                                .font(.title2)
                                .foregroundColor(hasAgreed ? .blue : .secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I understand and agree to the privacy practices described above")
                                .font(.callout)
                            
                            Text("You can review the full privacy policy in Settings at any time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hasAgreed.toggle()
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                Spacer(minLength: 20)
            }
            .padding()
        }
    }
}

private struct PermissionsPage: View {
    @Binding var isRequesting: Bool
    @Binding var error: AppError?
    let onComplete: () -> Void
    
    @State private var musicPermissionGranted = false
    @State private var hasRequestedPermissions = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                Text("Apple Music Access")
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("To track your music listening habits, we need access to your Apple Music data.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                    
                    PermissionRow(
                        icon: "music.note",
                        title: "Apple Music Library",
                        description: "Access your music library and listening history",
                        isGranted: musicPermissionGranted
                    )
                }
                
                if !hasRequestedPermissions {
                    VStack(spacing: 12) {
                        Text("Tap \"Get Started\" to grant permissions")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        
                        Text("You can change these permissions later in Settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if isRequesting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        Text("Requesting permissions...")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                } else if musicPermissionGranted {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        
                        Text("All set! You're ready to start tracking your music.")
                            .font(.callout)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 12) {
                        Text("Permission Required")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        
                        Text("Music Tracking needs access to your Apple Music data to function properly.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            
            Spacer()
            
            if musicPermissionGranted && hasRequestedPermissions {
                Button(action: {
                    onComplete()
                }) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            } else if !hasRequestedPermissions {
                Button(action: {
                    requestPermissions()
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .disabled(isRequesting)
                .padding(.horizontal)
            } else if !musicPermissionGranted {
                Button(action: {
                    openSettings()
                }) {
                    Text("Open Settings")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
        }
        .padding()
    }
    
    private func requestPermissions() {
        hasRequestedPermissions = true
        isRequesting = true
        
        Task {
            do {
                try await AppStateManager.shared.requestMusicAuthorization()
                
                await MainActor.run {
                    musicPermissionGranted = true
                    isRequesting = false
                }
                
            } catch {
                await MainActor.run {
                    isRequesting = false
                    self.error = error as? AppError ?? AppError.musicKitNotAuthorized
                }
            }
        }
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Supporting Views

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
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

private struct DataPointRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.green)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

private struct PrivacyPointRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
}

private struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.callout)
                .foregroundColor(.secondary)
            
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

#Preview {
    PrivacyConsentView {
        print("Consent completed")
    }
}