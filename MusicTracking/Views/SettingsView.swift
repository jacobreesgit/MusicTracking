import SwiftUI

public struct SettingsView: View {
    @State private var appStateManager = AppStateManager.shared
    @State private var showingPrivacyPolicy = false
    @State private var showingDataExport = false
    @State private var showingDeleteDataAlert = false
    @State private var isExporting = false
    @State private var exportError: AppError?
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                MonitoringSection()
                
                PrivacySection()
                
                DataSection()
                
                SyncSection()
                
                AboutSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .sheet(isPresented: $showingDataExport) {
                DataExportView()
            }
            .alert("Delete All Data", isPresented: $showingDeleteDataAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteAllData()
                    }
                }
            } message: {
                Text("This will permanently delete all your listening history and cannot be undone.")
            }
            .errorAlert(error: $exportError)
        }
    }
    
    @ViewBuilder
    private func MonitoringSection() -> some View {
        Section("Background Monitoring") {
            let (isActive, state, metrics) = appStateManager.getBackgroundMonitoringStatus()
            
            HStack {
                Image(systemName: isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isActive ? .green : .red)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Background Tracking")
                        .font(.callout)
                    
                    Text(state.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: .constant(isActive))
                    .disabled(true)
            }
            
            if let metrics = metrics {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(title: "Sessions Tracked", value: "\(metrics.totalSessions)")
                    MetricRow(title: "Total Uptime", value: metrics.formattedMetrics.uptime)
                    MetricRow(title: "Success Rate", value: metrics.formattedMetrics.successRate)
                }
                .padding(.vertical, 4)
            }
            
            Button(action: {
                Task {
                    await toggleBackgroundMonitoring()
                }
            }) {
                HStack {
                    Image(systemName: isActive ? "stop.circle" : "play.circle")
                    Text(isActive ? "Stop Monitoring" : "Start Monitoring")
                }
            }
            .foregroundColor(isActive ? .red : .blue)
        }
    }
    
    @ViewBuilder
    private func PrivacySection() -> some View {
        Section("Privacy & Data") {
            Button(action: {
                showingPrivacyPolicy = true
            }) {
                HStack {
                    Image(systemName: "doc.text")
                    Text("Privacy Policy")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .foregroundColor(.primary)
            
            HStack {
                Image(systemName: "lock.shield")
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data Protection")
                        .font(.callout)
                    
                    Text("All data is stored locally and synced securely via iCloud")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Image(systemName: "eye.slash")
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Third-Party Sharing")
                        .font(.callout)
                    
                    Text("Your listening data is never shared with third parties")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private func DataSection() -> some View {
        Section("Data Management") {
            Button(action: {
                showingDataExport = true
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Data")
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .foregroundColor(.primary)
            .disabled(isExporting)
            
            let storageInfo = getStorageInfo()
            VStack(alignment: .leading, spacing: 8) {
                MetricRow(title: "Sessions Stored", value: "\(storageInfo.sessionCount)")
                MetricRow(title: "Songs Tracked", value: "\(storageInfo.songCount)")
                MetricRow(title: "Storage Used", value: storageInfo.storageSize)
            }
            .padding(.vertical, 4)
            
            Button(action: {
                showingDeleteDataAlert = true
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete All Data")
                }
            }
            .foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    private func SyncSection() -> some View {
        Section("iCloud Sync") {
            let syncInfo = appStateManager.cloudKitSyncService.getSyncInfo()
            
            HStack {
                Image(systemName: syncInfo.isHealthy ? "icloud.fill" : "icloud.slash.fill")
                    .foregroundColor(syncInfo.isHealthy ? .blue : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Status")
                        .font(.callout)
                    
                    Text(syncInfo.status.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if syncInfo.isInProgress {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let lastSync = syncInfo.lastSuccessfulSync {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last Sync")
                            .font(.callout)
                        
                        Text(lastSync.relativeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Button(action: {
                Task {
                    await triggerManualSync()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
            }
            .disabled(syncInfo.isInProgress)
        }
    }
    
    @ViewBuilder
    private func AboutSection() -> some View {
        Section("About") {
            HStack {
                Image(systemName: "info.circle")
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version")
                        .font(.callout)
                    
                    Text(getAppVersion())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Image(systemName: "music.note.list")
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Music Tracking")
                        .font(.callout)
                    
                    Text("Discover your music patterns")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: {
                openAppStore()
            }) {
                HStack {
                    Image(systemName: "star")
                    Text("Rate on App Store")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .foregroundColor(.primary)
        }
    }
    
    private func toggleBackgroundMonitoring() async {
        do {
            try await appStateManager.toggleBackgroundMonitoring()
        } catch {
            exportError = error as? AppError ?? AppError.backgroundTaskFailed("Failed to toggle monitoring")
        }
    }
    
    private func triggerManualSync() async {
        do {
            try await appStateManager.triggerManualSync()
        } catch {
            exportError = error as? AppError ?? AppError.cloudKitSyncFailed("Manual sync failed")
        }
    }
    
    private func deleteAllData() async {
        do {
            try await appStateManager.repository.deleteAllData()
        } catch {
            exportError = error as? AppError ?? AppError.coreDataSaveFailed("Failed to delete data")
        }
    }
    
    private func getStorageInfo() -> (sessionCount: Int, songCount: Int, storageSize: String) {
        // This would be implemented with actual storage queries
        return (sessionCount: 1234, songCount: 567, storageSize: "2.3 MB")
    }
    
    private func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    private func openAppStore() {
        if let url = URL(string: "https://apps.apple.com/app/id123456789") {
            UIApplication.shared.open(url)
        }
    }
}

private struct MetricRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

private struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Music Tracking Privacy Policy")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.bottom)
                    
                    PrivacySection(
                        title: "Data Collection",
                        content: "Music Tracking only collects data about your music listening habits from Apple Music. This includes song titles, artists, albums, play counts, and listening times."
                    )
                    
                    PrivacySection(
                        title: "Data Storage",
                        content: "All data is stored locally on your device and synchronized securely through your personal iCloud account. We do not have access to your data."
                    )
                    
                    PrivacySection(
                        title: "Data Sharing",
                        content: "Your listening data is never shared with third parties. All statistics and insights are generated locally on your device."
                    )
                    
                    PrivacySection(
                        title: "Data Control",
                        content: "You can export or delete all your data at any time from the Settings screen. Deleting the app will remove all locally stored data."
                    )
                    
                    Text("Last updated: \(Date().mediumString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top)
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PrivacySection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(content)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

private struct DataExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var exportComplete = false
    @State private var exportError: AppError?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("Export Your Data")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Export all your listening history as a JSON file")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if isExporting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        Text("Preparing your data...")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                } else if exportComplete {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        
                        Text("Export Complete")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                } else {
                    Button(action: {
                        Task {
                            await exportData()
                        }
                    }) {
                        Text("Export Data")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .errorAlert(error: $exportError)
        }
    }
    
    private func exportData() async {
        isExporting = true
        
        do {
            // Simulate export process
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await MainActor.run {
                isExporting = false
                exportComplete = true
            }
            
            // Here you would implement actual data export
            
        } catch {
            await MainActor.run {
                isExporting = false
                exportError = AppError.backgroundTaskFailed("Export failed: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    SettingsView()
}