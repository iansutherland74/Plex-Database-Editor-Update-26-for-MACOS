import SwiftUI
import SQLite3
import AppKit

// MARK: - Plex Color Scheme
extension Color {
    static let plexOrange = Color(red: 0.90, green: 0.64, blue: 0.12)
    static let plexDarkGray = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let plexMediumGray = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let plexLightGray = Color(red: 0.21, green: 0.21, blue: 0.21)
    static let plexTextPrimary = Color(red: 0.90, green: 0.90, blue: 0.90)
    static let plexTextSecondary = Color(red: 0.65, green: 0.65, blue: 0.65)
}

struct ContentView: View {
    @StateObject private var viewModel = PlexTVEditorViewModel()
    @State private var selectedTab: Int = 0
    @State private var selectedShowListId: Int?

    var body: some View {
        ZStack {
            Color.plexDarkGray.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack(spacing: 0) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.plexOrange)
                        .padding(.leading, 20)
                    
                    Text("Plex TV Editor")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.plexTextPrimary)
                        .padding(.leading, 12)
                    
                    Spacer()
                    
                    // Tab Buttons
                    HStack(spacing: 4) {
                        TabButton(title: "TV Shows", icon: "tv", isSelected: selectedTab == 0) {
                            selectedTab = 0
                        }
                        TabButton(title: "Movies", icon: "film", isSelected: selectedTab == 3) {
                            selectedTab = 3
                        }
                        TabButton(title: "Settings", icon: "gearshape", isSelected: selectedTab == 4) {
                            selectedTab = 4
                        }
                    }
                    .padding(.trailing, 20)
                }
                .frame(height: 60)
                .background(Color.plexMediumGray)
                
                // Main Content Area
                HSplitView {
                    // Sidebar
                    VStack(spacing: 0) {
                        if selectedTab == 3 {
                            // Movies List
                            ScrollView {
                                LazyVStack(spacing: 1) {
                                    ForEach(viewModel.movies, id: \.id) { movie in
                                        SidebarItemView(
                                            title: movie.title,
                                            subtitle: movie.year != nil ? "\(movie.year!)" : nil,
                                            isSelected: false
                                        )
                                    }
                                }
                            }
                        } else if selectedTab != 4 {
                            // TV Shows List
                            ScrollView {
                                LazyVStack(spacing: 1) {
                                    ForEach(viewModel.shows, id: \.id) { show in
                                        SidebarItemView(
                                            title: show.title,
                                            subtitle: show.year != nil ? "\(show.year!)" : nil,
                                            isSelected: selectedShowListId == show.id
                                        )
                                        .onTapGesture {
                                            selectedShowListId = show.id
                                            viewModel.selectShow(show)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: 250, idealWidth: 300)
                    .background(Color.plexMediumGray)
                    
                    // Detail View
                    ZStack {
                        Color.plexDarkGray
                        
                        if selectedTab == 0 || selectedTab == 1 || selectedTab == 2 {
                            TVShowDetailView(viewModel: viewModel, selectedTab: $selectedTab)
                        } else if selectedTab == 3 {
                            MoviesDetailView_New(viewModel: viewModel)
                        } else {
                            SettingsView_New(viewModel: viewModel)
                        }
                    }
                }
                
                // Status Bar
                HStack {
                    Image(systemName: viewModel.statusMessage.isEmpty ? "checkmark.circle" : "info.circle")
                        .foregroundColor(.plexOrange)
                    Text(viewModel.statusMessage.isEmpty ? "Ready" : viewModel.statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.plexTextSecondary)
                    Spacer()
                }
                .frame(height: 28)
                .padding(.horizontal, 20)
                .background(Color.plexMediumGray)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadShows()
            viewModel.loadMovies()
        }
    }
}

// MARK: - Tab Button
struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? .plexOrange : .plexTextSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.plexOrange.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Sidebar Item
struct SidebarItemView: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.plexTextPrimary)
                    .lineLimit(1)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.plexTextSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.plexOrange.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - TV Show Detail View
struct TVShowDetailView: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel
    @Binding var selectedTab: Int
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !viewModel.recentShows().isEmpty {
                    SectionCard(title: "Recent Shows", icon: "clock.arrow.circlepath") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.recentShows(), id: \.id) { show in
                                    Button {
                                        viewModel.selectShow(show)
                                        selectedTab = 0
                                    } label: {
                                        Text(show.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(viewModel.selectedShowId == show.id ? .black : .plexTextPrimary)
                                            .lineLimit(1)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(viewModel.selectedShowId == show.id ? Color.plexOrange : Color.plexLightGray.opacity(0.5))
                                            .cornerRadius(12)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(12)
                        }
                    }
                }

                if viewModel.selectedShowId > 0 {
                    // Seasons Section
                    SectionCard(title: "Seasons", icon: "list.number") {
                        if viewModel.seasons.isEmpty {
                            Text("No seasons found")
                                .foregroundColor(.plexTextSecondary)
                                .padding()
                        } else {
                            VStack(spacing: 8) {
                                ForEach(viewModel.seasons, id: \.id) { season in
                                    SeasonRowView(season: season) {
                                        viewModel.selectSeason(season)
                                        selectedTab = 2
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    
                    // Episodes Section
                    if viewModel.selectedSeasonId > 0 {
                        EpisodesSection_New(viewModel: viewModel)
                    }
                } else {
                    EmptyStateView(
                        icon: "tv",
                        message: "Select a TV show from the sidebar to begin"
                    )
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Season Row
struct SeasonRowView: View {
    let season: Season
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.plexOrange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Season \(season.season_number)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.plexTextPrimary)
                    Text("\(season.episode_count) episodes")
                        .font(.system(size: 12))
                        .foregroundColor(.plexTextSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.plexTextSecondary)
            }
            .padding(12)
            .background(Color.plexLightGray)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Episodes Section
struct EpisodesSection_New: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel
    @State private var selectedEpisodeIds: Set<Int> = []
    @State private var autoSelectSeasonEpisodes = false
    @State private var showPlexPreviewPanel = false
    @State private var previewEpisodeId: Int?
    @State private var showRemapPanel = false
    @State private var manualEditTitle = ""
    @State private var manualEditSeasonNumber = ""
    @State private var manualEditEpisodeNumber = ""
    @State private var manualTMDBSeasonNumber = ""
    @State private var manualTMDBEpisodeNumber = ""
    @State private var manualTMDBShowRef = ""
    @State private var manualTMDBCode = ""
    @State private var manualEpisodeCount = ""
    @State private var remapSeasonNumber: Int = 1
    @State private var remapEpisodeNumber: Int = 1
    @State private var remapUpdateTitle = true
    @State private var remapUpdateAirDate = true
    @State private var remapUpdateSummary = true
    @State private var remapUpdateYear = true
    @State private var remapRequireTMDBMatch = false
    @State private var remapCode = ""
    
    var body: some View {
        SectionCard(title: "Episodes", icon: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                // Selection Controls
                HStack {
                    Button(action: {
                        selectedEpisodeIds = Set(viewModel.episodes.map { $0.id })
                    }) {
                        Label("Select All", systemImage: "checkmark.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.plexOrange)
                    .keyboardShortcut("a", modifiers: [.command])
                    
                    Button(action: {
                        selectedEpisodeIds.removeAll()
                    }) {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.plexTextSecondary)
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    
                    Spacer()
                    
                    Text("\(selectedEpisodeIds.count) selected")
                        .font(.system(size: 12))
                        .foregroundColor(.plexTextSecondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Divider()
                    .background(Color.plexLightGray)
                
                // Episodes List
                if viewModel.episodes.isEmpty {
                    Text("No episodes found")
                        .foregroundColor(.plexTextSecondary)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(viewModel.episodes, id: \.id) { episode in
                                EpisodeRowView(
                                    episode: episode,
                                    isSelected: selectedEpisodeIds.contains(episode.id)
                                ) {
                                    if selectedEpisodeIds.contains(episode.id) {
                                        selectedEpisodeIds.remove(episode.id)
                                    } else {
                                        selectedEpisodeIds.insert(episode.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: 300)
                }
                
                Divider()
                    .background(Color.plexLightGray)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Divider()
                        .background(Color.plexLightGray)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Manual Edit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.plexTextPrimary)
                            Spacer()
                            Text(editTargetEpisodeLabel)
                                .font(.system(size: 11))
                                .foregroundColor(.plexTextSecondary)
                        }

                        if let context = viewModel.lastTMDBContext() {
                            HStack(spacing: 8) {
                                Button {
                                    applyLastTMDBContext(context)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Use Last TMDB S\(context.season)E\(context.episode)")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(.plexTextPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.plexLightGray.opacity(0.45))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(PlainButtonStyle())

                                if let activeTMDBShowId {
                                    SmallUtilityButton(title: "Copy TMDB ID", icon: "doc.on.doc") {
                                        copyValueToClipboard(String(activeTMDBShowId), label: "TMDB show ID")
                                    }
                                }

                                if let episode = editTargetEpisode {
                                    SmallUtilityButton(title: "Copy Plex ID", icon: "number") {
                                        copyValueToClipboard(String(episode.id), label: "Plex episode ID")
                                    }
                                }

                                Spacer()
                            }
                        } else if let episode = editTargetEpisode {
                            HStack {
                                SmallUtilityButton(title: "Copy Plex ID", icon: "number") {
                                    copyValueToClipboard(String(episode.id), label: "Plex episode ID")
                                }
                                if let activeTMDBShowId {
                                    SmallUtilityButton(title: "Copy TMDB ID", icon: "doc.on.doc") {
                                        copyValueToClipboard(String(activeTMDBShowId), label: "TMDB show ID")
                                    }
                                }
                                Spacer()
                            }
                        }

                        HStack(spacing: 10) {
                            TextField("Episode title", text: $manualEditTitle)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color.plexLightGray)
                                .cornerRadius(6)

                            TextField("Season #", text: $manualEditSeasonNumber)
                                .frame(width: 90)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color.plexLightGray)
                                .cornerRadius(6)

                            TextField("Episode #", text: $manualEditEpisodeNumber)
                                .frame(width: 100)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color.plexLightGray)
                                .cornerRadius(6)

                            Spacer()
                        }

                        HStack(spacing: 10) {
                            TextField("TMDB Season #", text: $manualTMDBSeasonNumber)
                                .frame(width: 110)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color.plexLightGray)
                                .cornerRadius(6)

                            TextField("TMDB Episode #", text: $manualTMDBEpisodeNumber)
                                .frame(width: 120)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color.plexLightGray)
                                .cornerRadius(6)

                            TextField("TMDB URL or Show ID (optional)", text: $manualTMDBShowRef)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color.plexLightGray)
                                .cornerRadius(6)
                        }

                        HStack(spacing: 10) {
                            TextField("TMDB Start Code (e.g. S2E1)", text: $manualTMDBCode)
                                .frame(width: 220)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color.plexLightGray)
                                .cornerRadius(6)

                            TextField("Episode Count", text: $manualEpisodeCount)
                                .frame(width: 120)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color.plexLightGray)
                                .cornerRadius(6)

                            ActionButton(
                                title: "Auto Select",
                                icon: "checklist",
                                disabled: editTargetEpisode == nil
                            ) {
                                autoSelectEpisodeRange()
                            }
                            .keyboardShortcut("r", modifiers: [.command, .option])

                            Spacer()
                        }

                        HStack(spacing: 12) {
                            ActionButton(
                                title: "Save",
                                icon: "square.and.arrow.down",
                                disabled: editTargetEpisode == nil
                            ) {
                                guard let episode = editTargetEpisode else { return }
                                let parsedSeason = Int(manualEditSeasonNumber.trimmingCharacters(in: .whitespacesAndNewlines)) ?? episode.season_number
                                let parsedNumber = Int(manualEditEpisodeNumber.trimmingCharacters(in: .whitespacesAndNewlines)) ?? episode.episode_number
                                viewModel.updateEpisodeTitleAndNumber(
                                    episodeId: episode.id,
                                    title: manualEditTitle,
                                    seasonNumber: parsedSeason,
                                    episodeNumber: parsedNumber
                                )
                                selectedEpisodeIds.removeAll()
                            }
                            .keyboardShortcut("s", modifiers: [.command])

                            ActionButton(
                                title: "TV Metadata",
                                icon: "magnifyingglass",
                                disabled: viewModel.episodes.isEmpty
                            ) {
                                let orderedSeasonEpisodes = viewModel.episodes
                                    .sorted { lhs, rhs in
                                        if lhs.season_number == rhs.season_number {
                                            return lhs.episode_number < rhs.episode_number
                                        }
                                        return lhs.season_number < rhs.season_number
                                    }

                                guard let anchorEpisode = orderedSeasonEpisodes.first else { return }

                                let code = manualTMDBCode.trimmingCharacters(in: .whitespacesAndNewlines)
                                let parsedFromCode = PlexTVEditorViewModel.parseSeasonEpisodeCode(code)

                                let parsedTMDBSeason = parsedFromCode?.season
                                    ?? Int(manualTMDBSeasonNumber.trimmingCharacters(in: .whitespacesAndNewlines))
                                    ?? anchorEpisode.season_number
                                let parsedTMDBEpisode = parsedFromCode?.episode
                                    ?? Int(manualTMDBEpisodeNumber.trimmingCharacters(in: .whitespacesAndNewlines))
                                    ?? anchorEpisode.episode_number

                                let orderedIds: [Int]
                                if selectedEpisodeIds.isEmpty {
                                    orderedIds = orderedSeasonEpisodes.map { $0.id }
                                } else {
                                    orderedIds = orderedSeasonEpisodes
                                        .filter { selectedEpisodeIds.contains($0.id) }
                                        .map { $0.id }
                                }

                                viewModel.applyTMDBMetadataToEpisodes(
                                    episodeIds: orderedIds,
                                    tmdbStartSeasonNumber: parsedTMDBSeason,
                                    tmdbStartEpisodeNumber: parsedTMDBEpisode,
                                    tmdbShowIdOrURL: manualTMDBShowRef
                                )
                                manualEditSeasonNumber = String(parsedTMDBSeason)
                                manualEditEpisodeNumber = String(parsedTMDBEpisode)
                                manualTMDBSeasonNumber = String(parsedTMDBSeason)
                                manualTMDBEpisodeNumber = String(parsedTMDBEpisode)
                                selectedEpisodeIds.removeAll()
                            }
                            .keyboardShortcut("m", modifiers: [.command])

                            ActionButton(
                                title: "Smart Thumb Season",
                                icon: "photo.stack",
                                disabled: viewModel.episodes.isEmpty
                            ) {
                                let manualShowRefTrimmed = manualTMDBShowRef.trimmingCharacters(in: .whitespacesAndNewlines)
                                let resolvedShowRef = manualShowRefTrimmed.isEmpty ? nil : manualShowRefTrimmed

                                viewModel.smartRemapCurrentSeasonThumbnailsFromTMDB(tmdbShowIdOrURL: resolvedShowRef)
                                selectedEpisodeIds.removeAll()
                            }
                            .keyboardShortcut("t", modifiers: [.command, .option])

                            Button {
                                previewEpisodeId = editTargetEpisode?.id ?? viewModel.episodes.sorted { $0.episode_number < $1.episode_number }.first?.id
                                showPlexPreviewPanel = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "rectangle.on.rectangle")
                                        .font(.system(size: 12))
                                    Text("View Plex Panel")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(viewModel.episodes.isEmpty ? .plexTextSecondary : .black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(viewModel.episodes.isEmpty ? Color.plexLightGray.opacity(0.3) : Color.plexOrange)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(viewModel.episodes.isEmpty)
                            .keyboardShortcut("p", modifiers: [.command])

                            Spacer()
                        }

                        Text("TV Metadata applies TMDB metadata and numbering. Smart Thumb Season keeps the same season/episode numbers and refreshes artwork metadata only.")
                            .font(.system(size: 11))
                            .foregroundColor(.plexTextSecondary)
                    }
                    
                    Button(action: { showRemapPanel.toggle() }) {
                        HStack {
                            Image(systemName: showRemapPanel ? "chevron.down" : "chevron.right")
                            Text("Advanced: Remap from TMDB")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.plexOrange)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if showRemapPanel {
                        RemapPanel(
                            viewModel: viewModel,
                            selectedEpisodeIds: $selectedEpisodeIds,
                            remapSeasonNumber: $remapSeasonNumber,
                            remapEpisodeNumber: $remapEpisodeNumber,
                            remapUpdateTitle: $remapUpdateTitle,
                            remapUpdateAirDate: $remapUpdateAirDate,
                            remapUpdateSummary: $remapUpdateSummary,
                            remapUpdateYear: $remapUpdateYear,
                            remapRequireTMDBMatch: $remapRequireTMDBMatch,
                            remapCode: $remapCode
                        )
                    }
                }
                .padding()
            }
        }
        .onChange(of: selectedEpisodeIds) { _ in
            syncManualEpisodeEditor()
        }
        .onChange(of: viewModel.selectedSeasonId) { _ in
            selectedEpisodeIds.removeAll()
            autoSelectSeasonEpisodes = true
            syncManualEpisodeEditor()
        }
        .onChange(of: viewModel.episodes.map { $0.id }) { _ in
            guard autoSelectSeasonEpisodes else { return }
            selectedEpisodeIds = Set(viewModel.episodes.map { $0.id })
            autoSelectSeasonEpisodes = false
            syncManualEpisodeEditor()
        }
        .sheet(isPresented: $showPlexPreviewPanel) {
            PlexEpisodePanelPreview(
                episodes: viewModel.episodes,
                initialEpisodeId: previewEpisodeId,
                onClose: {
                    showPlexPreviewPanel = false
                }
            )
        }
    }

    private var editTargetEpisode: Episode? {
        let sortedCandidates = viewModel.episodes
            .filter { selectedEpisodeIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.season_number == rhs.season_number {
                    return lhs.episode_number < rhs.episode_number
                }
                return lhs.season_number < rhs.season_number
            }
        return sortedCandidates.first
    }

    private var editTargetEpisodeLabel: String {
        if selectedEpisodeIds.isEmpty {
            return "Select at least 1 episode"
        }
        if selectedEpisodeIds.count == 1 {
            return "Editing 1 episode"
        }
        return "\(selectedEpisodeIds.count) selected (TV Metadata uses all)"
    }

    private func syncManualEpisodeEditor() {
        guard let episode = editTargetEpisode else {
            manualEditTitle = ""
            manualEditSeasonNumber = ""
            manualEditEpisodeNumber = ""
            return
        }
        manualEditTitle = episode.name
        manualEditSeasonNumber = String(episode.season_number)
        manualEditEpisodeNumber = String(episode.episode_number)
        manualTMDBSeasonNumber = String(episode.season_number)
        manualTMDBEpisodeNumber = String(episode.episode_number)
    }

    private func autoSelectEpisodeRange() {
        guard let anchor = editTargetEpisode else {
            viewModel.statusMessage = "Select a starting episode first"
            return
        }

        let requestedCount = Int(manualEpisodeCount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        guard requestedCount > 0 else {
            viewModel.statusMessage = "Episode count must be greater than 0"
            return
        }

        let orderedEpisodes = viewModel.episodes
            .sorted { lhs, rhs in
                if lhs.season_number == rhs.season_number {
                    return lhs.episode_number < rhs.episode_number
                }
                return lhs.season_number < rhs.season_number
            }

        guard let anchorIndex = orderedEpisodes.firstIndex(where: { $0.id == anchor.id }) else {
            viewModel.statusMessage = "Could not locate starting episode"
            return
        }

        let endIndex = min(anchorIndex + requestedCount - 1, orderedEpisodes.count - 1)
        let selectedSlice = orderedEpisodes[anchorIndex...endIndex]
        selectedEpisodeIds = Set(selectedSlice.map { $0.id })

        viewModel.statusMessage = "Selected \(selectedSlice.count) episode(s) from S\(anchor.season_number)E\(anchor.episode_number)"
    }

    private var activeTMDBShowId: Int? {
        if let explicit = PlexTVEditorViewModel.parseTMDBShowId(manualTMDBShowRef) {
            return explicit
        }
        if let resolved = viewModel.lastResolvedTMDBShowId {
            return resolved
        }
        if let context = viewModel.lastTMDBContext() {
            return PlexTVEditorViewModel.parseTMDBShowId(context.showRef)
        }
        return nil
    }

    private func applyLastTMDBContext(_ context: (season: Int, episode: Int, showRef: String?)) {
        manualTMDBSeasonNumber = String(context.season)
        manualTMDBEpisodeNumber = String(context.episode)
        if let showRef = context.showRef, !showRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            manualTMDBShowRef = showRef
        }
        manualTMDBCode = "S\(context.season)E\(context.episode)"
        viewModel.statusMessage = "Loaded last TMDB context into manual fields"
    }

    private func copyValueToClipboard(_ value: String, label: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(value, forType: .string)
        viewModel.statusMessage = "Copied \(label): \(value)"
    }
}

// MARK: - Episode Row
struct EpisodeRowView: View {
    let episode: Episode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .plexOrange : .plexTextSecondary)

                EpisodeThumbnailView(urlString: episode.still_path)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("S\(episode.season_number)E\(episode.episode_number): \(episode.name)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.plexTextPrimary)
                        .lineLimit(1)
                    
                    Text("Aired: \(episode.air_date ?? "TBA")")
                        .font(.system(size: 11))
                        .foregroundColor(.plexTextSecondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.plexOrange.opacity(0.1) : Color.plexLightGray.opacity(0.3))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EpisodeThumbnailView: View {
    let urlString: String?
    let width: CGFloat
    let height: CGFloat

    @State private var image: NSImage?
    @State private var isLoading = false

    init(urlString: String?, width: CGFloat = 96, height: CGFloat = 54) {
        self.urlString = urlString
        self.width = width
        self.height = height
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.plexLightGray.opacity(0.6))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.plexTextSecondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: urlString) { _ in
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        image = nil

        guard let rawURL = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty,
              rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://"),
              let url = URL(string: rawURL) else {
            isLoading = false
            return
        }

        isLoading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let fetchedImage = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                self.image = fetchedImage
                self.isLoading = false
            }
        }.resume()
    }
}

