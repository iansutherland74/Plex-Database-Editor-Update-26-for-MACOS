import Foundation
import SQLite3
import Cocoa

struct EpisodeRemapOptions {
    // Fine-grained switches so one workflow can support metadata-only, artwork-only, or full remaps.
    let updateTitle: Bool
    let updateAirDate: Bool
    let updateSummary: Bool
    let updateYearFromAirDate: Bool
    let updateThumbnail: Bool
    let requireTMDBMatch: Bool
}

class PlexTVEditorViewModel: ObservableObject {
    @Published var shows: [PlexShow] = []
    @Published var movies: [PlexMovie] = []
    @Published var seasons: [Season] = []
    @Published var episodes: [Episode] = []
    @Published var searchResults: [TMDBShow] = []
    
    @Published var selectedShowId: Int = 0
    @Published var selectedSeasonId: Int = 0
    @Published var selectedShow: TMDBShow?
    @Published var editingEpisode: Episode?
    
    @Published var tmdbApiKey: String = ""
    @Published var plexSqlitePath: String = ""
    @Published var plexDbPath: String = ""
    @Published var statusMessage: String = ""

    private let defaultPlexSqlitePath = "/Applications/Plex Media Server.app/Contents/MacOS/Plex SQLite"
    private let legacyPlexSqlitePath = "/Applications/Plex Media Server.app/Contents/Resources/Support/Plex SQLite"
    private let legacyPlexDbPath = "~/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    private let placeholderPlexDbPath = "/Users/<there username>/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    
    private let tmdbClient = TMDBClient()
    private var lastTMDBStartSeasonNumber: Int?
    private var lastTMDBStartEpisodeNumber: Int?
    private var lastTMDBShowRef: String?

    private var defaultPlexDbPath: String {
        return "\(NSHomeDirectory())/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    }
    
    init() {
        loadSettings()
    }
    
    // MARK: - Plex Database Access
    
    func loadShows() {
        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        shows = manager.getShows()
        if shows.isEmpty {
            statusMessage = "No TV shows found in selected Plex database"
        } else {
            statusMessage = "Loaded \(shows.count) TV shows"
        }
    }

    func loadMovies() {
        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        movies = manager.getMovies()
    }

    func selectShow(_ show: PlexShow) {
        selectedShowId = show.id
        selectedSeasonId = 0

        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        let fetchedSeasons = manager.getSeasons(for: show.id)
        seasons = fetchedSeasons

        if let firstSeason = fetchedSeasons.first {
            selectedSeasonId = firstSeason.id
            episodes = manager.getEpisodes(for: firstSeason.id)
            statusMessage = "Loaded \(episodes.count) episodes from Season \(firstSeason.season_number)"
        } else {
            episodes = []
            statusMessage = "No seasons found for \(show.title)"
        }
    }
    
    func getSeasons(for showId: Int) {
        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        seasons = manager.getSeasons(for: showId)
    }
    
    func getEpisodes(for seasonId: Int) {
        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        episodes = manager.getEpisodes(for: seasonId)
    }

    func selectSeason(_ season: Season) {
        selectedSeasonId = season.id
        getEpisodes(for: season.id)
        statusMessage = "Loaded \(episodes.count) episodes from Season \(season.season_number)"
    }

    func applyDateToEpisodes(episodeIds: [Int], date: Date) {
        guard !episodeIds.isEmpty else {
            statusMessage = "Select at least one episode to update"
            return
        }

        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        _ = manager.createBackup()
        let updated = manager.updateMetadataDates(itemIds: episodeIds, date: date)

        if updated > 0 {
            statusMessage = "Updated \(updated) episode(s)"
            if selectedSeasonId > 0 {
                getEpisodes(for: selectedSeasonId)
            }
        } else {
            statusMessage = "No episodes were updated"
        }
    }

    func updateEpisodeTitleAndNumber(episodeId: Int, title: String, seasonNumber: Int, episodeNumber: Int) {
        guard selectedShowId > 0 else {
            statusMessage = "Select a show first"
            return
        }

        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            statusMessage = "Episode title cannot be empty"
            return
        }

        guard seasonNumber > 0 else {
            statusMessage = "Season number must be greater than 0"
            return
        }

        guard episodeNumber > 0 else {
            statusMessage = "Episode number must be greater than 0"
            return
        }

        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        guard let targetSeasonId = manager.getSeasonId(for: selectedShowId, seasonNumber: seasonNumber) else {
            statusMessage = "Season \(seasonNumber) does not exist for this show"
            return
        }

        guard manager.createBackup() != nil else {
            statusMessage = "Failed to create backup before update"
            return
        }

        let updated = manager.remapEpisode(
            episodeId: episodeId,
            seasonId: targetSeasonId,
            episodeNumber: episodeNumber,
            title: cleanedTitle,
            airDateUnix: nil,
            summary: nil,
            year: nil,
            thumbURL: nil,
            artURL: nil,
            bannerURL: nil,
            squareArtURL: nil
        )

        if updated {
            selectedSeasonId = targetSeasonId
            getSeasons(for: selectedShowId)
            getEpisodes(for: targetSeasonId)
            statusMessage = "Updated to S\(seasonNumber)E\(episodeNumber) with new title"

            // Keep episode and season artwork aligned when an episode is moved/changed.
            syncEpisodeAndSeasonArtworkFromTMDB(
                showId: selectedShowId,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                episodeId: episodeId,
                explicitShowRef: nil
            )
        } else {
            statusMessage = "Failed to update selected episode"
        }
    }

