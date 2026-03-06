import SwiftUI
import SQLite3

struct ContentView: View {
    @StateObject private var viewModel = PlexTVEditorViewModel()
    @State private var selectedTab: Int = 0
    @State private var selectedShowListId: Int?

    var body: some View {
        HSplitView {
            VStack {
                Picker("View", selection: $selectedTab) {
                    Text("Shows").tag(0)
                    Text("Seasons").tag(1)
                    Text("Episodes").tag(2)
                    Text("Movies").tag(3)
                    Text("Settings").tag(4)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 3 {
                    List(viewModel.movies, id: \.id) { movie in
                        HStack {
                            Text(movie.title)
                            Spacer()
                            if let year = movie.year {
                                Text("\(year)").foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    List(viewModel.shows, id: \.id) { show in
                        HStack {
                            Text(show.title)
                            Spacer()
                            if let year = show.year {
                                Text("\(year)").foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .background(selectedShowListId == show.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        .onTapGesture {
                            selectedShowListId = show.id
                            viewModel.selectShow(show)
                            if selectedTab == 0 {
                                selectedTab = 1
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 200)

            if selectedTab == 0 {
                ShowsDetailView(viewModel: viewModel)
            } else if selectedTab == 1 {
                SeasonsDetailView(viewModel: viewModel, selectedTab: $selectedTab)
            } else if selectedTab == 2 {
                EpisodesDetailView(viewModel: viewModel)
            } else if selectedTab == 3 {
                MoviesDetailView(viewModel: viewModel)
            } else {
                SettingsView(viewModel: viewModel)
            }
        }
        .onAppear {
            viewModel.loadShows()
            viewModel.loadMovies()
        }
    }
}

struct ShowsDetailView: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel
    @State private var searchText = ""
    @State private var showingDatePicker = false

    var body: some View {
        VStack {
            if let selectedShow = viewModel.shows.first(where: { $0.id == viewModel.selectedShowId }) {
                HStack {
                    Text("Selected Plex show: \(selectedShow.title)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }

            HStack {
                TextField("Search TMDB", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Search") {
                    viewModel.searchTMDB(query: searchText)
                }
            }
            .padding()

            List(viewModel.searchResults, id: \.id) { result in
                VStack(alignment: .leading) {
                    Text(result.name).font(.headline)
                    Text("First air: \(result.first_air_date ?? "N/A")").font(.caption)
                }
                .onTapGesture {
                    viewModel.selectedShow = result
                }
            }
        }
    }
}

struct SeasonsDetailView: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel
    @Binding var selectedTab: Int

    var body: some View {
        if viewModel.selectedShowId > 0 {
            List(viewModel.seasons, id: \.id) { season in
                Button(action: {
                    viewModel.selectSeason(season)
                    selectedTab = 2
                }) {
                    Text("Season \(season.season_number): \(season.episode_count) episodes")
                }
                .buttonStyle(PlainButtonStyle())
            }
        } else {
            Text("Select a show to view seasons")
        }
    }
}

struct EpisodesDetailView: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel
    @State private var selectedEpisodeIds: Set<Int> = []
    @State private var episodeDate = Date()
    @State private var remapSeasonNumber: Int = 1
    @State private var remapEpisodeNumber: Int = 1
    @State private var remapUpdateTitle = true
    @State private var remapUpdateAirDate = true
    @State private var remapUpdateSummary = true
    @State private var remapUpdateYear = true
    @State private var remapRequireTMDBMatch = false
    @State private var remapCode = ""

    var body: some View {
        if viewModel.selectedShowId > 0 {
            if viewModel.selectedSeasonId == 0 {
                VStack(alignment: .leading) {
                    Text("Select a season to view episodes")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
            } else if viewModel.episodes.isEmpty {
                VStack(alignment: .leading) {
                    Text("No episodes found for selected season")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
            } else {
            VStack(alignment: .leading) {
                HStack {
                    Button("Select All") {
                        selectedEpisodeIds = Set(viewModel.episodes.map { $0.id })
                    }
                    Button("Clear") {
                        selectedEpisodeIds.removeAll()
                    }
                    Spacer()
                    Text("\(selectedEpisodeIds.count) selected")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                List(viewModel.episodes, id: \.id) { episode in
                    HStack {
                        Image(systemName: selectedEpisodeIds.contains(episode.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedEpisodeIds.contains(episode.id) ? .accentColor : .secondary)
                        VStack(alignment: .leading) {
                            Text("S\(episode.season_number)E\(episode.episode_number): \(episode.name)").font(.headline)
                            Text("Aired: \(episode.air_date ?? "TBA")").font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedEpisodeIds.contains(episode.id) {
                            selectedEpisodeIds.remove(episode.id)
                        } else {
                            selectedEpisodeIds.insert(episode.id)
                        }
                    }
                }

                HStack {
                    DatePicker("New Air Date", selection: $episodeDate, displayedComponents: [.date])
                    Button("Apply To Selected") {
                        viewModel.applyDateToEpisodes(episodeIds: Array(selectedEpisodeIds), date: episodeDate)
                        selectedEpisodeIds.removeAll()
                    }
                    .disabled(selectedEpisodeIds.isEmpty)
                }
                .padding()
                
                HStack {
                    Button("Detect & Set 3D Edition") {
                        _ = viewModel.detect3DAndApply(forEpisodeIds: Array(selectedEpisodeIds))
                        selectedEpisodeIds.removeAll()
                    }
                    .disabled(selectedEpisodeIds.isEmpty)
                    Text("Scans file paths for 3D formats (FSBS, SBS, TAB, MVC, etc.)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Remap Season/Episode From TMDB")
                        .font(.headline)

                    HStack {
                        Text("Target Season")
                        TextField("Season", value: $remapSeasonNumber, formatter: NumberFormatter())
                            .frame(width: 80)

                        Text("Start Episode")
                        TextField("Episode", value: $remapEpisodeNumber, formatter: NumberFormatter())
                            .frame(width: 80)

                        Spacer()
                    }

                    HStack {
                        Text("Quick Code")
                        TextField("e.g. S2E8 or 2x8", text: $remapCode)
                            .frame(maxWidth: 220)
                        Text("If set, this overrides season/start episode fields")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    HStack {
                        Toggle("Title", isOn: $remapUpdateTitle)
                        Toggle("Air Date", isOn: $remapUpdateAirDate)
                        Toggle("Summary", isOn: $remapUpdateSummary)
                        Toggle("Year", isOn: $remapUpdateYear)
                            .disabled(!remapUpdateAirDate)
                        Toggle("Strict TMDB Match", isOn: $remapRequireTMDBMatch)
                    }

                    HStack {
                        Spacer()

                        Button("Pull From TV DB & Apply") {
                            let orderedIds = viewModel.episodes
                                .filter { selectedEpisodeIds.contains($0.id) }
                                .sorted { $0.episode_number < $1.episode_number }
                                .map { $0.id }

                            let options = EpisodeRemapOptions(
                                updateTitle: remapUpdateTitle,
                                updateAirDate: remapUpdateAirDate,
                                updateSummary: remapUpdateSummary,
                                updateYearFromAirDate: remapUpdateYear,
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
                        .disabled(selectedEpisodeIds.isEmpty)
                    }

                    Text("Select episodes, then either set season/start episode or enter a quick code like S2E8. Choose which metadata to update. Enable strict match to skip episodes with no TMDB match.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .onChange(of: viewModel.selectedSeasonId) { _ in
                selectedEpisodeIds.removeAll()
                if let firstEpisode = viewModel.episodes.first {
                    remapSeasonNumber = firstEpisode.season_number
                    remapEpisodeNumber = firstEpisode.episode_number
                }
            }
            }
        } else {
            Text("Select a show to view episodes")
        }
    }
}

struct MoviesDetailView: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel
    @State private var selectedMovieIds: Set<Int> = []
    @State private var movieDate = Date()

    var body: some View {
        VStack(alignment: .leading) {
            Text("Movies In Plex Database")
                .font(.headline)
                .padding(.bottom, 8)

            if viewModel.movies.isEmpty {
                Text("No movies found in selected Plex database")
                    .foregroundColor(.secondary)
            } else {
                HStack {
                    Button("Select All") {
                        selectedMovieIds = Set(viewModel.movies.map { $0.id })
                    }
                    Button("Clear") {
                        selectedMovieIds.removeAll()
                    }
                    Spacer()
                    Text("\(selectedMovieIds.count) selected")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                List(viewModel.movies, id: \.id) { movie in
                    HStack {
                        Image(systemName: selectedMovieIds.contains(movie.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedMovieIds.contains(movie.id) ? .accentColor : .secondary)
                        Text(movie.title)
                        Spacer()
                        if let year = movie.year {
                            Text("\(year)").foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedMovieIds.contains(movie.id) {
                            selectedMovieIds.remove(movie.id)
                        } else {
                            selectedMovieIds.insert(movie.id)
                        }
                    }
                }

                HStack {
                    DatePicker("New Release Date", selection: $movieDate, displayedComponents: [.date])
                    Button("Apply To Selected") {
                        viewModel.applyDateToMovies(movieIds: Array(selectedMovieIds), date: movieDate)
                        selectedMovieIds.removeAll()
                    }
                    .disabled(selectedMovieIds.isEmpty)
                }
                .padding()
                
                HStack {
                    Button("Detect & Set 3D Edition") {
                        _ = viewModel.detect3DAndApplyMovies(forMovieIds: Array(selectedMovieIds))
                        selectedMovieIds.removeAll()
                    }
                    .disabled(selectedMovieIds.isEmpty)
                    Text("Scans file paths for 3D formats (FSBS, SBS, TAB, MVC, etc.)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding()
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: PlexTVEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.headline)

            VStack(alignment: .leading) {
                Text("TMDB API Key").font(.caption).foregroundColor(.gray)
                SecureField("API Key", text: $viewModel.tmdbApiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            VStack(alignment: .leading) {
                Text("Plex SQLite Path").font(.caption).foregroundColor(.gray)
                HStack {
                    TextField("Path", text: $viewModel.plexSqlitePath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Browse...") {
                        viewModel.browsePlexSqlite()
                    }
                }
            }

            VStack(alignment: .leading) {
                Text("Plex Database Path").font(.caption).foregroundColor(.gray)
                HStack {
                    TextField("Path", text: $viewModel.plexDbPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Browse...") {
                        viewModel.browsePlexDatabase()
                    }
                }
            }

            HStack {
                Button(action: {
                    viewModel.saveSettings()
                }) {
                    Text("Save Settings")
                }
                
                Button(action: {
                    viewModel.testConnection()
                }) {
                    Text("Test Connection")
                }

                Button(action: {
                    viewModel.loadShows()
                    viewModel.loadMovies()
                }) {
                    Text("Reload Library")
                }
            }

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
