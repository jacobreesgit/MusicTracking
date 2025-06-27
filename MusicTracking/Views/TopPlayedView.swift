import SwiftUI

public struct TopPlayedView: View {
    @State private var viewModel = TopPlayedViewModel(appStateManager: AppStateManager.shared)
    @State private var showingTimeframePicker = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading && viewModel.topSongs.isEmpty {
                    LoadingView(message: "Loading your top songs...")
                } else if viewModel.isEmpty {
                    EmptyStateView(
                        icon: "music.note",
                        title: "No Music Data",
                        subtitle: "Start listening to music to see your top played songs here",
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
                    TopSongsContent()
                }
            }
            .navigationTitle("Top Played")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(viewModel.timeframe.shortDescription) {
                        showingTimeframePicker = true
                    }
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                }
            }
            .sheet(isPresented: $showingTimeframePicker) {
                TimeframePickerSheet()
            }
        }
        .task {
            if viewModel.topSongs.isEmpty {
                await viewModel.loadTopSongs()
            }
        }
    }
    
    @ViewBuilder
    private func TopSongsContent() -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.hasData {
                    StatsHeaderSection()
                    
                    TopSongsSection()
                }
            }
        }
        .pullToRefresh {
            await viewModel.refreshData()
        }
    }
    
    @ViewBuilder
    private func StatsHeaderSection() -> some View {
        let stats = viewModel.formattedStats
        
        VStack(spacing: 16) {
            SongStatsView(
                totalSongs: viewModel.totalSongs,
                totalPlayTime: viewModel.totalPlayTime,
                topGenre: viewModel.getTopGenres().first
            )
            
            HStack(spacing: 20) {
                StatCard(
                    title: "Avg Plays",
                    value: stats.avgPlays,
                    icon: "repeat"
                )
                
                StatCard(
                    title: "Top Genre",
                    value: viewModel.getTopGenres().first ?? "Unknown",
                    icon: "guitars"
                )
                
                StatCard(
                    title: "Total Time",
                    value: stats.playTime,
                    icon: "clock"
                )
            }
            .padding(.horizontal)
        }
        .padding(.bottom)
    }
    
    @ViewBuilder
    private func TopSongsSection() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SongListHeaderView(
                title: "Top Songs",
                subtitle: "Most played tracks for \(viewModel.timeframe.rawValue.lowercased())"
            )
            
            ForEach(Array(viewModel.topSongs.enumerated()), id: \.offset) { index, songData in
                let (song, playCount) = songData
                
                SongRowView(
                    song: song,
                    playCount: playCount,
                    showPlayCount: true,
                    ranking: index + 1
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    // Handle song tap - could open in Apple Music
                }
                
                if index < viewModel.topSongs.count - 1 {
                    Divider()
                        .padding(.leading, 82)
                }
            }
        }
    }
    
    @ViewBuilder
    private func TimeframePickerSheet() -> some View {
        NavigationView {
            List {
                ForEach(TopPlayedTimeframe.allCases, id: \.self) { timeframe in
                    Button(action: {
                        Task {
                            await viewModel.changeTimeframe(timeframe)
                        }
                        showingTimeframePicker = false
                    }) {
                        HStack {
                            Text(timeframe.rawValue)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if timeframe == viewModel.timeframe {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Time Period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingTimeframePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
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

#Preview {
    TopPlayedView()
}