struct PlexEpisodePanelPreview: View {
    let episodes: [Episode]
    let initialEpisodeId: Int?
    let onClose: () -> Void

    @State private var selectedEpisodeId: Int?

    private var orderedEpisodes: [Episode] {
        episodes.sorted { lhs, rhs in
            if lhs.season_number == rhs.season_number {
                return lhs.episode_number < rhs.episode_number
            }
            return lhs.season_number < rhs.season_number
        }
    }

    private var selectedEpisode: Episode? {
        if let selectedEpisodeId {
            return orderedEpisodes.first(where: { $0.id == selectedEpisodeId })
        }
        return orderedEpisodes.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TV Pre-Play Preview")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.plexTextPrimary)
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.plexOrange)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Color.plexMediumGray)

            GeometryReader { proxy in
                if let selectedEpisode {
                    // Scale hero media with window size so controls and episode rail stay visible.
                    let heroHeight = min(max(proxy.size.height * 0.5, 210), 350)
                    let heroWidth = max(proxy.size.width - 2, 300)

                    VStack(spacing: 0) {
                        ZStack(alignment: .bottomLeading) {
                            EpisodeThumbnailView(urlString: selectedEpisode.still_path, width: heroWidth, height: heroHeight)
                                .frame(maxWidth: .infinity)
                                .clipped()

                            LinearGradient(
                                colors: [Color.black.opacity(0.05), Color.black.opacity(0.88)],
                                startPoint: .top,
                                endPoint: .bottom
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                Text(selectedEpisode.name)
                                    .font(.system(size: 30, weight: .heavy))
                                    .foregroundColor(.white)
                                    .lineLimit(2)

                                HStack(spacing: 10) {
                                    Text("S\(selectedEpisode.season_number)E\(selectedEpisode.episode_number)")
                                    Text("•")
                                    Text(selectedEpisode.air_date ?? "Air date unknown")
                                    Text("•")
                                    Text("\(orderedEpisodes.count) in season")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.86))

                                HStack(spacing: 8) {
                                    PreplayActionPill(title: "Play", icon: "play.fill", emphasized: true)
                                    PreplayActionPill(title: "Mark Played", icon: "checkmark")
                                    PreplayActionPill(title: "More", icon: "ellipsis")
                                }
                            }
                            .padding(20)
                        }
                        .frame(height: heroHeight)

                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("In This Season")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.plexTextPrimary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(orderedEpisodes, id: \.id) { episode in
                                            Button {
                                                selectedEpisodeId = episode.id
                                            } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    EpisodeThumbnailView(urlString: episode.still_path, width: 200, height: 112)
                                                    Text("S\(episode.season_number)E\(episode.episode_number)")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(.plexOrange)
                                                    Text(episode.name)
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundColor(.plexTextPrimary)
                                                        .lineLimit(2)
                                                }
                                                .padding(8)
                                                .frame(width: 216, alignment: .leading)
                                                .background((selectedEpisodeId == episode.id) ? Color.plexOrange.opacity(0.14) : Color.plexLightGray.opacity(0.2))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }

                                Text(selectedEpisode.still_path ?? "No thumbnail URL on this episode")
                                    .font(.system(size: 11))
                                    .foregroundColor(.plexTextSecondary)
                                    .lineLimit(1)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                } else {
                    VStack {
                        Text("No episode selected")
                            .foregroundColor(.plexTextSecondary)
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            HStack {
                Spacer()
                Button("Close Panel") { onClose() }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.plexOrange)
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.plexMediumGray)
        }
        .frame(minWidth: 820, idealWidth: 960, minHeight: 560, idealHeight: 640)
        .background(Color.plexDarkGray)
        .onExitCommand {
            onClose()
        }
        .onAppear {
            selectedEpisodeId = initialEpisodeId ?? orderedEpisodes.first?.id
        }
    }
}