    func applyTMDBMetadataToEpisode(episodeId: Int, seasonNumber: Int, episodeNumber: Int) {
        applyTMDBMetadataToEpisodes(
            episodeIds: [episodeId],
            tmdbStartSeasonNumber: seasonNumber,
            tmdbStartEpisodeNumber: episodeNumber,
            tmdbShowIdOrURL: nil
        )
    }

    func applyTMDBMetadataToEpisodes(
        episodeIds: [Int],
        tmdbStartSeasonNumber: Int,
        tmdbStartEpisodeNumber: Int,
        tmdbShowIdOrURL: String?
    ) {
        let options = EpisodeRemapOptions(
            updateTitle: true,
            updateAirDate: true,
            updateSummary: true,
            updateYearFromAirDate: true,
            updateThumbnail: true,
            requireTMDBMatch: true
        )

        remapEpisodesFromTMDB(
            episodeIds: episodeIds,
            targetSeasonNumber: tmdbStartSeasonNumber,
            startEpisodeNumber: tmdbStartEpisodeNumber,
            options: options,
            tmdbShowIdOrURL: tmdbShowIdOrURL
        )
    }

    func remapEpisodeThumbnailsFromTMDB(
        episodeIds: [Int],
        tmdbStartSeasonNumber: Int,
        tmdbStartEpisodeNumber: Int,
        tmdbShowIdOrURL: String?
    ) {
        guard selectedShowId > 0 else {
            statusMessage = "Select a show first"
            return
        }
        guard !episodeIds.isEmpty else {
            statusMessage = "Select at least one episode"
            return
        }
        guard tmdbStartSeasonNumber > 0, tmdbStartEpisodeNumber > 0 else {
            statusMessage = "TMDB season and episode must be greater than 0"
            return
        }

        rememberTMDBContext(
            startSeasonNumber: tmdbStartSeasonNumber,
            startEpisodeNumber: tmdbStartEpisodeNumber,
            showRef: tmdbShowIdOrURL
        )

        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))

        guard let showTitle = shows.first(where: { $0.id == selectedShowId })?.title else {
            statusMessage = "Could not resolve selected show title"
            return
        }

        statusMessage = "Fetching TMDB thumbnails..."

        Task {
            do {
                guard let tmdbShowId = try await resolveTMDBShowId(
                    showTitle: showTitle,
                    tmdbSeasonNumber: tmdbStartSeasonNumber,
                    tmdbEpisodeNumber: tmdbStartEpisodeNumber,
                    explicitShowRef: tmdbShowIdOrURL
                ) else {
                    DispatchQueue.main.async {
                        self.statusMessage = "No TMDB show match found for \(showTitle)"
                    }
                    return
                }

                let sortedIds = episodeIds
                let backupPath = manager.createBackup()
                let showInfo = try? await tmdbClient.getShowInfo(showId: tmdbShowId, apiKey: tmdbApiKey)
                let showBackdropURL = Self.tmdbBackdropURLString(showInfo?.backdrop_path)

                var updatedCount = 0
                var tmdbMatchedCount = 0
                var missingStillCount = 0
                var skippedCount = 0

                // Cache season payloads so we do not re-fetch the same TMDB season repeatedly.
                var tmdbSeasonCache: [Int: [Int: TMDBEpisodeResponse]] = [:]
                var tmdbSeasonMaxEpisode: [Int: Int] = [:]
                var tmdbSeasonPosterURLCache: [Int: String] = [:]
                var cursorSeason = tmdbStartSeasonNumber
                var cursorEpisode = tmdbStartEpisodeNumber

                for episodeId in sortedIds {
                    var tmdbEpisode: TMDBEpisodeResponse?
                    var searchSteps = 0

                    // Cursor-style lookup lets us continue into next TMDB seasons when needed.
                    while tmdbEpisode == nil && searchSteps < 40 {
                        if tmdbSeasonCache[cursorSeason] == nil {
                            do {
                                let seasonData = try await tmdbClient.getSeason(
                                    showId: tmdbShowId,
                                    seasonNumber: cursorSeason,
                                    apiKey: tmdbApiKey
                                )
                                let episodeMap = Dictionary(uniqueKeysWithValues: (seasonData.episodes ?? []).map { ($0.episode_number, $0) })
                                tmdbSeasonCache[cursorSeason] = episodeMap
                                tmdbSeasonMaxEpisode[cursorSeason] = episodeMap.keys.max() ?? 0
                                if let posterURL = Self.tmdbSeasonPosterURLString(seasonData.poster_path) {
                                    tmdbSeasonPosterURLCache[cursorSeason] = posterURL
                                }
                            } catch {
                                tmdbSeasonCache[cursorSeason] = [:]
                                tmdbSeasonMaxEpisode[cursorSeason] = 0
                                tmdbSeasonPosterURLCache.removeValue(forKey: cursorSeason)
                            }
                        }

                        let currentMap = tmdbSeasonCache[cursorSeason] ?? [:]
                        if let found = currentMap[cursorEpisode] {
                            tmdbEpisode = found
                            cursorEpisode += 1
                        } else {
                            let maxEpisode = tmdbSeasonMaxEpisode[cursorSeason] ?? 0
                            if maxEpisode == 0 || cursorEpisode >= maxEpisode {
                                cursorSeason += 1
                                cursorEpisode = 1
                            } else {
                                cursorEpisode += 1
                            }
                        }

                        searchSteps += 1
                    }

                    guard let matchedEpisode = tmdbEpisode else {
                        skippedCount += 1
                        continue
                    }
                    tmdbMatchedCount += 1

                    guard let thumbURL = Self.tmdbStillURLString(matchedEpisode.still_path) else {
                        missingStillCount += 1
                        continue
                    }

                    let seasonPosterURL = tmdbSeasonPosterURLCache[matchedEpisode.season_number]

                    if manager.updateEpisodeThumbnail(
                        episodeId: episodeId,
                        thumbURL: thumbURL,
                        artURL: showBackdropURL,
                        bannerURL: showBackdropURL,
                        squareArtURL: seasonPosterURL
                    ) {
                        updatedCount += 1
                    } else {
                        skippedCount += 1
                    }
                }

                DispatchQueue.main.async {
                    self.getSeasons(for: self.selectedShowId)
                    if self.selectedSeasonId > 0 {
                        self.getEpisodes(for: self.selectedSeasonId)
                    }
                    let backupSuffix = backupPath != nil ? " Backup created." : ""
                    let missingStillSuffix = missingStillCount > 0 ? " Missing still image for \(missingStillCount)." : ""
                    self.statusMessage = "Thumbnail remap updated \(updatedCount) episode(s). TMDB matched \(tmdbMatchedCount). Skipped \(skippedCount).\(missingStillSuffix)\(backupSuffix)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Thumbnail remap failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func smartRemapCurrentSeasonThumbnailsFromTMDB(tmdbShowIdOrURL: String?) {
        guard selectedShowId > 0 else {
            statusMessage = "Select a show first"
            return
        }

        // Smart mode keeps Plex S/E numbering unchanged and only refreshes artwork fields.
        let sortedSeasonEpisodes = episodes
            .sorted { lhs, rhs in
                if lhs.season_number == rhs.season_number {
                    return lhs.episode_number < rhs.episode_number
                }
                return lhs.season_number < rhs.season_number
            }

        guard let firstEpisode = sortedSeasonEpisodes.first else {
            statusMessage = "No episodes found in this season"
            return
        }

        let targetSeasonNumber = firstEpisode.season_number
        let firstEpisodeNumber = firstEpisode.episode_number

        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))

        guard let showTitle = shows.first(where: { $0.id == selectedShowId })?.title else {
            statusMessage = "Could not resolve selected show title"
            return
        }

        statusMessage = "Fetching TMDB thumbnails for S\(targetSeasonNumber)..."

        Task {
            do {
                guard let tmdbShowId = try await resolveTMDBShowId(
                    showTitle: showTitle,
                    tmdbSeasonNumber: targetSeasonNumber,
                    tmdbEpisodeNumber: firstEpisodeNumber,
                    explicitShowRef: tmdbShowIdOrURL
                ) else {
                    DispatchQueue.main.async {
                        self.statusMessage = "No TMDB show match found for \(showTitle)"
                    }
                    return
                }

                rememberTMDBContext(
                    startSeasonNumber: targetSeasonNumber,
                    startEpisodeNumber: firstEpisodeNumber,
                    showRef: tmdbShowIdOrURL
                )

                let backupPath = manager.createBackup()
                let showInfo = try? await tmdbClient.getShowInfo(showId: tmdbShowId, apiKey: tmdbApiKey)
                let showBackdropURL = Self.tmdbBackdropURLString(showInfo?.backdrop_path)
                let seasonData = try await tmdbClient.getSeason(
                    showId: tmdbShowId,
                    seasonNumber: targetSeasonNumber,
                    apiKey: tmdbApiKey
                )

                let seasonPosterURL = Self.tmdbSeasonPosterURLString(seasonData.poster_path)
                var seasonPosterUpdated = false
                if let seasonPosterURL = seasonPosterURL,
                   let plexSeasonId = manager.getSeasonId(for: selectedShowId, seasonNumber: targetSeasonNumber) {
                    seasonPosterUpdated = manager.updateSeasonPoster(
                        seasonId: plexSeasonId,
                        posterURL: seasonPosterURL,
                        artURL: showBackdropURL,
                        bannerURL: showBackdropURL,
                        squareArtURL: seasonPosterURL
                    )
                }

                let tmdbByEpisode = Dictionary(uniqueKeysWithValues: (seasonData.episodes ?? []).map { ($0.episode_number, $0) })

                var updatedCount = 0
                var matchedCount = 0
                var missingStillCount = 0
                var skippedCount = 0

                for episode in sortedSeasonEpisodes {
                    guard let tmdbEpisode = tmdbByEpisode[episode.episode_number] else {
                        skippedCount += 1
                        continue
                    }

                    matchedCount += 1

                    guard let thumbURL = Self.tmdbStillURLString(tmdbEpisode.still_path) else {
                        missingStillCount += 1
                        continue
                    }

                    if manager.updateEpisodeThumbnail(
                        episodeId: episode.id,
                        thumbURL: thumbURL,
                        artURL: showBackdropURL,
                        bannerURL: showBackdropURL,
                        squareArtURL: seasonPosterURL
                    ) {
                        updatedCount += 1
                    } else {
                        skippedCount += 1
                    }
                }

                DispatchQueue.main.async {
                    self.getSeasons(for: self.selectedShowId)
                    if self.selectedSeasonId > 0 {
                        self.getEpisodes(for: self.selectedSeasonId)
                    }
                    let backupSuffix = backupPath != nil ? " Backup created." : ""
                    let missingStillSuffix = missingStillCount > 0 ? " Missing still image for \(missingStillCount)." : ""
                    let seasonPosterSuffix = seasonPosterUpdated ? " Season poster updated." : ""
                    self.statusMessage = "Smart season thumbnail remap updated \(updatedCount) episode(s). TMDB matched \(matchedCount). Skipped \(skippedCount).\(seasonPosterSuffix)\(missingStillSuffix)\(backupSuffix)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Smart season thumbnail remap failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func applyDateToMovies(movieIds: [Int], date: Date) {
        guard !movieIds.isEmpty else {
            statusMessage = "Select at least one movie to update"
            return
        }

        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        _ = manager.createBackup()
        let updated = manager.updateMetadataDates(itemIds: movieIds, date: date)

        if updated > 0 {
            statusMessage = "Updated \(updated) movie(s)"
            loadMovies()
        } else {
            statusMessage = "No movies were updated"
        }
    }

    func remapEpisodesFromTMDB(
        episodeIds: [Int],
        targetSeasonNumber: Int,
        startEpisodeNumber: Int,
        options: EpisodeRemapOptions,
        tmdbShowIdOrURL: String? = nil
    ) {
        guard selectedShowId > 0 else {
            statusMessage = "Select a show first"
            return
        }
        guard !episodeIds.isEmpty else {
            statusMessage = "Select at least one episode to remap"
            return
        }
        guard targetSeasonNumber > 0, startEpisodeNumber > 0 else {
            statusMessage = "Season and episode numbers must be greater than 0"
            return
        }

        rememberTMDBContext(
            startSeasonNumber: targetSeasonNumber,
            startEpisodeNumber: startEpisodeNumber,
            showRef: tmdbShowIdOrURL
        )

        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))

        guard let showTitle = shows.first(where: { $0.id == selectedShowId })?.title else {
            statusMessage = "Could not resolve selected show title"
            return
        }

        statusMessage = "Fetching episode data from TMDB..."

        Task {
            do {
                guard let tmdbShowId = try await resolveTMDBShowId(
                    showTitle: showTitle,
                    tmdbSeasonNumber: targetSeasonNumber,
                    tmdbEpisodeNumber: startEpisodeNumber,
                    explicitShowRef: tmdbShowIdOrURL
                ) else {
                    DispatchQueue.main.async {
                        self.statusMessage = "No TMDB show match found for \(showTitle)"
                    }
                    return
                }

                let sortedIds = episodeIds
                let backupPath = manager.createBackup()
                let showInfo = try? await tmdbClient.getShowInfo(showId: tmdbShowId, apiKey: tmdbApiKey)
                let showBackdropURL = Self.tmdbBackdropURLString(showInfo?.backdrop_path)

                var updatedCount = 0
                var tmdbMatchedCount = 0
                var skippedCount = 0
                var missingPlexSeasonCount = 0
                var createdPlexSeasonCount = 0
                var firstUpdatedSeasonId: Int?
                var plexSeasonIdCache: [Int: Int] = [:]
                var seasonPosterUpdatedSeasonIds: Set<Int> = []
                var seasonPosterUpdatedCount = 0

                // These caches avoid repeated TMDB calls while remapping long episode ranges.
                var tmdbSeasonCache: [Int: [Int: TMDBEpisodeResponse]] = [:]
                var tmdbSeasonMaxEpisode: [Int: Int] = [:]
                var tmdbSeasonPosterURLCache: [Int: String] = [:]
                var cursorSeason = targetSeasonNumber
                var cursorEpisode = startEpisodeNumber

                for (offset, episodeId) in sortedIds.enumerated() {
                    var tmdbEpisode: TMDBEpisodeResponse?
                    var searchSteps = 0

                    // Walk forward across season boundaries until we find a TMDB episode or hit a guard limit.
                    while tmdbEpisode == nil && searchSteps < 40 {
                        if tmdbSeasonCache[cursorSeason] == nil {
                            do {
                                let seasonData = try await tmdbClient.getSeason(
                                    showId: tmdbShowId,
                                    seasonNumber: cursorSeason,
                                    apiKey: tmdbApiKey
                                )
                                let episodeMap = Dictionary(uniqueKeysWithValues: (seasonData.episodes ?? []).map { ($0.episode_number, $0) })
                                tmdbSeasonCache[cursorSeason] = episodeMap
                                tmdbSeasonMaxEpisode[cursorSeason] = episodeMap.keys.max() ?? 0
                                if let posterURL = Self.tmdbSeasonPosterURLString(seasonData.poster_path) {
                                    tmdbSeasonPosterURLCache[cursorSeason] = posterURL
                                } else {
                                    tmdbSeasonPosterURLCache.removeValue(forKey: cursorSeason)
                                }
                            } catch {
                                tmdbSeasonCache[cursorSeason] = [:]
                                tmdbSeasonMaxEpisode[cursorSeason] = 0
                                tmdbSeasonPosterURLCache.removeValue(forKey: cursorSeason)
                            }
                        }

                        let currentMap = tmdbSeasonCache[cursorSeason] ?? [:]
                        if let found = currentMap[cursorEpisode] {
                            tmdbEpisode = found
                            cursorEpisode += 1
                        } else {
                            let maxEpisode = tmdbSeasonMaxEpisode[cursorSeason] ?? 0
                            if maxEpisode == 0 || cursorEpisode >= maxEpisode {
                                cursorSeason += 1
                                cursorEpisode = 1
                            } else {
                                cursorEpisode += 1
                            }
                        }

                        searchSteps += 1
                    }

                    if tmdbEpisode != nil {
                        tmdbMatchedCount += 1
                    }

                    if options.requireTMDBMatch && tmdbEpisode == nil {
                        skippedCount += 1
                        continue
                    }

                    let mappedSeasonNumber = tmdbEpisode?.season_number ?? targetSeasonNumber
                    let mappedEpisodeNumber = tmdbEpisode?.episode_number ?? (startEpisodeNumber + offset)

                    let mappedSeasonId: Int
                    if let cached = plexSeasonIdCache[mappedSeasonNumber] {
                        mappedSeasonId = cached
                    } else if let existing = manager.getSeasonId(for: selectedShowId, seasonNumber: mappedSeasonNumber) {
                        mappedSeasonId = existing
                        plexSeasonIdCache[mappedSeasonNumber] = existing
                    } else if let created = manager.ensureSeasonId(for: selectedShowId, seasonNumber: mappedSeasonNumber) {
                        mappedSeasonId = created
                        plexSeasonIdCache[mappedSeasonNumber] = created
                        createdPlexSeasonCount += 1
                    } else {
                        skippedCount += 1
                        missingPlexSeasonCount += 1
                        continue
                    }

                    if !seasonPosterUpdatedSeasonIds.contains(mappedSeasonId),
                       let seasonPosterURL = tmdbSeasonPosterURLCache[mappedSeasonNumber],
                       manager.updateSeasonPoster(
                           seasonId: mappedSeasonId,
                           posterURL: seasonPosterURL,
                           artURL: showBackdropURL,
                           bannerURL: showBackdropURL,
                           squareArtURL: seasonPosterURL
                       ) {
                        seasonPosterUpdatedSeasonIds.insert(mappedSeasonId)
                        seasonPosterUpdatedCount += 1
                    }

                    let mappedAirDateUnix = options.updateAirDate ? Self.unixFromDateString(tmdbEpisode?.air_date) : nil
                    let mappedYear = (options.updateAirDate && options.updateYearFromAirDate) ? Self.yearFromDateString(tmdbEpisode?.air_date) : nil
                    let mappedThumbURL = (options.updateThumbnail ? Self.tmdbStillURLString(tmdbEpisode?.still_path) : nil)
                    let mappedSeasonPosterURL = tmdbSeasonPosterURLCache[mappedSeasonNumber]

                    let remapped = manager.remapEpisode(
                        episodeId: episodeId,
                        seasonId: mappedSeasonId,
                        episodeNumber: mappedEpisodeNumber,
                        title: options.updateTitle ? tmdbEpisode?.name : nil,
                        airDateUnix: mappedAirDateUnix,
                        summary: options.updateSummary ? tmdbEpisode?.overview : nil,
                        year: mappedYear,
                        thumbURL: mappedThumbURL,
                        artURL: showBackdropURL,
                        bannerURL: showBackdropURL,
                        squareArtURL: mappedSeasonPosterURL
                    )

                    if remapped {
                        updatedCount += 1
                        if firstUpdatedSeasonId == nil {
                            firstUpdatedSeasonId = mappedSeasonId
                        }
                    }
                }

                DispatchQueue.main.async {
                    if let seasonToShow = firstUpdatedSeasonId {
                        self.selectedSeasonId = seasonToShow
                    }
                    self.getSeasons(for: self.selectedShowId)
                    if self.selectedSeasonId > 0 {
                        self.getEpisodes(for: self.selectedSeasonId)
                    }
                    let backupSuffix = backupPath != nil ? " Backup created." : ""
                    let missingSeasonSuffix = missingPlexSeasonCount > 0 ? " Missing Plex season for \(missingPlexSeasonCount)." : ""
                    let createdSeasonSuffix = createdPlexSeasonCount > 0 ? " Created Plex season(s): \(createdPlexSeasonCount)." : ""
                    let seasonPosterSuffix = seasonPosterUpdatedCount > 0 ? " Season poster(s) updated: \(seasonPosterUpdatedCount)." : ""
                    self.statusMessage = "Remapped \(updatedCount) episode(s). TMDB matched \(tmdbMatchedCount). Skipped \(skippedCount).\(createdSeasonSuffix)\(seasonPosterSuffix)\(missingSeasonSuffix)\(backupSuffix)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "TMDB remap failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func remapEpisodesUsingCode(
        episodeIds: [Int],
        code: String,
        options: EpisodeRemapOptions
    ) {
        guard let parsed = Self.parseSeasonEpisodeCode(code) else {
            statusMessage = "Invalid code. Use format like S2E8 or 2x8"
            return
        }

        remapEpisodesFromTMDB(
            episodeIds: episodeIds,
            targetSeasonNumber: parsed.season,
            startEpisodeNumber: parsed.episode,
            options: options
        )
    }

    func lastTMDBContext() -> (season: Int, episode: Int, showRef: String?)? {
        guard let season = lastTMDBStartSeasonNumber, let episode = lastTMDBStartEpisodeNumber else {
            return nil
        }
        return (season, episode, lastTMDBShowRef)
    }
    
    // MARK: - TMDB API

    private func resolveTMDBShowId(
        showTitle: String,
        tmdbSeasonNumber: Int,
        tmdbEpisodeNumber: Int,
        explicitShowRef: String?
    ) async throws -> Int? {
        // Prefer explicit user input first (raw ID or tmdb.org URL).
        if let parsedShowId = Self.parseTMDBShowId(explicitShowRef) {
            return parsedShowId
        }

        let searchResults = try await tmdbClient.searchShows(query: showTitle, apiKey: tmdbApiKey)
        guard !searchResults.isEmpty else {
            return nil
        }

        let ranked = searchResults.sorted {
            let lhsScore = Self.tmdbTitleScore(candidate: $0.name, target: showTitle)
            let rhsScore = Self.tmdbTitleScore(candidate: $1.name, target: showTitle)
            if lhsScore == rhsScore {
                return $0.id < $1.id
            }
            return lhsScore > rhsScore
        }

        // Validate top candidates against the requested season/episode to avoid similarly named shows.
        for candidate in ranked.prefix(6) {
            do {
                let seasonData = try await tmdbClient.getSeason(
                    showId: candidate.id,
                    seasonNumber: tmdbSeasonNumber,
                    apiKey: tmdbApiKey
                )
                let hasEpisode = (seasonData.episodes ?? []).contains { $0.episode_number == tmdbEpisodeNumber }
                if hasEpisode {
                    return candidate.id
                }
            } catch {
                continue
            }
        }

        return ranked.first?.id
    }
    
    func searchTMDB(query: String) {
        Task {
            do {
                searchResults = try await tmdbClient.searchShows(query: query, apiKey: tmdbApiKey)
            } catch {
                statusMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }
    
    func getSeasonDetails(showId: Int, seasonNumber: Int) {
        Task {
            do {
                let seasonResponse = try await tmdbClient.getSeason(showId: showId, seasonNumber: seasonNumber, apiKey: tmdbApiKey)
                DispatchQueue.main.async {
                    self.seasons = [Season(id: -1, season_number: seasonResponse.season_number, episode_count: seasonResponse.episodes?.count ?? 0)]
                }
            } catch {
                statusMessage = "Failed to load season: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Settings
    
    func loadSettings() {
        var migratedSettings = false

        if let data = UserDefaults.standard.data(forKey: "PlexTVEditorSettings"),
           let settings = try? JSONDecoder().decode(Settings.self, from: data) {
            self.tmdbApiKey = settings.tmdbApiKey
            if settings.plexSqlitePath.isEmpty || settings.plexSqlitePath == legacyPlexSqlitePath {
                self.plexSqlitePath = defaultPlexSqlitePath
                migratedSettings = true
            } else {
                self.plexSqlitePath = settings.plexSqlitePath
            }

            let normalizedDbPath = normalizePlexDbPath(settings.plexDbPath)
            if normalizedDbPath.isEmpty {
                self.plexDbPath = defaultPlexDbPath
                migratedSettings = true
            } else {
                self.plexDbPath = normalizedDbPath
                if normalizedDbPath != settings.plexDbPath {
                    migratedSettings = true
                }
            }
        } else {
            // Set defaults
            self.tmdbApiKey = "fd51c863ad45547eb19ba9f70f3ac4f0"
            self.plexSqlitePath = defaultPlexSqlitePath
            self.plexDbPath = defaultPlexDbPath
        }

        if migratedSettings {
            saveSettings()
        }
    }
    
    func saveSettings() {
        let normalizedDbPath = normalizePlexDbPath(plexDbPath)
        if !normalizedDbPath.isEmpty {
            self.plexDbPath = normalizedDbPath
        }

        let settings = Settings(
            tmdbApiKey: tmdbApiKey,
            plexSqlitePath: plexSqlitePath,
            plexDbPath: self.plexDbPath
        )
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "PlexTVEditorSettings")
            statusMessage = "Settings saved successfully"
        }
    }
    
    func testConnection() {
        // Test Plex database
        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        let testShows = manager.getShows()
        
        if !testShows.isEmpty {
            statusMessage = "✓ Plex connection successful (\(testShows.count) shows found)"
        } else {
            statusMessage = "✗ Could not find shows in Plex database"
        }
    }
    
    // MARK: - File Selection
    
    func browsePlexSqlite() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = [""]  // Allow all files
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Plex SQLite Executable"
        panel.message = "Find the Plex SQLite binary (usually in /Applications/Plex Media Server.app)"
        
        if panel.runModal() == .OK, let url = panel.url {
            self.plexSqlitePath = url.path
            statusMessage = "Plex SQLite path updated"
        }
    }
    
    func browsePlexDatabase() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["db"]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Plex Media Server Database"
        panel.message = "Select com.plexapp.plugins.library.db"
        panel.directoryURL = URL(fileURLWithPath: (defaultPlexDbPath as NSString).deletingLastPathComponent)
        
        if panel.runModal() == .OK, let url = panel.url {
            self.plexDbPath = url.path
            statusMessage = "Plex database path updated"
        }
    }
    
    // MARK: - Utilities
    
    private func expandPath(_ path: String) -> String {
        return NSString(string: path).expandingTildeInPath
    }

    private func normalizePlexDbPath(_ path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.isEmpty {
            return ""
        }

        if trimmedPath == legacyPlexDbPath || trimmedPath == placeholderPlexDbPath {
            return defaultPlexDbPath
        }

        if trimmedPath.contains("<there username>") {
            return defaultPlexDbPath
        }

        return expandPath(trimmedPath)
    }

    func detect3DAndApply(forEpisodeIds episodeIds: [Int]) -> (detected: Int, updated: Int) {
        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        var detectedCount = 0
        var updatedCount = 0
        
        for episodeId in episodeIds {
            guard let filePath = manager.getFilePath(forItemId: episodeId) else {
                continue
            }
            
            if let format3D = PlexDatabaseManager.detect3DFormat(fromPath: filePath) {
                detectedCount += 1
                if manager.updateEdition(itemId: episodeId, edition: format3D) {
                    updatedCount += 1
                }
            }
        }
        
        if updatedCount > 0 {
            getEpisodes(for: selectedSeasonId)
            statusMessage = "Detected \(detectedCount) 3D files, updated \(updatedCount) editions"
        } else if detectedCount > 0 {
            statusMessage = "Detected \(detectedCount) 3D files, but update failed"
        } else {
            statusMessage = "No 3D formats detected in selected files"
        }
        
        return (detectedCount, updatedCount)
    }
    
    func detect3DAndApplyMovies(forMovieIds movieIds: [Int]) -> (detected: Int, updated: Int) {
        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        var detectedCount = 0
        var updatedCount = 0
        
        for movieId in movieIds {
            guard let filePath = manager.getFilePath(forItemId: movieId) else {
                continue
            }
            
            if let format3D = PlexDatabaseManager.detect3DFormat(fromPath: filePath) {
                detectedCount += 1
                if manager.updateEdition(itemId: movieId, edition: format3D) {
                    updatedCount += 1
                }
            }
        }
        
        if updatedCount > 0 {
            loadMovies()
            statusMessage = "Detected \(detectedCount) 3D files, updated \(updatedCount) editions"
        } else if detectedCount > 0 {
            statusMessage = "Detected \(detectedCount) 3D files, but update failed"
        } else {
            statusMessage = "No 3D formats detected in selected files"
        }
        
        return (detectedCount, updatedCount)
    }

    private static func unixFromDateString(_ dateString: String?) -> Int64? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return nil }
        return Int64(date.timeIntervalSince1970)
    }

    private static func yearFromDateString(_ dateString: String?) -> Int? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }
        let parts = dateString.split(separator: "-")
        guard let first = parts.first, let year = Int(first) else { return nil }
        return year
    }

    private static func tmdbStillURLString(_ stillPath: String?) -> String? {
        guard let sourceURL = tmdbStillSourceURLString(stillPath) else { return nil }
        return plexProxyImageURLString(sourceURL: sourceURL, width: 480, height: 270)
    }

    private static func tmdbSeasonPosterURLString(_ posterPath: String?) -> String? {
        guard let sourceURL = tmdbPosterSourceURLString(posterPath) else { return nil }
        return plexProxyImageURLString(sourceURL: sourceURL, width: 300, height: 450)
    }

    private static func tmdbBackdropURLString(_ backdropPath: String?) -> String? {
        guard let sourceURL = tmdbBackdropSourceURLString(backdropPath) else { return nil }
        return plexProxyImageURLString(sourceURL: sourceURL, width: 1280, height: 720)
    }

    private static func tmdbStillSourceURLString(_ stillPath: String?) -> String? {
        guard let stillPath = stillPath?.trimmingCharacters(in: .whitespacesAndNewlines), !stillPath.isEmpty else {
            return nil
        }
        if stillPath.hasPrefix("http://") || stillPath.hasPrefix("https://") {
            return stillPath
        }
        return "https://image.tmdb.org/t/p/original\(stillPath)"
    }

    private static func tmdbPosterSourceURLString(_ posterPath: String?) -> String? {
        guard let posterPath = posterPath?.trimmingCharacters(in: .whitespacesAndNewlines), !posterPath.isEmpty else {
            return nil
        }
        if posterPath.hasPrefix("http://") || posterPath.hasPrefix("https://") {
            return posterPath
        }
        return "https://image.tmdb.org/t/p/original\(posterPath)"
    }

    private static func tmdbBackdropSourceURLString(_ backdropPath: String?) -> String? {
        guard let backdropPath = backdropPath?.trimmingCharacters(in: .whitespacesAndNewlines), !backdropPath.isEmpty else {
            return nil
        }
        if backdropPath.hasPrefix("http://") || backdropPath.hasPrefix("https://") {
            return backdropPath
        }
        return "https://image.tmdb.org/t/p/original\(backdropPath)"
    }

    private static func plexProxyImageURLString(sourceURL: String, width: Int, height: Int) -> String {
        var components = URLComponents(string: "https://images.plex.tv/photo")
        components?.queryItems = [
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "1"),
            URLQueryItem(name: "url", value: sourceURL)
        ]

        return components?.url?.absoluteString ?? sourceURL
    }

    private func syncEpisodeAndSeasonArtworkFromTMDB(
        showId: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        episodeId: Int,
        explicitShowRef: String?
    ) {
        // Best-effort background sync after manual edits so artwork stays consistent without blocking UI actions.
        guard seasonNumber > 0, episodeNumber > 0 else { return }

        let manager = PlexDatabaseManager(dbPath: expandPath(plexDbPath), plexSqlitePath: expandPath(plexSqlitePath))
        guard let showTitle = shows.first(where: { $0.id == showId })?.title else { return }

        Task {
            do {
                guard let tmdbShowId = try await resolveTMDBShowId(
                    showTitle: showTitle,
                    tmdbSeasonNumber: seasonNumber,
                    tmdbEpisodeNumber: episodeNumber,
                    explicitShowRef: explicitShowRef
                ) else {
                    return
                }

                let seasonData = try await tmdbClient.getSeason(
                    showId: tmdbShowId,
                    seasonNumber: seasonNumber,
                    apiKey: tmdbApiKey
                )

                let showInfo = try? await tmdbClient.getShowInfo(showId: tmdbShowId, apiKey: tmdbApiKey)
                let showBackdropURL = Self.tmdbBackdropURLString(showInfo?.backdrop_path)

                var seasonPosterUpdated = false
                if let seasonPosterURL = Self.tmdbSeasonPosterURLString(seasonData.poster_path),
                   let seasonId = manager.getSeasonId(for: showId, seasonNumber: seasonNumber) {
                    seasonPosterUpdated = manager.updateSeasonPoster(
                        seasonId: seasonId,
                        posterURL: seasonPosterURL,
                        artURL: showBackdropURL,
                        bannerURL: showBackdropURL,
                        squareArtURL: seasonPosterURL
                    )
                }

                var episodeThumbUpdated = false
                if let tmdbEpisode = (seasonData.episodes ?? []).first(where: { $0.episode_number == episodeNumber }),
                   let episodeThumbURL = Self.tmdbStillURLString(tmdbEpisode.still_path) {
                    episodeThumbUpdated = manager.updateEpisodeThumbnail(
                        episodeId: episodeId,
                        thumbURL: episodeThumbURL,
                        artURL: showBackdropURL,
                        bannerURL: showBackdropURL,
                        squareArtURL: Self.tmdbSeasonPosterURLString(seasonData.poster_path)
                    )
                }

                DispatchQueue.main.async {
                    self.getSeasons(for: showId)
                    if self.selectedSeasonId > 0 {
                        self.getEpisodes(for: self.selectedSeasonId)
                    }
                    if episodeThumbUpdated || seasonPosterUpdated {
                        var syncedParts: [String] = []
                        if episodeThumbUpdated { syncedParts.append("episode thumbnail") }
                        if seasonPosterUpdated { syncedParts.append("season poster") }
                        self.statusMessage = "Artwork synced: \(syncedParts.joined(separator: " + "))"
                    }
                }
            } catch {
                // Silent best-effort sync to avoid interrupting manual edit workflow.
            }
        }
    }

    private func rememberTMDBContext(startSeasonNumber: Int, startEpisodeNumber: Int, showRef: String?) {
        // Used by later actions so users do not need to re-enter the same TMDB mapping context each time.
        guard startSeasonNumber > 0, startEpisodeNumber > 0 else { return }
        lastTMDBStartSeasonNumber = startSeasonNumber
        lastTMDBStartEpisodeNumber = startEpisodeNumber
        if let normalizedShowRef = Self.normalizedTMDBShowRef(showRef) {
            lastTMDBShowRef = normalizedShowRef
        }
    }

    private static func normalizedTMDBShowRef(_ input: String?) -> String? {
        guard let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func parseSeasonEpisodeCode(_ input: String) -> (season: Int, episode: Int)? {
        // Accept common shorthand formats like S2E8 and 2x8.
        let compact = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        guard !compact.isEmpty else { return nil }

        let patterns = ["^s(\\d{1,3})e(\\d{1,3})$", "^(\\d{1,3})x(\\d{1,3})$"]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: compact.utf16.count)
            guard let match = regex.firstMatch(in: compact, options: [], range: range), match.numberOfRanges == 3 else { continue }

            let seasonRange = match.range(at: 1)
            let episodeRange = match.range(at: 2)
            if let sRange = Range(seasonRange, in: compact),
               let eRange = Range(episodeRange, in: compact),
               let season = Int(compact[sRange]),
               let episode = Int(compact[eRange]),
               season > 0,
               episode > 0 {
                return (season, episode)
            }
        }

        return nil
    }

    static func parseTMDBShowId(_ input: String?) -> Int? {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return nil
        }

        if let directId = Int(input), directId > 0 {
            return directId
        }

        let pattern = "/tv/(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(location: 0, length: input.utf16.count)
        guard let match = regex.firstMatch(in: input, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }

        let idRange = match.range(at: 1)
        guard let swiftRange = Range(idRange, in: input), let id = Int(input[swiftRange]), id > 0 else {
            return nil
        }

        return id
    }

    private static func tmdbTitleScore(candidate: String, target: String) -> Int {
        let normalizedCandidate = normalizeTitle(candidate)
        let normalizedTarget = normalizeTitle(target)

        if normalizedCandidate == normalizedTarget {
            return 100
        }
        if normalizedCandidate.contains(normalizedTarget) || normalizedTarget.contains(normalizedCandidate) {
            return 70
        }

        let candidateTokens = Set(normalizedCandidate.split(separator: " ").map(String.init))
        let targetTokens = Set(normalizedTarget.split(separator: " ").map(String.init))
        let overlap = candidateTokens.intersection(targetTokens).count
        return overlap
    }

    private static func normalizeTitle(_ value: String) -> String {
        let lower = value.lowercased()
        let parts = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Data Models

struct PlexShow: Codable {
    let id: Int
    let title: String
    let year: Int?
}

struct PlexMovie: Codable {
    let id: Int
    let title: String
    let year: Int?
}

struct Season: Codable {
    let id: Int
    let season_number: Int
    let episode_count: Int
}

struct Episode: Codable, Identifiable {
    let id: Int
    let season_number: Int
    let episode_number: Int
    let name: String
    let air_date: String?
    let still_path: String?
}

struct TMDBShow: Codable, Identifiable {
    let id: Int
    let name: String
    let first_air_date: String?
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
}

struct Settings: Codable {
    let tmdbApiKey: String
    let plexSqlitePath: String
    let plexDbPath: String
}
