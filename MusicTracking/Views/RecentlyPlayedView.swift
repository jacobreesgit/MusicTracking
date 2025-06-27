import SwiftUI

public struct RecentlyPlayedView: View {
    @State private var viewModel = RecentlyPlayedViewModel(appStateManager: AppStateManager.shared)
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading && viewModel.recentSessions.isEmpty {
                    LoadingView(message: "Loading your listening history...")
                } else if viewModel.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "No Listening History",
                        subtitle: "Your recently played songs will appear here as you listen to music",
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
                    RecentSessionsContent()
                }
            }
            .navigationTitle("Recently Played")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            if viewModel.recentSessions.isEmpty {
                await viewModel.loadRecentSessions()
            }
        }
    }
    
    @ViewBuilder
    private func RecentSessionsContent() -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.hasData {
                    RecentStatsSection()
                    
                    ListeningHistorySection()
                }
            }
        }
        .pullToRefresh {
            await viewModel.refreshData()
        }
    }
    
    @ViewBuilder
    private func RecentStatsSection() -> some View {
        let stats = viewModel.formattedStats
        
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                StatItem(
                    title: "Sessions",
                    value: stats.sessions,
                    icon: "play.circle"
                )
                
                StatItem(
                    title: "Listen Time",
                    value: stats.time,
                    icon: "clock"
                )
                
                StatItem(
                    title: "Artists",
                    value: stats.artists,
                    icon: "person.2"
                )
                
                StatItem(
                    title: "Songs",
                    value: stats.songs,
                    icon: "music.note"
                )
            }
            .padding(.horizontal)
            
            if viewModel.getListeningStreak() > 0 {
                StreakCard(streakDays: viewModel.getListeningStreak())
                    .padding(.horizontal)
            }
        }
        .padding(.bottom)
    }
    
    @ViewBuilder
    private func ListeningHistorySection() -> some View {
        let groupedSessions = viewModel.getSessionsGroupedByDate()
        
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groupedSessions, id: \.0) { date, sessions in
                Section {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                        SessionRowView(session: session)
                            .onAppear {
                                if viewModel.shouldLoadMore(for: session) {
                                    Task {
                                        await viewModel.loadMoreSessions()
                                    }
                                }
                            }
                        
                        if index < sessions.count - 1 {
                            Divider()
                                .padding(.leading, 82)
                        }
                    }
                    
                    if viewModel.isLoadingMore && date == groupedSessions.last?.0 {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading more...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    DateSectionHeader(
                        date: date,
                        sessionCount: sessions.count,
                        totalTime: viewModel.getTotalListeningTime(for: date)
                    )
                }
            }
        }
    }
}

private struct SessionRowView: View {
    let session: DomainListeningSession
    
    var body: some View {
        SongRowView(
            song: session.song,
            lastPlayed: session.startTime,
            showLastPlayed: true
        )
        .overlay(alignment: .trailing) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.startTime.timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                if session.wasSkipped {
                    Label("Skipped", systemImage: "forward.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .labelStyle(.iconOnly)
                } else if session.isComplete {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .labelStyle(.iconOnly)
                }
            }
            .padding(.trailing)
        }
    }
}

private struct DateSectionHeader: View {
    let date: Date
    let sessionCount: Int
    let totalTime: TimeInterval
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateDisplayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\(sessionCount) songs • \(totalTime.formattedDurationShort)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(date.shortString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
        }
        .background(Color(.systemBackground))
    }
    
    private var dateDisplayName: String {
        if date.isToday {
            return "Today"
        } else if date.isYesterday {
            return "Yesterday"
        } else if date.isThisWeek {
            return date.dayString
        } else {
            return date.mediumString
        }
    }
}

private struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

private struct StreakCard: View {
    let streakDays: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Listening Streak")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text("\(streakDays) \(streakDays == 1 ? "day" : "days") in a row")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(streakDays)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    RecentlyPlayedView()
}