struct PreplayActionPill: View {
    let title: String
    let icon: String
    let emphasized: Bool

    init(title: String, icon: String, emphasized: Bool = false) {
        self.title = title
        self.icon = icon
        self.emphasized = emphasized
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(emphasized ? .black : .white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(emphasized ? Color.plexOrange : Color.white.opacity(0.14))
        .cornerRadius(16)
    }
}

// MARK: - Remap Panel
struct RemapPanel: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel
    @Binding var selectedEpisodeIds: Set<Int>
    @Binding var remapSeasonNumber: Int
    @Binding var remapEpisodeNumber: Int
    @Binding var remapUpdateTitle: Bool
    @Binding var remapUpdateAirDate: Bool
    @Binding var remapUpdateSummary: Bool
    @Binding var remapUpdateYear: Bool
    @Binding var remapRequireTMDBMatch: Bool
    @Binding var remapCode: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Target Season")
                        .font(.system(size: 11))
                        .foregroundColor(.plexTextSecondary)
                    TextField("", value: $remapSeasonNumber, formatter: NumberFormatter())
                        .frame(width: 60)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.plexLightGray)
                        .cornerRadius(4)
                }
                
                VStack(alignment: .leading) {
                    Text("Start Episode")
                        .font(.system(size: 11))
                        .foregroundColor(.plexTextSecondary)
                    TextField("", value: $remapEpisodeNumber, formatter: NumberFormatter())
                        .frame(width: 60)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.plexLightGray)
                        .cornerRadius(4)
                }
                
                Text("or")
                    .foregroundColor(.plexTextSecondary)
                    .padding(.top, 16)
                
                VStack(alignment: .leading) {
                    Text("Quick Code (e.g. S2E8)")
                        .font(.system(size: 11))
                        .foregroundColor(.plexTextSecondary)
                    TextField("S2E8", text: $remapCode)
                        .frame(width: 100)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.plexLightGray)
                        .cornerRadius(4)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Update Options")
                    .font(.system(size: 11))
                    .foregroundColor(.plexTextSecondary)
                
                HStack(spacing: 16) {
                    Toggle("Title", isOn: $remapUpdateTitle)
                    Toggle("Air Date", isOn: $remapUpdateAirDate)
                    Toggle("Summary", isOn: $remapUpdateSummary)
                    Toggle("Year", isOn: $remapUpdateYear)
                        .disabled(!remapUpdateAirDate)
                    Toggle("Strict Match", isOn: $remapRequireTMDBMatch)
                }
                .font(.system(size: 12))
                .toggleStyle(SwitchToggleStyle(tint: .plexOrange))
            }
            
            ActionButton(
                title: "Pull from TMDB & Apply",
                icon: "arrow.down.circle.fill",
                disabled: selectedEpisodeIds.isEmpty
            ) {
                let orderedIds = viewModel.episodes
                    .filter { selectedEpisodeIds.contains($0.id) }
                    .sorted { $0.episode_number < $1.episode_number }
                    .map { $0.id }
                
                let options = EpisodeRemapOptions(
                    updateTitle: remapUpdateTitle,
                    updateAirDate: remapUpdateAirDate,
                    updateSummary: remapUpdateSummary,
                    updateYearFromAirDate: remapUpdateYear,
                    updateThumbnail: true,
                    requireTMDBMatch: remapRequireTMDBMatch
                )
                
                let code = remapCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    if let parsed = PlexTVEditorViewModel.parseSeasonEpisodeCode(code) {
                        remapSeasonNumber = parsed.season
                        remapEpisodeNumber = parsed.episode
                    }
                    viewModel.remapEpisodesUsingCode(
                        episodeIds: orderedIds,
                        code: code,
                        options: options
                    )
                } else {
                    viewModel.remapEpisodesFromTMDB(
                        episodeIds: orderedIds,
                        targetSeasonNumber: remapSeasonNumber,
                        startEpisodeNumber: remapEpisodeNumber,
                        options: options
                    )
                }
                selectedEpisodeIds.removeAll()
            }
        }
        .padding(12)
        .background(Color.plexMediumGray)
        .cornerRadius(8)
    }
}

