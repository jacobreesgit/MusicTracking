import SwiftUI

public struct SongRowView: View {
    let song: Song
    let playCount: Int?
    let lastPlayed: Date?
    let showArtwork: Bool
    let showPlayCount: Bool
    let showLastPlayed: Bool
    let ranking: Int?
    
    public init(
        song: Song,
        playCount: Int? = nil,
        lastPlayed: Date? = nil,
        showArtwork: Bool = true,
        showPlayCount: Bool = false,
        showLastPlayed: Bool = false,
        ranking: Int? = nil
    ) {
        self.song = song
        self.playCount = playCount
        self.lastPlayed = lastPlayed
        self.showArtwork = showArtwork
        self.showPlayCount = showPlayCount
        self.showLastPlayed = showLastPlayed
        self.ranking = ranking
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            if let ranking = ranking {
                Text("\(ranking)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }
            
            if showArtwork {
                ArtworkView(url: song.artworkURL, size: 50)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text(song.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let albumTitle = song.albumTitle {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(albumTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                if song.isExplicit {
                    HStack(spacing: 4) {
                        Image(systemName: "e.square")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if !song.genreNames.isEmpty {
                            Text(song.genreNames.first!)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if showPlayCount, let playCount = playCount {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(playCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                
                if showLastPlayed, let lastPlayed = lastPlayed {
                    Text(lastPlayed.relativeString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if let duration = song.duration {
                    Text(duration.formattedDuration)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

public struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    
    public init(url: URL?, size: CGFloat = 50) {
        self.url = url
        self.size = size
    }
    
    public var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ArtworkPlaceholder()
                }
            } else {
                ArtworkPlaceholder()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

public struct ArtworkPlaceholder: View {
    public init() {}
    
    public var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundColor(.secondary)
            )
    }
}

public struct CompactSongRowView: View {
    let song: Song
    let subtitle: String
    let accessory: String?
    
    public init(song: Song, subtitle: String, accessory: String? = nil) {
        self.song = song
        self.subtitle = subtitle
        self.accessory = accessory
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: song.artworkURL, size: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let accessory = accessory {
                Text(accessory)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

public struct SongListHeaderView: View {
    let title: String
    let subtitle: String?
    let showSeeAll: Bool
    let seeAllAction: (() -> Void)?
    
    public init(
        title: String,
        subtitle: String? = nil,
        showSeeAll: Bool = false,
        seeAllAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showSeeAll = showSeeAll
        self.seeAllAction = seeAllAction
    }
    
    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if showSeeAll, let action = seeAllAction {
                Button("See All", action: action)
                    .font(.callout)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

public struct SongStatsView: View {
    let totalSongs: Int
    let totalPlayTime: TimeInterval
    let topGenre: String?
    
    public init(totalSongs: Int, totalPlayTime: TimeInterval, topGenre: String? = nil) {
        self.totalSongs = totalSongs
        self.totalPlayTime = totalPlayTime
        self.topGenre = topGenre
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                StatItem(
                    value: "\(totalSongs)",
                    label: "Songs",
                    icon: "music.note"
                )
                
                StatItem(
                    value: totalPlayTime.formattedDurationMedium,
                    label: "Listen Time",
                    icon: "clock"
                )
                
                if let topGenre = topGenre {
                    StatItem(
                        value: topGenre,
                        label: "Top Genre",
                        icon: "guitars"
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

private struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Song Row - Full") {
    SongRowView(
        song: Song(
            id: MusicItemID("123"),
            title: "Bohemian Rhapsody",
            artistName: "Queen",
            albumTitle: "A Night at the Opera",
            duration: 355,
            isExplicit: false,
            genreNames: ["Rock", "Progressive Rock"]
        ),
        playCount: 42,
        lastPlayed: Date().addingTimeInterval(-3600),
        showPlayCount: true,
        showLastPlayed: true,
        ranking: 1
    )
}

#Preview("Song Row - Compact") {
    CompactSongRowView(
        song: Song(
            id: MusicItemID("123"),
            title: "Bohemian Rhapsody",
            artistName: "Queen",
            albumTitle: "A Night at the Opera"
        ),
        subtitle: "Queen • A Night at the Opera",
        accessory: "5:55"
    )
}

#Preview("Song Stats") {
    SongStatsView(
        totalSongs: 1234,
        totalPlayTime: 86400,
        topGenre: "Rock"
    )
}