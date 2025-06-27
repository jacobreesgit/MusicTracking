import SwiftUI

public struct WeeklyTopView: View {
    @State private var viewModel = WeeklyTopViewModel(appStateManager: AppStateManager.shared)
    @State private var showingWeekPicker = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading && viewModel.topSongs.isEmpty {
                    LoadingView(message: "Loading weekly stats...")
                } else if viewModel.isEmpty {
                    EmptyStateView(
                        icon: "calendar",
                        title: "No Weekly Data",
                        subtitle: "Listen to music throughout the week to see your weekly top songs here",
                        actionTitle: "Refresh",
                        action: {
                            Task {
                                await viewModel.refreshData()
                            }
                        }
                    )
                } else if let error = viewModel.error {
                    ErrorStateView(
                        error: error,
                        retryAction: {
                            Task {
                                await viewModel.refreshData()
                            }
                        }
                    )
                } else {
                    WeeklyContent()
                }
            }
            .navigationTitle("Weekly Top")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.goToPreviousWeek()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!viewModel.canGoPrevious)
                    
                    Button(viewModel.weekDisplayName) {
                        showingWeekPicker = true
                    }
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    
                    Button(action: {
                        Task {
                            await viewModel.goToNextWeek()
                        }
                    }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!viewModel.canGoNext)
                }
            }
            .sheet(isPresented: $showingWeekPicker) {
                WeekPickerSheet()
            }
        }
        .task {
            if !viewModel.hasData {
                await viewModel.loadWeeklyData()
            }
        }
    }
    
    @ViewBuilder
    private func WeeklyContent() -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                WeeklyStatsSection()
                
                if viewModel.selectedWeek.isCurrentWeek {
                    WeekProgressSection()
                }
                
                TopSongsSection()
                
                TopArtistsSection()
            }
            .padding(.bottom)
        }
        .pullToRefresh {
            await viewModel.refreshData()
        }
    }
    
    @ViewBuilder
    private func WeeklyStatsSection() -> some View {
        let stats = viewModel.formattedStats
        
        VStack(spacing: 16) {
            HStack {
                Text(viewModel.weekDisplayName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated.relativeString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            HStack(spacing: 12) {
                WeeklyStatCard(
                    title: "Listen Time",
                    value: stats.playTime,
                    icon: "clock.fill",
                    color: .blue
                )
                
                WeeklyStatCard(
                    title: "Songs",
                    value: stats.songs,
                    icon: "music.note",
                    color: .green
                )
                
                WeeklyStatCard(
                    title: "Artists",
                    value: stats.artists,
                    icon: "person.2.fill",
                    color: .orange
                )
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private func WeekProgressSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Week Progress")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(viewModel.weekProgress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            
            ProgressView(value: viewModel.weekProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .scaleEffect(y: 2)
            
            HStack {
                Text("Monday")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Sunday")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func TopSongsSection() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SongListHeaderView(
                title: "Top Songs",
                subtitle: viewModel.topSongs.isEmpty ? "No songs this week" : "Top \(min(viewModel.topSongs.count, 10)) songs"
            )
            
            if viewModel.topSongs.isEmpty {
                EmptyTopSongsView()
            } else {
                ForEach(Array(viewModel.topSongs.prefix(10).enumerated()), id: \.offset) { index, songData in
                    let (song, playCount) = songData
                    
                    SongRowView(
                        song: song,
                        playCount: playCount,
                        showPlayCount: true,
                        ranking: index + 1
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Handle song tap
                    }
                    
                    if index < min(viewModel.topSongs.count, 10) - 1 {
                        Divider()
                            .padding(.leading, 82)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func TopArtistsSection() -> some View {
        let topArtists = viewModel.getTopArtists()
        
        if !topArtists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SongListHeaderView(
                    title: "Top Artists",
                    subtitle: "Most played artists this week"
                )
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(Array(topArtists.prefix(6).enumerated()), id: \.offset) { index, artistData in
                        let (artistName, playCount) = artistData
                        
                        ArtistCard(
                            artistName: artistName,
                            playCount: playCount,
                            ranking: index + 1
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private func WeekPickerSheet() -> some View {
        NavigationView {
            List {
                ForEach(viewModel.availableWeeks, id: \.startDate) { week in
                    Button(action: {
                        Task {
                            await viewModel.selectWeek(week)
                        }
                        showingWeekPicker = false
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(week.isCurrentWeek ? "This Week" : week.displayName)
                                    .foregroundColor(.primary)
                                    .fontWeight(week.isCurrentWeek ? .medium : .regular)
                                
                                Text(week.startDate.mediumString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if week == viewModel.selectedWeek {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingWeekPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct WeeklyStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

private struct ArtistCard: View {
    let artistName: String
    let playCount: Int
    let ranking: Int
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("#\(ranking)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(playCount)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            
            Text(artistName)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

private struct EmptyTopSongsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.house")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No songs played this week")
                .font(.callout)
                .foregroundColor(.secondary)
            
            Text("Start listening to see your top songs here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
    }
}

#Preview {
    WeeklyTopView()
}