// MARK: - Movies Detail View
struct MoviesDetailView_New: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel
    @State private var selectedMovieIds: Set<Int> = []
    @State private var movieDate = Date()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionCard(title: "Movies", icon: "film") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Selection Controls
                        HStack {
                            Button(action: {
                                selectedMovieIds = Set(viewModel.movies.map { $0.id })
                            }) {
                                Label("Select All", systemImage: "checkmark.circle")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(.plexOrange)
                            
                            Button(action: {
                                selectedMovieIds.removeAll()
                            }) {
                                Label("Clear", systemImage: "xmark.circle")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(.plexTextSecondary)
                            
                            Spacer()
                            
                            Text("\(selectedMovieIds.count) selected")
                                .font(.system(size: 12))
                                .foregroundColor(.plexTextSecondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        Divider()
                            .background(Color.plexLightGray)
                        
                        // Movies List
                        if viewModel.movies.isEmpty {
                            Text("No movies found in database")
                                .foregroundColor(.plexTextSecondary)
                                .padding()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 4) {
                                    ForEach(viewModel.movies, id: \.id) { movie in
                                        MovieRowView(
                                            movie: movie,
                                            isSelected: selectedMovieIds.contains(movie.id)
                                        ) {
                                            if selectedMovieIds.contains(movie.id) {
                                                selectedMovieIds.remove(movie.id)
                                            } else {
                                                selectedMovieIds.insert(movie.id)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(maxHeight: 400)
                        }
                        
                        Divider()
                            .background(Color.plexLightGray)
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                ActionButton(
                                    title: "Change Release Date",
                                    icon: "calendar",
                                    disabled: selectedMovieIds.isEmpty
                                ) {
                                    // Show date picker inline
                                }
                                
                                ActionButton(
                                    title: "Detect 3D Format",
                                    icon: "eye.trianglebadge.exclamationmark",
                                    disabled: selectedMovieIds.isEmpty
                                ) {
                                    _ = viewModel.detect3DAndApplyMovies(forMovieIds: Array(selectedMovieIds))
                                    selectedMovieIds.removeAll()
                                }
                            }
                            
                            HStack {
                                DatePicker("", selection: $movieDate, displayedComponents: [.date])
                                    .labelsHidden()
                                
                                ActionButton(
                                    title: "Apply Date",
                                    icon: "checkmark",
                                    disabled: selectedMovieIds.isEmpty
                                ) {
                                    viewModel.applyDateToMovies(movieIds: Array(selectedMovieIds), date: movieDate)
                                    selectedMovieIds.removeAll()
                                }
                                
                                Spacer()
                            }
                        }
                        .padding()
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Movie Row
struct MovieRowView: View {
    let movie: PlexMovie
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .plexOrange : .plexTextSecondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.plexTextPrimary)
                        .lineLimit(1)
                    
                    if let year = movie.year {
                        Text("\(year)")
                            .font(.system(size: 11))
                            .foregroundColor(.plexTextSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.plexOrange.opacity(0.1) : Color.plexLightGray.opacity(0.3))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Settings View
struct SettingsView_New: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionCard(title: "Configuration", icon: "gearshape") {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingField(
                            label: "TMDB API Key",
                            hint: "Required for fetching TV show metadata",
                            isSecure: true,
                            text: $viewModel.tmdbApiKey
                        )
                        
                        SettingField(
                            label: "Plex SQLite Path",
                            hint: "Path to Plex SQLite binary",
                            isSecure: false,
                            text: $viewModel.plexSqlitePath
                        ) {
                            viewModel.browsePlexSqlite()
                        }
                        
                        SettingField(
                            label: "Plex Database Path",
                            hint: "Path to Plex database file",
                            isSecure: false,
                            text: $viewModel.plexDbPath
                        ) {
                            viewModel.browsePlexDatabase()
                        }
                        
                        Divider()
                            .background(Color.plexLightGray)
                        
                        HStack(spacing: 12) {
                            ActionButton(title: "Save Settings", icon: "square.and.arrow.down", disabled: false) {
                                viewModel.saveSettings()
                            }
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                            
                            ActionButton(title: "Test Connection", icon: "link", disabled: false) {
                                viewModel.testConnection()
                            }
                            .keyboardShortcut("k", modifiers: [.command, .option])
                            
                            ActionButton(title: "Reload Library", icon: "arrow.clockwise", disabled: false) {
                                viewModel.loadShows()
                                viewModel.loadMovies()
                            }
                            .keyboardShortcut("r", modifiers: [.command, .option])
                        }
                    }
                    .padding()
                }

                SectionCard(title: "Change Log", icon: "doc.plaintext") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Automatic batch log entries: \(viewModel.changeLogEntries.count)")
                            .font(.system(size: 12))
                            .foregroundColor(.plexTextSecondary)

                        if let latest = viewModel.changeLogEntries.first {
                            Text("Latest: \(latest.message)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.plexTextPrimary)
                                .lineLimit(2)
                        } else {
                            Text("No logged batch operations yet")
                                .font(.system(size: 12))
                                .foregroundColor(.plexTextSecondary)
                        }

                        HStack(spacing: 12) {
                            ActionButton(title: "Export CSV", icon: "tablecells", disabled: viewModel.changeLogEntries.isEmpty) {
                                viewModel.exportChangeLog(format: .csv)
                            }
                            .keyboardShortcut("e", modifiers: [.command, .option])

                            ActionButton(title: "Export JSON", icon: "curlybraces", disabled: viewModel.changeLogEntries.isEmpty) {
                                viewModel.exportChangeLog(format: .json)
                            }
                            .keyboardShortcut("j", modifiers: [.command, .option])

                            ActionButton(title: "Clear Log", icon: "trash", disabled: viewModel.changeLogEntries.isEmpty) {
                                viewModel.clearChangeLog()
                            }
                        }
                    }
                    .padding()
                }
                
                SectionCard(title: "About", icon: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Version", value: "1.0")
                        InfoRow(label: "Database", value: viewModel.plexDbPath.isEmpty ? "Not set" : "Connected")
                        InfoRow(label: "TV Shows", value: "\(viewModel.shows.count)")
                        InfoRow(label: "Movies", value: "\(viewModel.movies.count)")
                    }
                    .padding()
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Setting Field
struct SettingField: View {
    let label: String
    let hint: String
    let isSecure: Bool
    @Binding var text: String
    var browseAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.plexTextPrimary)
            
            Text(hint)
                .font(.system(size: 11))
                .foregroundColor(.plexTextSecondary)
            
            HStack {
                if isSecure {
                    SecureField("", text: $text)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(8)
                        .background(Color.plexLightGray)
                        .cornerRadius(6)
                } else {
                    TextField("", text: $text)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(8)
                        .background(Color.plexLightGray)
                        .cornerRadius(6)
                }
                
                if let action = browseAction {
                    Button(action: action) {
                        Text("Browse")
                            .font(.system(size: 12))
                            .foregroundColor(.plexOrange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.plexOrange.opacity(0.15))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.plexTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.plexTextPrimary)
        }
    }
}

// MARK: - Section Card
struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.plexOrange)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.plexTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.plexMediumGray)
            
            content
        }
        .background(Color.plexMediumGray.opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.plexLightGray, lineWidth: 1)
        )
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let icon: String
    let disabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(disabled ? .plexTextSecondary : .plexTextPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(disabled ? Color.plexLightGray.opacity(0.3) : Color.plexOrange)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
    }
}

struct SmallUtilityButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.plexTextPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.plexLightGray.opacity(0.5))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let icon: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.plexTextSecondary)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.plexTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
