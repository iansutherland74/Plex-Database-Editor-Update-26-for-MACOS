import Foundation
import SQLite3
import Cocoa
import UserNotifications

struct PlexServerIdentity {
    let friendlyName: String
    let version: String
    let machineIdentifier: String
}

struct PlexLibrarySection: Identifiable {
    let id: String
    let key: String
    let title: String
    let type: String
}

enum PlexSectionActionKind: String {
    case refresh = "Refresh"
    case analyze = "Analyze"
    case emptyTrash = "Empty Trash"

    var pathComponent: String {
        switch self {
        case .refresh:
            return "refresh"
        case .analyze:
            return "analyze"
        case .emptyTrash:
            return "emptyTrash"
        }
    }
}

struct PlexSectionActionHistoryEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let sectionKey: String
    let sectionLabel: String
    let actionLabel: String
    let outcome: String
}

struct PlexServerProfile: Identifiable, Codable {
    let id: UUID
    let name: String
    let serverURL: String
    let token: String
}

struct PlexSectionActionPreset: Identifiable, Codable {
    let id: UUID
    let name: String
    let sectionType: String
    let includeRefresh: Bool
    let includeAnalyze: Bool
    let includeEmptyTrash: Bool
    let runOnAllSections: Bool
}

struct PlexCapabilities: Codable {
    var canRefreshSection: Bool
    var canAnalyzeSection: Bool
    var canEmptyTrashSection: Bool
    var canCancelSectionJob: Bool
    var canAnalyzeItem: Bool

    static let unknown = PlexCapabilities(
        canRefreshSection: true,
        canAnalyzeSection: true,
        canEmptyTrashSection: true,
        canCancelSectionJob: true,
        canAnalyzeItem: true
    )
}

struct PlexSectionJobMonitorItem: Identifiable {
    let id: UUID
    let sectionKey: String
    let sectionLabel: String
    let actionLabel: String
    let startedAt: Date
    var finishedAt: Date?
    var status: String
}

struct PlexTrashPreviewRow: Identifiable {
    let id = UUID()
    let sectionKey: String
    let sectionLabel: String
    let trashCount: Int
}

enum SchedulerFrequency: String, Codable, CaseIterable {
    case daily
    case weekly
}

enum SchedulerScope: String, Codable, CaseIterable {
    case tv
    case movie
    case both
}

private final class PlexIdentityXMLParserDelegate: NSObject, XMLParserDelegate {
    var identity: PlexServerIdentity?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "MediaContainer" else { return }

        let name = attributeDict["friendlyName"] ?? "Unknown"
        let version = attributeDict["version"] ?? "Unknown"
        let machineId = attributeDict["machineIdentifier"] ?? "Unknown"
        identity = PlexServerIdentity(friendlyName: name, version: version, machineIdentifier: machineId)
    }
}

private final class PlexSectionsXMLParserDelegate: NSObject, XMLParserDelegate {
    var sections: [PlexLibrarySection] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "Directory" else { return }

        guard let key = attributeDict["key"],
              let title = attributeDict["title"],
              let type = attributeDict["type"] else {
            return
        }

        sections.append(
            PlexLibrarySection(
                id: key,
                key: key,
                title: title,
                type: type
            )
        )
    }
}

private final class PlexMediaContainerSizeParserDelegate: NSObject, XMLParserDelegate {
    var size: Int?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "MediaContainer" else { return }
        if let sizeText = attributeDict["size"], let parsed = Int(sizeText) {
            size = parsed
        }
    }
}

struct EpisodeRemapOptions {
    // Fine-grained switches so one workflow can support metadata-only, artwork-only, or full remaps.
    let updateTitle: Bool
    let updateAirDate: Bool
    let updateSummary: Bool
    let updateYearFromAirDate: Bool
    let updateThumbnail: Bool
    let requireTMDBMatch: Bool
}

enum ChangeLogExportFormat {
    case csv
    case json

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        }
    }
}

enum DryRunExportFormat {
    case csv
    case json

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        }
    }
}

enum SectionActionHistoryExportFormat {
    case csv
    case json

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        }
    }
}

struct ChangeLogEntry: Codable, Identifiable {
    let id: UUID
    let timestampISO8601: String
    let message: String
    let showId: Int?
    let showTitle: String?
    let seasonId: Int?
    let tmdbShowId: Int?
    let tmdbContext: String?
}

struct DryRunDiffRow: Encodable, Identifiable {
    let id = UUID()
    let episodeId: Int
    let currentCode: String
    let mappedCode: String
    let currentTitle: String
    let mappedTitle: String
    let currentAirDate: String
    let mappedAirDate: String
    let note: String
}

struct BackupFileItem: Identifiable {
    let id: String
    let path: String
    let fileName: String
    let modifiedAt: Date
    let sizeBytes: Int64
}

// View model state is UI-owned; we explicitly opt into Sendable to avoid noisy
// closure-capture warnings from Task/DispatchQueue boundaries.
final class PlexTVEditorViewModel: ObservableObject, @unchecked Sendable {
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
    @Published var plexServerURL: String = ""
    @Published var plexToken: String = ""
    @Published var plexConnectionSummary: String = "Not tested"
    @Published var plexServerName: String = ""
    @Published var plexServerVersion: String = ""
    @Published var plexServerMachineIdentifier: String = ""
    @Published var isTestingPlexConnection = false
    @Published var plexLibrarySections: [PlexLibrarySection] = []
    @Published var selectedPlexTVSectionKey: String = ""
    @Published var selectedPlexMovieSectionKey: String = ""
    @Published var isLoadingPlexSections = false
    @Published var isRefreshingPlexSection = false
    @Published var isAnalyzingPlexSection = false
    @Published var isEmptyingPlexSection = false
    @Published var isCancellingPlexSectionJob = false
    @Published var isRunningPlexSectionMaintenance = false
    @Published var isRunningBulkPlexSectionMaintenance = false
    @Published var isRetryingFailedPlexSectionActions = false
    @Published var bulkPlexSectionMaintenanceProgress: String = ""
    @Published var isPreviewingSectionTrash = false
    @Published var sectionTrashPreviewRows: [PlexTrashPreviewRow] = []
    @Published var plexServerProfiles: [PlexServerProfile] = []
    @Published var selectedPlexProfileId: String = ""
    @Published var plexActionPresets: [PlexSectionActionPreset] = []
    @Published var selectedPlexPresetId: String = ""
    @Published var sectionActionMaxRetries: Int = 1
    @Published var sectionActionRetryDelaySeconds: Double = 0.5
    @Published var schedulerEnabled = false
    @Published var schedulerFrequency: SchedulerFrequency = .daily
    @Published var schedulerScope: SchedulerScope = .both
    @Published var schedulerLastRunAt: Date?
    @Published var schedulerNextRunAt: Date?
    @Published var notificationsEnabled = false
    @Published var capabilitySummary: String = "Unknown"
    @Published var plexCapabilities: PlexCapabilities = .unknown
    @Published var activeSectionJobs: [PlexSectionJobMonitorItem] = []
    @Published var completedSectionJobs: [PlexSectionJobMonitorItem] = []
    @Published var lastQueuedPlexSectionKey: String = ""
    @Published var lastQueuedPlexSectionLabel: String = ""
    @Published var lastQueuedPlexSectionAction: String = ""
    @Published var plexSectionActionHistory: [PlexSectionActionHistoryEntry] = []
    @Published var statusMessage: String = "" {
        didSet {
            logBatchStatusIfNeeded(statusMessage)
        }
    }
    @Published var changeLogEntries: [ChangeLogEntry] = []
    @Published var recentShowIds: [Int] = []
    @Published var lastResolvedTMDBShowId: Int?
    @Published var dryRunRows: [DryRunDiffRow] = []
    @Published var dryRunSummary: String = ""
    @Published var isDryRunLoading = false
    @Published var backupFiles: [BackupFileItem] = []

    private var lastDryRunEpisodeIds: [Int] = []
    private var lastDryRunSeasonNumber: Int?
    private var lastDryRunEpisodeNumber: Int?
    private var lastDryRunShowRef: String?
    private var schedulerTimer: Timer?

    private let defaultPlexSqlitePath = "/Applications/Plex Media Server.app/Contents/MacOS/Plex SQLite"
    private let legacyPlexSqlitePath = "/Applications/Plex Media Server.app/Contents/Resources/Support/Plex SQLite"
    private let legacyPlexDbPath = "~/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    private let placeholderPlexDbPath = "/Users/<there username>/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    
    private let tmdbClient = TMDBClient()
    private var lastTMDBStartSeasonNumber: Int?
    private var lastTMDBStartEpisodeNumber: Int?
    private var lastTMDBShowRef: String?

    private static let changeLogDateFormatter = ISO8601DateFormatter()

    private var defaultPlexDbPath: String {
        return "\(NSHomeDirectory())/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    }
    
    init() {
        loadSettings()
        ensureDefaultPresetsIfNeeded()
        refreshSchedulerTimerState()
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
        rememberRecentShow(show.id)

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
            tmdbShowIdOrURL: nil,
            autoLockInPlex: false
        )
    }

    func applyTMDBMetadataToEpisodes(
        episodeIds: [Int],
        tmdbStartSeasonNumber: Int,
        tmdbStartEpisodeNumber: Int,
        tmdbShowIdOrURL: String?,
        autoLockInPlex: Bool = false
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
            tmdbShowIdOrURL: tmdbShowIdOrURL,
            autoLockInPlex: autoLockInPlex
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
        tmdbShowIdOrURL: String? = nil,
        autoLockInPlex: Bool = false
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
                var updatedEpisodeIds: [Int] = []
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
                        updatedEpisodeIds.append(episodeId)
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
                    if autoLockInPlex, !updatedEpisodeIds.isEmpty {
                        self.lockAllPlexMetadata(itemIds: updatedEpisodeIds, entityLabel: "episode")
                    }
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

    func recentShows(limit: Int = 6) -> [PlexShow] {
        let byId = Dictionary(uniqueKeysWithValues: shows.map { ($0.id, $0) })
        return Array(recentShowIds.compactMap { byId[$0] }.prefix(limit))
    }

    func exportChangeLog(format: ChangeLogExportFormat) {
        guard !changeLogEntries.isEmpty else {
            statusMessage = "No change log entries to export"
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedFileTypes = [format.fileExtension]
        panel.nameFieldStringValue = "plex_change_log_\(Self.fileTimestamp()).\(format.fileExtension)"
        panel.title = "Export Change Log"
        panel.message = "Save change log as \(format.fileExtension.uppercased())"

        guard panel.runModal() == .OK, let url = panel.url else {
            statusMessage = "Change log export cancelled"
            return
        }

        do {
            switch format {
            case .csv:
                try csvDataForChangeLog().write(to: url, options: .atomic)
            case .json:
                try jsonDataForChangeLog().write(to: url, options: .atomic)
            }
            statusMessage = "Exported \(changeLogEntries.count) change log entries"
        } catch {
            statusMessage = "Failed to export change log: \(error.localizedDescription)"
        }
    }

    func clearChangeLog() {
        changeLogEntries.removeAll()
        statusMessage = "Cleared change log"
    }

    func runTMDBDryRunPreview(
        episodeIds: [Int],
        tmdbStartSeasonNumber: Int,
        tmdbStartEpisodeNumber: Int,
        tmdbShowIdOrURL: String?,
        options: EpisodeRemapOptions = EpisodeRemapOptions(
            updateTitle: true,
            updateAirDate: true,
            updateSummary: true,
            updateYearFromAirDate: true,
            updateThumbnail: true,
            requireTMDBMatch: true
        )
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

        guard let showTitle = shows.first(where: { $0.id == selectedShowId })?.title else {
            statusMessage = "Could not resolve selected show title"
            return
        }

        rememberTMDBContext(
            startSeasonNumber: tmdbStartSeasonNumber,
            startEpisodeNumber: tmdbStartEpisodeNumber,
            showRef: tmdbShowIdOrURL
        )

        let localEpisodesById = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
        lastDryRunEpisodeIds = episodeIds
        lastDryRunSeasonNumber = tmdbStartSeasonNumber
        lastDryRunEpisodeNumber = tmdbStartEpisodeNumber
        lastDryRunShowRef = Self.normalizedTMDBShowRef(tmdbShowIdOrURL)
        isDryRunLoading = true
        dryRunRows = []
        dryRunSummary = "Calculating preview..."

        Task {
            do {
                guard let tmdbShowId = try await resolveTMDBShowId(
                    showTitle: showTitle,
                    tmdbSeasonNumber: tmdbStartSeasonNumber,
                    tmdbEpisodeNumber: tmdbStartEpisodeNumber,
                    explicitShowRef: tmdbShowIdOrURL
                ) else {
                    DispatchQueue.main.async {
                        self.isDryRunLoading = false
                        self.dryRunRows = []
                        self.dryRunSummary = "No TMDB show match found for \(showTitle)"
                        self.statusMessage = self.dryRunSummary
                    }
                    return
                }

                var rows: [DryRunDiffRow] = []
                var tmdbMatchedCount = 0
                var skippedCount = 0

                // Reuse season responses while walking the TMDB cursor forward.
                var tmdbSeasonCache: [Int: [Int: TMDBEpisodeResponse]] = [:]
                var tmdbSeasonMaxEpisode: [Int: Int] = [:]
                var cursorSeason = tmdbStartSeasonNumber
                var cursorEpisode = tmdbStartEpisodeNumber

                for (offset, episodeId) in episodeIds.enumerated() {
                    guard let localEpisode = localEpisodesById[episodeId] else {
                        rows.append(
                            DryRunDiffRow(
                                episodeId: episodeId,
                                currentCode: "Unknown",
                                mappedCode: "Skipped",
                                currentTitle: "Episode not loaded",
                                mappedTitle: "Episode not loaded",
                                currentAirDate: "N/A",
                                mappedAirDate: "N/A",
                                note: "Episode was not found in the current season list"
                            )
                        )
                        skippedCount += 1
                        continue
                    }

                    var tmdbEpisode: TMDBEpisodeResponse?
                    var searchSteps = 0

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
                            } catch {
                                tmdbSeasonCache[cursorSeason] = [:]
                                tmdbSeasonMaxEpisode[cursorSeason] = 0
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
                        rows.append(
                            DryRunDiffRow(
                                episodeId: episodeId,
                                currentCode: "S\(localEpisode.season_number)E\(localEpisode.episode_number)",
                                mappedCode: "Skipped",
                                currentTitle: localEpisode.name,
                                mappedTitle: localEpisode.name,
                                currentAirDate: localEpisode.air_date ?? "N/A",
                                mappedAirDate: localEpisode.air_date ?? "N/A",
                                note: "No TMDB match found"
                            )
                        )
                        skippedCount += 1
                        continue
                    }

                    let mappedSeasonNumber = tmdbEpisode?.season_number ?? tmdbStartSeasonNumber
                    let mappedEpisodeNumber = tmdbEpisode?.episode_number ?? (tmdbStartEpisodeNumber + offset)
                    let mappedTitle = options.updateTitle ? (tmdbEpisode?.name ?? localEpisode.name) : localEpisode.name
                    let mappedAirDate = options.updateAirDate ? (tmdbEpisode?.air_date ?? localEpisode.air_date ?? "N/A") : (localEpisode.air_date ?? "N/A")

                    rows.append(
                        DryRunDiffRow(
                            episodeId: episodeId,
                            currentCode: "S\(localEpisode.season_number)E\(localEpisode.episode_number)",
                            mappedCode: "S\(mappedSeasonNumber)E\(mappedEpisodeNumber)",
                            currentTitle: localEpisode.name,
                            mappedTitle: mappedTitle,
                            currentAirDate: localEpisode.air_date ?? "N/A",
                            mappedAirDate: mappedAirDate,
                            note: tmdbEpisode == nil ? "TMDB match missing; fallback numbering used" : "TMDB match found"
                        )
                    )
                }

                let summary = "Dry run ready: \(rows.count) episode(s), TMDB matched \(tmdbMatchedCount), skipped \(skippedCount)."
                DispatchQueue.main.async {
                    self.isDryRunLoading = false
                    self.dryRunRows = rows
                    self.dryRunSummary = summary
                    self.statusMessage = summary
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDryRunLoading = false
                    self.dryRunRows = []
                    self.dryRunSummary = "Dry run failed: \(error.localizedDescription)"
                    self.statusMessage = self.dryRunSummary
                }
            }
        }
    }

    func applyLastDryRunPreview() {
        applyDryRunPreview(forEpisodeIds: lastDryRunEpisodeIds)
    }

    func applyDryRunPreview(forEpisodeIds episodeIds: [Int]) {
        guard !isDryRunLoading else {
            statusMessage = "Dry run is still loading"
            return
        }

        guard !lastDryRunEpisodeIds.isEmpty,
              let season = lastDryRunSeasonNumber,
              let episode = lastDryRunEpisodeNumber else {
            statusMessage = "Run a dry run preview first"
            return
        }

        let selectedSet = Set(episodeIds)
        let orderedEpisodeIds = lastDryRunEpisodeIds.filter { selectedSet.contains($0) }
        guard !orderedEpisodeIds.isEmpty else {
            statusMessage = "Select at least one dry run row to apply"
            return
        }

        applyTMDBMetadataToEpisodes(
            episodeIds: orderedEpisodeIds,
            tmdbStartSeasonNumber: season,
            tmdbStartEpisodeNumber: episode,
            tmdbShowIdOrURL: lastDryRunShowRef
        )
    }

    func isDryRunMeaningfulChange(_ row: DryRunDiffRow) -> Bool {
        if row.currentCode != row.mappedCode { return true }
        if row.currentTitle != row.mappedTitle { return true }
        if row.currentAirDate != row.mappedAirDate { return true }
        if row.mappedCode == "Skipped" { return true }
        return row.note.lowercased().contains("missing")
    }

    func exportDryRun(format: DryRunExportFormat, onlyChangedRows: Bool) {
        guard !dryRunRows.isEmpty else {
            statusMessage = "No dry run rows to export"
            return
        }

        let rowsToExport = onlyChangedRows
            ? dryRunRows.filter { isDryRunMeaningfulChange($0) }
            : dryRunRows

        guard !rowsToExport.isEmpty else {
            statusMessage = "No dry run rows match current export filter"
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedFileTypes = [format.fileExtension]
        panel.nameFieldStringValue = "plex_dry_run_\(Self.fileTimestamp()).\(format.fileExtension)"
        panel.title = "Export Dry Run"
        panel.message = "Save dry run as \(format.fileExtension.uppercased())"

        guard panel.runModal() == .OK, let url = panel.url else {
            statusMessage = "Dry run export cancelled"
            return
        }

        do {
            switch format {
            case .csv:
                try csvDataForDryRun(rows: rowsToExport).write(to: url, options: .atomic)
            case .json:
                try jsonDataForDryRun(rows: rowsToExport).write(to: url, options: .atomic)
            }
            statusMessage = "Exported \(rowsToExport.count) dry run row(s)"
        } catch {
            statusMessage = "Failed to export dry run: \(error.localizedDescription)"
        }
    }

    func refreshBackupFiles() {
        let backupDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".plex_tv_editor_backups", isDirectory: true)

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: backupDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey, .nameKey],
                options: [.skipsHiddenFiles]
            )

            let items = urls.compactMap { url -> BackupFileItem? in
                guard url.pathExtension.lowercased() == "db" else { return nil }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey, .nameKey])
                guard values?.isRegularFile == true else { return nil }
                let modified = values?.contentModificationDate ?? Date.distantPast
                let size = Int64(values?.fileSize ?? 0)
                let name = values?.name ?? url.lastPathComponent
                return BackupFileItem(
                    id: url.path,
                    path: url.path,
                    fileName: name,
                    modifiedAt: modified,
                    sizeBytes: size
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }

            backupFiles = items
        } catch {
            backupFiles = []
        }
    }

    func revealBackupInFinder(path: String) {
        let expandedPath = expandPath(path)
        let url = URL(fileURLWithPath: expandedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "Backup file not found"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        statusMessage = "Revealed backup in Finder"
    }

    func restoreBackup(from backupPath: String) {
        let sourcePath = expandPath(backupPath)
        let destinationPath = expandPath(plexDbPath)

        guard !sourcePath.isEmpty else {
            statusMessage = "Select a backup file first"
            return
        }
        guard !destinationPath.isEmpty else {
            statusMessage = "Configure Plex database path before restoring"
            return
        }

        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let destinationURL = URL(fileURLWithPath: destinationPath)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            statusMessage = "Backup file not found"
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path),
           !canAcquireExclusiveSQLiteLock(atPath: destinationURL.path) {
            statusMessage = "Plex database appears busy. Stop Plex scans/playback and retry restore"
            return
        }

        do {
            let destinationDirectory = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true, attributes: nil)

            let safetyBackupURL = sourceURL.deletingLastPathComponent()
                .appendingPathComponent("pre_restore_\(Self.fileTimestamp()).db")
            var createdSafetySnapshot = false

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.copyItem(at: destinationURL, to: safetyBackupURL)
                createdSafetySnapshot = true
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            refreshBackupFiles()
            loadShows()
            loadMovies()

            if selectedShowId > 0 {
                getSeasons(for: selectedShowId)
                if selectedSeasonId > 0 {
                    getEpisodes(for: selectedSeasonId)
                }
            }

            if createdSafetySnapshot {
                statusMessage = "Restored backup \(sourceURL.lastPathComponent). Safety snapshot created: \(safetyBackupURL.lastPathComponent)"
            } else {
                statusMessage = "Restored backup \(sourceURL.lastPathComponent)"
            }
            notifyIfEnabled(title: "Backup Restored", body: sourceURL.lastPathComponent)
        } catch {
            statusMessage = "Backup restore failed: \(error.localizedDescription)"
            notifyIfEnabled(title: "Backup Restore Failed", body: error.localizedDescription)
        }
    }

    func formattedBackupDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func formattedBackupSize(_ sizeBytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
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
            DispatchQueue.main.async {
                self.lastResolvedTMDBShowId = parsedShowId
            }
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
                    DispatchQueue.main.async {
                        self.lastResolvedTMDBShowId = candidate.id
                    }
                    return candidate.id
                }
            } catch {
                continue
            }
        }

        let fallback = ranked.first?.id
        DispatchQueue.main.async {
            self.lastResolvedTMDBShowId = fallback
        }
        return fallback
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

            let savedServerURL = settings.plexServerURL ?? "http://127.0.0.1:32400"
            let normalizedServerURL = normalizePlexServerURL(savedServerURL)
            self.plexServerURL = normalizedServerURL
            self.plexToken = settings.plexToken ?? ""
            self.selectedPlexTVSectionKey = settings.selectedPlexTVSectionKey ?? ""
            self.selectedPlexMovieSectionKey = settings.selectedPlexMovieSectionKey ?? ""
            self.plexServerProfiles = settings.plexServerProfiles ?? []
            self.selectedPlexProfileId = settings.selectedPlexProfileId ?? ""
            self.plexActionPresets = settings.plexActionPresets ?? []
            self.selectedPlexPresetId = settings.selectedPlexPresetId ?? ""
            self.sectionActionMaxRetries = max(0, settings.sectionActionMaxRetries ?? 1)
            self.sectionActionRetryDelaySeconds = max(0, settings.sectionActionRetryDelaySeconds ?? 0.5)
            self.schedulerEnabled = settings.schedulerEnabled ?? false
            if let frequencyRaw = settings.schedulerFrequency,
               let frequency = SchedulerFrequency(rawValue: frequencyRaw) {
                self.schedulerFrequency = frequency
            }
            if let scopeRaw = settings.schedulerScope,
               let scope = SchedulerScope(rawValue: scopeRaw) {
                self.schedulerScope = scope
            }
            self.schedulerLastRunAt = settings.schedulerLastRunAt
            self.schedulerNextRunAt = settings.schedulerNextRunAt
            self.notificationsEnabled = settings.notificationsEnabled ?? false
            self.plexCapabilities = settings.plexCapabilities ?? .unknown
            self.capabilitySummary = settings.capabilitySummary ?? "Unknown"
            if normalizedServerURL != savedServerURL {
                migratedSettings = true
            }
        } else {
            // Set defaults
            self.tmdbApiKey = "fd51c863ad45547eb19ba9f70f3ac4f0"
            self.plexSqlitePath = defaultPlexSqlitePath
            self.plexDbPath = defaultPlexDbPath
            self.plexServerURL = "http://127.0.0.1:32400"
            self.plexToken = ""
            self.selectedPlexTVSectionKey = ""
            self.selectedPlexMovieSectionKey = ""
            self.plexServerProfiles = []
            self.selectedPlexProfileId = ""
            self.plexActionPresets = []
            self.selectedPlexPresetId = ""
            self.sectionActionMaxRetries = 1
            self.sectionActionRetryDelaySeconds = 0.5
            self.schedulerEnabled = false
            self.schedulerFrequency = .daily
            self.schedulerScope = .both
            self.schedulerLastRunAt = nil
            self.schedulerNextRunAt = nil
            self.notificationsEnabled = false
            self.plexCapabilities = .unknown
            self.capabilitySummary = "Unknown"
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

        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        if !normalizedServerURL.isEmpty {
            self.plexServerURL = normalizedServerURL
        }

        let settings = Settings(
            tmdbApiKey: tmdbApiKey,
            plexSqlitePath: plexSqlitePath,
            plexDbPath: self.plexDbPath,
            plexServerURL: self.plexServerURL,
            plexToken: plexToken.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedPlexTVSectionKey: selectedPlexTVSectionKey,
            selectedPlexMovieSectionKey: selectedPlexMovieSectionKey,
            plexServerProfiles: plexServerProfiles,
            selectedPlexProfileId: selectedPlexProfileId,
            plexActionPresets: plexActionPresets,
            selectedPlexPresetId: selectedPlexPresetId,
            sectionActionMaxRetries: sectionActionMaxRetries,
            sectionActionRetryDelaySeconds: sectionActionRetryDelaySeconds,
            schedulerEnabled: schedulerEnabled,
            schedulerFrequency: schedulerFrequency.rawValue,
            schedulerScope: schedulerScope.rawValue,
            schedulerLastRunAt: schedulerLastRunAt,
            schedulerNextRunAt: schedulerNextRunAt,
            notificationsEnabled: notificationsEnabled,
            plexCapabilities: plexCapabilities,
            capabilitySummary: capabilitySummary
        )
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "PlexTVEditorSettings")
            statusMessage = "Settings saved successfully"
        }
        refreshSchedulerTimerState()
    }

    func saveCurrentServerAsProfile(name: String) {
        let profileName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        let trimmedToken = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !profileName.isEmpty else {
            statusMessage = "Enter a profile name"
            return
        }
        guard !normalizedServerURL.isEmpty, !trimmedToken.isEmpty else {
            statusMessage = "Server URL and token are required to save profile"
            return
        }

        if let existingIndex = plexServerProfiles.firstIndex(where: { $0.name.caseInsensitiveCompare(profileName) == .orderedSame }) {
            plexServerProfiles[existingIndex] = PlexServerProfile(
                id: plexServerProfiles[existingIndex].id,
                name: profileName,
                serverURL: normalizedServerURL,
                token: trimmedToken
            )
            selectedPlexProfileId = plexServerProfiles[existingIndex].id.uuidString
            statusMessage = "Updated server profile \(profileName)"
        } else {
            let profile = PlexServerProfile(id: UUID(), name: profileName, serverURL: normalizedServerURL, token: trimmedToken)
            plexServerProfiles.append(profile)
            plexServerProfiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectedPlexProfileId = profile.id.uuidString
            statusMessage = "Saved server profile \(profileName)"
        }

        saveSettings()
    }

    func applySelectedServerProfile() {
        guard let uuid = UUID(uuidString: selectedPlexProfileId),
              let profile = plexServerProfiles.first(where: { $0.id == uuid }) else {
            statusMessage = "Select a valid server profile"
            return
        }

        plexServerURL = normalizePlexServerURL(profile.serverURL)
        plexToken = profile.token
        statusMessage = "Applied profile \(profile.name)"
        saveSettings()
    }

    func deleteSelectedServerProfile() {
        guard let uuid = UUID(uuidString: selectedPlexProfileId) else {
            statusMessage = "Select a server profile to delete"
            return
        }

        guard let index = plexServerProfiles.firstIndex(where: { $0.id == uuid }) else {
            statusMessage = "Selected profile no longer exists"
            return
        }

        let name = plexServerProfiles[index].name
        plexServerProfiles.remove(at: index)
        selectedPlexProfileId = plexServerProfiles.first?.id.uuidString ?? ""
        statusMessage = "Deleted profile \(name)"
        saveSettings()
    }

    func addPreset(name: String, sectionType: String, includeRefresh: Bool, includeAnalyze: Bool, includeEmptyTrash: Bool, runOnAllSections: Bool) {
        let presetName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedType = sectionType.lowercased()
        guard !presetName.isEmpty else {
            statusMessage = "Enter a preset name"
            return
        }
        guard normalizedType == "show" || normalizedType == "movie" else {
            statusMessage = "Preset section type must be TV or Movie"
            return
        }
        guard includeRefresh || includeAnalyze || includeEmptyTrash else {
            statusMessage = "Preset must include at least one action"
            return
        }

        let preset = PlexSectionActionPreset(
            id: UUID(),
            name: presetName,
            sectionType: normalizedType,
            includeRefresh: includeRefresh,
            includeAnalyze: includeAnalyze,
            includeEmptyTrash: includeEmptyTrash,
            runOnAllSections: runOnAllSections
        )
        plexActionPresets.append(preset)
        plexActionPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedPlexPresetId = preset.id.uuidString
        statusMessage = "Preset \(presetName) added"
        saveSettings()
    }

    func deleteSelectedPreset() {
        guard let uuid = UUID(uuidString: selectedPlexPresetId),
              let index = plexActionPresets.firstIndex(where: { $0.id == uuid }) else {
            statusMessage = "Select a preset to delete"
            return
        }

        let name = plexActionPresets[index].name
        plexActionPresets.remove(at: index)
        selectedPlexPresetId = plexActionPresets.first?.id.uuidString ?? ""
        statusMessage = "Deleted preset \(name)"
        saveSettings()
    }

    func runSelectedPreset(confirmedDestructive: Bool = false) {
        guard let uuid = UUID(uuidString: selectedPlexPresetId),
              let preset = plexActionPresets.first(where: { $0.id == uuid }) else {
            statusMessage = "Select a preset to run"
            return
        }

        if preset.includeEmptyTrash && !confirmedDestructive {
            statusMessage = "Preset includes Empty Trash. Confirm before running."
            return
        }

        let sections = plexLibrarySections
            .filter { $0.type.lowercased() == preset.sectionType }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        guard !sections.isEmpty else {
            statusMessage = "Load sections first before running preset"
            return
        }

        let targetSections: [PlexLibrarySection]
        if preset.runOnAllSections {
            targetSections = sections
        } else {
            let selectedKey = preset.sectionType == "show" ? selectedPlexTVSectionKey : selectedPlexMovieSectionKey
            let trimmed = selectedKey.trimmingCharacters(in: .whitespacesAndNewlines)
            targetSections = sections.filter { $0.key == trimmed }
        }

        guard !targetSections.isEmpty else {
            statusMessage = "Preset requires a selected section"
            return
        }

        runPresetOnSections(preset: preset, sections: targetSections)
    }

    func selectedPresetRequiresDestructiveConfirmation() -> Bool {
        guard let uuid = UUID(uuidString: selectedPlexPresetId),
              let preset = plexActionPresets.first(where: { $0.id == uuid }) else {
            return false
        }
        return preset.includeEmptyTrash
    }

    func selectedPresetName() -> String {
        guard let uuid = UUID(uuidString: selectedPlexPresetId),
              let preset = plexActionPresets.first(where: { $0.id == uuid }) else {
            return "selected preset"
        }
        return preset.name
    }

    func previewTrashForLoadedSections() {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before previewing trash"
            return
        }

        guard !plexLibrarySections.isEmpty else {
            statusMessage = "Load Plex sections first"
            return
        }

        isPreviewingSectionTrash = true
        statusMessage = "Previewing trash counts..."

        Task {
            var rows: [PlexTrashPreviewRow] = []
            for section in plexLibrarySections.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
                let count = (try? await fetchTrashCount(baseURL: serverURL, token: token, sectionKey: section.key)) ?? 0
                rows.append(PlexTrashPreviewRow(sectionKey: section.key, sectionLabel: section.title, trashCount: count))
            }

            DispatchQueue.main.async {
                self.isPreviewingSectionTrash = false
                self.sectionTrashPreviewRows = rows
                let total = rows.reduce(0) { $0 + $1.trashCount }
                self.statusMessage = "Trash preview ready: \(total) item(s) across \(rows.count) section(s)"
            }
        }
    }

    func runRollbackWizard(reRunSafeActions: Bool) {
        refreshBackupFiles()
        guard let latestBackup = backupFiles.sorted(by: { $0.modifiedAt > $1.modifiedAt }).first else {
            statusMessage = "No backups available for rollback"
            return
        }

        restoreBackup(from: latestBackup.path)

        if reRunSafeActions {
            if !selectedPlexTVSectionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let tvLabel = plexLibrarySections.first(where: { $0.key == selectedPlexTVSectionKey })?.title {
                runPlexSectionMaintenance(sectionKey: selectedPlexTVSectionKey, sectionLabel: tvLabel)
            }
            if !selectedPlexMovieSectionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let movieLabel = plexLibrarySections.first(where: { $0.key == selectedPlexMovieSectionKey })?.title {
                runPlexSectionMaintenance(sectionKey: selectedPlexMovieSectionKey, sectionLabel: movieLabel)
            }
        }

        notifyIfEnabled(title: "Rollback Complete", body: reRunSafeActions ? "Rollback completed and safe maintenance started." : "Rollback completed.")
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                self.statusMessage = granted ? "Notifications enabled" : "Notifications permission denied"
                self.saveSettings()
            }
        }
    }

    func detectPlexCapabilities() {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before capability detection"
            return
        }

        guard let probeSection = plexLibrarySections.first else {
            statusMessage = "Load sections first to detect capabilities"
            return
        }

        Task {
            let refresh = await probePlexEndpoint(baseURL: serverURL, token: token, path: "/library/sections/\(probeSection.key)/refresh")
            let analyze = await probePlexEndpoint(baseURL: serverURL, token: token, path: "/library/sections/\(probeSection.key)/analyze")
            let emptyTrash = await probePlexEndpoint(baseURL: serverURL, token: token, path: "/library/sections/\(probeSection.key)/emptyTrash")
            let cancel = await probePlexEndpoint(baseURL: serverURL, token: token, path: "/library/sections/\(probeSection.key)/refresh/cancel")

            DispatchQueue.main.async {
                self.plexCapabilities = PlexCapabilities(
                    canRefreshSection: refresh,
                    canAnalyzeSection: analyze,
                    canEmptyTrashSection: emptyTrash,
                    canCancelSectionJob: cancel,
                    canAnalyzeItem: analyze
                )
                self.capabilitySummary = "Refresh: \(refresh ? "Yes" : "No"), Analyze: \(analyze ? "Yes" : "No"), Empty Trash: \(emptyTrash ? "Yes" : "No"), Cancel: \(cancel ? "Yes" : "No")"
                self.statusMessage = "Capability detection complete"
                self.saveSettings()
            }
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

    func testPlexAPIConnection() {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            plexConnectionSummary = "Invalid Plex server URL"
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            plexConnectionSummary = "Missing Plex token"
            statusMessage = "Enter Plex token before testing API"
            return
        }

        isTestingPlexConnection = true
        plexConnectionSummary = "Testing..."

        Task {
            do {
                let identity = try await fetchPlexIdentity(baseURL: serverURL, token: token)
                DispatchQueue.main.async {
                    self.isTestingPlexConnection = false
                    self.plexServerURL = normalizedServerURL
                    self.plexServerName = identity.friendlyName
                    self.plexServerVersion = identity.version
                    self.plexServerMachineIdentifier = identity.machineIdentifier
                    self.plexConnectionSummary = "Connected to \(identity.friendlyName)"
                    self.statusMessage = "✓ Plex API connected (\(identity.friendlyName) v\(identity.version))"
                    self.notifyIfEnabled(title: "Plex Connected", body: "Connected to \(identity.friendlyName)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isTestingPlexConnection = false
                    self.plexConnectionSummary = "Connection failed"
                    self.statusMessage = "✗ Plex API test failed: \(error.localizedDescription)"
                    self.notifyIfEnabled(title: "Plex Connection Failed", body: error.localizedDescription)
                }
            }
        }
    }

    func loadPlexLibrarySections() {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before loading sections"
            return
        }

        isLoadingPlexSections = true

        Task {
            do {
                let sections = try await fetchPlexLibrarySections(baseURL: serverURL, token: token)
                DispatchQueue.main.async {
                    self.isLoadingPlexSections = false
                    self.plexLibrarySections = sections

                    if let firstTV = sections.first(where: { $0.type == "show" }),
                       (self.selectedPlexTVSectionKey.isEmpty || !sections.contains(where: { $0.key == self.selectedPlexTVSectionKey })) {
                        self.selectedPlexTVSectionKey = firstTV.key
                    }

                    if let firstMovie = sections.first(where: { $0.type == "movie" }),
                       (self.selectedPlexMovieSectionKey.isEmpty || !sections.contains(where: { $0.key == self.selectedPlexMovieSectionKey })) {
                        self.selectedPlexMovieSectionKey = firstMovie.key
                    }

                    self.statusMessage = "Loaded \(sections.count) Plex library section(s)"
                    self.detectPlexCapabilities()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingPlexSections = false
                    self.statusMessage = "Failed to load Plex sections: \(error.localizedDescription)"
                }
            }
        }
    }

    func refreshPlexMetadata(itemIds: [Int], entityLabel: String) {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before refreshing metadata"
            return
        }

        let uniqueIds = Array(Set(itemIds)).sorted()
        guard !uniqueIds.isEmpty else {
            statusMessage = "Select at least one \(entityLabel) to refresh"
            return
        }

        statusMessage = "Queueing Plex refresh for \(uniqueIds.count) \(entityLabel)(s)..."

        Task {
            var successCount = 0
            var failureCount = 0

            for id in uniqueIds {
                do {
                    try await queuePlexMetadataRefresh(baseURL: serverURL, token: token, itemId: id)
                    successCount += 1
                } catch {
                    failureCount += 1
                }
            }

            DispatchQueue.main.async {
                self.statusMessage = "Plex refresh queued: \(successCount) succeeded, \(failureCount) failed"
            }
        }
    }

    func analyzePlexMetadata(itemIds: [Int], entityLabel: String) {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before analyzing metadata"
            return
        }

        let uniqueIds = Array(Set(itemIds)).sorted()
        guard !uniqueIds.isEmpty else {
            statusMessage = "Select at least one \(entityLabel) to analyze"
            return
        }

        statusMessage = "Queueing Plex analyze for \(uniqueIds.count) \(entityLabel)(s)..."

        Task {
            var successCount = 0
            var failureCount = 0

            for id in uniqueIds {
                do {
                    try await queuePlexMetadataAnalyze(baseURL: serverURL, token: token, itemId: id)
                    successCount += 1
                } catch {
                    failureCount += 1
                }
            }

            DispatchQueue.main.async {
                self.statusMessage = "Plex analyze queued: \(successCount) succeeded, \(failureCount) failed"
            }
        }
    }

    func refreshSelectedPlexSection(sectionKey: String, sectionLabel: String) {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before refreshing section"
            return
        }

        let trimmedSectionKey = sectionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSectionKey.isEmpty else {
            statusMessage = "Select a Plex section before refreshing"
            return
        }

        isRefreshingPlexSection = true
        statusMessage = "Queueing Plex refresh for \(sectionLabel)..."

        Task {
            do {
                try await performTrackedSectionAction(
                    baseURL: serverURL,
                    token: token,
                    sectionKey: trimmedSectionKey,
                    sectionLabel: sectionLabel,
                    action: .refresh
                )
                DispatchQueue.main.async {
                    self.isRefreshingPlexSection = false
                    self.statusMessage = "Plex section refresh queued for \(sectionLabel)"
                    self.rememberQueuedPlexSectionJob(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: .refresh)
                    self.recordPlexSectionAction(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: .refresh, outcome: "Queued")
                    self.notifyIfEnabled(title: "Section Refresh Queued", body: sectionLabel)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRefreshingPlexSection = false
                    self.statusMessage = "Section refresh failed for \(sectionLabel): \(error.localizedDescription)"
                    self.recordPlexSectionAction(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: .refresh, outcome: "Failed: \(error.localizedDescription)")
                    self.notifyIfEnabled(title: "Section Refresh Failed", body: sectionLabel)
                }
            }
        }
    }

    func analyzeSelectedPlexSection(sectionKey: String, sectionLabel: String) {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before analyzing section"
            return
        }

        let trimmedSectionKey = sectionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSectionKey.isEmpty else {
            statusMessage = "Select a Plex section before analyzing"
            return
        }

        isAnalyzingPlexSection = true
        statusMessage = "Queueing Plex analyze for \(sectionLabel)..."

        Task {
            do {
                try await performTrackedSectionAction(
                    baseURL: serverURL,
                    token: token,
                    sectionKey: trimmedSectionKey,
                    sectionLabel: sectionLabel,
                    action: .analyze
                )
                DispatchQueue.main.async {
                    self.isAnalyzingPlexSection = false
                    self.statusMessage = "Plex section analyze queued for \(sectionLabel)"
                    self.rememberQueuedPlexSectionJob(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: .analyze)
                    self.recordPlexSectionAction(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: .analyze, outcome: "Queued")
                    self.notifyIfEnabled(title: "Section Analyze Queued", body: sectionLabel)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAnalyzingPlexSection = false
                    self.statusMessage = "Section analyze failed for \(sectionLabel): \(error.localizedDescription)"
                    self.recordPlexSectionAction(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: .analyze, outcome: "Failed: \(error.localizedDescription)")
                    self.notifyIfEnabled(title: "Section Analyze Failed", body: sectionLabel)
                }
            }
        }
    }

    func emptyTrashForSelectedPlexSection(sectionKey: String, sectionLabel: String) {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before emptying trash"
            return
        }

        let trimmedSectionKey = sectionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSectionKey.isEmpty else {
            statusMessage = "Select a Plex section before emptying trash"
            return
        }

        isEmptyingPlexSection = true
        statusMessage = "Queueing Plex empty trash for \(sectionLabel)..."

        Task {
            do {
                try await performTrackedSectionAction(
                    baseURL: serverURL,
                    token: token,
                    sectionKey: trimmedSectionKey,
                    sectionLabel: sectionLabel,
                    action: .emptyTrash
                )
                DispatchQueue.main.async {
                    self.isEmptyingPlexSection = false
                    self.statusMessage = "Plex empty trash queued for \(sectionLabel)"
                    self.rememberQueuedPlexSectionJob(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: .emptyTrash)
                    self.recordPlexSectionAction(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: .emptyTrash, outcome: "Queued")
                    self.notifyIfEnabled(title: "Empty Trash Queued", body: sectionLabel)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isEmptyingPlexSection = false
                    self.statusMessage = "Empty trash failed for \(sectionLabel): \(error.localizedDescription)"
                    self.recordPlexSectionAction(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: .emptyTrash, outcome: "Failed: \(error.localizedDescription)")
                    self.notifyIfEnabled(title: "Empty Trash Failed", body: sectionLabel)
                }
            }
        }
    }

    func runPlexSectionMaintenance(sectionKey: String, sectionLabel: String) {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before running maintenance"
            return
        }

        let trimmedSectionKey = sectionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSectionKey.isEmpty else {
            statusMessage = "Select a Plex section before running maintenance"
            return
        }

        isRunningPlexSectionMaintenance = true
        statusMessage = "Queueing Plex maintenance for \(sectionLabel)..."

        Task {
            let actions: [PlexSectionActionKind] = [
                plexCapabilities.canRefreshSection ? .refresh : nil,
                plexCapabilities.canAnalyzeSection ? .analyze : nil
            ].compactMap { $0 }

            guard !actions.isEmpty else {
                DispatchQueue.main.async {
                    self.isRunningPlexSectionMaintenance = false
                    self.statusMessage = "Maintenance unavailable: refresh/analyze not supported by server"
                }
                return
            }
            var queuedActions: [PlexSectionActionKind] = []
            var failedActions: [(PlexSectionActionKind, String)] = []

            for action in actions {
                do {
                    try await performTrackedSectionAction(
                        baseURL: serverURL,
                        token: token,
                        sectionKey: trimmedSectionKey,
                        sectionLabel: sectionLabel,
                        action: action
                    )
                    queuedActions.append(action)
                } catch {
                    failedActions.append((action, error.localizedDescription))
                }
            }

            DispatchQueue.main.async {
                self.isRunningPlexSectionMaintenance = false

                for action in queuedActions {
                    self.rememberQueuedPlexSectionJob(sectionKey: trimmedSectionKey, sectionLabel: sectionLabel, action: action)
                    self.recordPlexSectionAction(
                        sectionKey: trimmedSectionKey,
                        sectionLabel: sectionLabel,
                        action: action,
                        outcome: "Queued via maintenance"
                    )
                }

                for (action, message) in failedActions {
                    self.recordPlexSectionAction(
                        sectionKey: trimmedSectionKey,
                        sectionLabel: sectionLabel,
                        action: action,
                        outcome: "Failed via maintenance: \(message)"
                    )
                }

                if failedActions.isEmpty {
                    self.statusMessage = "Section maintenance queued for \(sectionLabel): \(queuedActions.count) succeeded"
                } else {
                    self.statusMessage = "Section maintenance for \(sectionLabel): \(queuedActions.count) succeeded, \(failedActions.count) failed"
                }
                self.notifyIfEnabled(title: "Section Maintenance", body: self.statusMessage)
            }
        }
    }

    func runBulkPlexSectionMaintenance(sectionType: String) {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before running bulk maintenance"
            return
        }

        let normalizedType = sectionType.lowercased()
        guard normalizedType == "show" || normalizedType == "movie" else {
            statusMessage = "Unsupported section type for bulk maintenance"
            return
        }

        let targetSections = plexLibrarySections
            .filter { $0.type.lowercased() == normalizedType }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        guard !targetSections.isEmpty else {
            let scopeLabel = normalizedType == "show" ? "TV" : "movie"
            statusMessage = "Load Plex sections first. No \(scopeLabel) sections available."
            return
        }

        let scopeLabel = normalizedType == "show" ? "TV" : "movie"
        isRunningBulkPlexSectionMaintenance = true
        bulkPlexSectionMaintenanceProgress = "0/\(targetSections.count) sections queued"
        statusMessage = "Running bulk \(scopeLabel) maintenance..."

        Task {
            let actions: [PlexSectionActionKind] = [
                plexCapabilities.canRefreshSection ? .refresh : nil,
                plexCapabilities.canAnalyzeSection ? .analyze : nil
            ].compactMap { $0 }

            guard !actions.isEmpty else {
                DispatchQueue.main.async {
                    self.isRunningBulkPlexSectionMaintenance = false
                    self.bulkPlexSectionMaintenanceProgress = ""
                    self.statusMessage = "Bulk maintenance unavailable: refresh/analyze not supported"
                }
                return
            }
            var sectionSuccessCount = 0
            var sectionFailureCount = 0
            var processedCount = 0

            for section in targetSections {
                var queuedActions: [PlexSectionActionKind] = []
                var failedActions: [(PlexSectionActionKind, String)] = []

                for action in actions {
                    do {
                        try await performTrackedSectionAction(
                            baseURL: serverURL,
                            token: token,
                            sectionKey: section.key,
                            sectionLabel: section.title,
                            action: action
                        )
                        queuedActions.append(action)
                    } catch {
                        failedActions.append((action, error.localizedDescription))
                    }
                }

                processedCount += 1
                if failedActions.isEmpty {
                    sectionSuccessCount += 1
                } else {
                    sectionFailureCount += 1
                }

                let sectionQueuedActions = queuedActions
                let sectionFailedActions = failedActions
                let progressText = "\(processedCount)/\(targetSections.count) sections queued"

                DispatchQueue.main.async {
                    for action in sectionQueuedActions {
                        self.rememberQueuedPlexSectionJob(sectionKey: section.key, sectionLabel: section.title, action: action)
                        self.recordPlexSectionAction(
                            sectionKey: section.key,
                            sectionLabel: section.title,
                            action: action,
                            outcome: "Queued via bulk maintenance"
                        )
                    }

                    for (action, message) in sectionFailedActions {
                        self.recordPlexSectionAction(
                            sectionKey: section.key,
                            sectionLabel: section.title,
                            action: action,
                            outcome: "Failed via bulk maintenance: \(message)"
                        )
                    }

                    self.bulkPlexSectionMaintenanceProgress = progressText
                }
            }

            DispatchQueue.main.async {
                self.isRunningBulkPlexSectionMaintenance = false
                self.bulkPlexSectionMaintenanceProgress = ""
                self.statusMessage = "Bulk \(scopeLabel) maintenance complete: \(sectionSuccessCount) succeeded, \(sectionFailureCount) with failures"
                self.notifyIfEnabled(title: "Bulk Maintenance Complete", body: self.statusMessage)
            }
        }
    }

    func retryFailedSectionActionsForSelectedSections() {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before retrying failed actions"
            return
        }

        let sectionKeys = Set([
            selectedPlexTVSectionKey.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedPlexMovieSectionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty })

        guard !sectionKeys.isEmpty else {
            statusMessage = "Select a TV or Movie section before retrying"
            return
        }

        let failedEntries = latestFailedSectionActions(for: sectionKeys)
        guard !failedEntries.isEmpty else {
            statusMessage = "No failed section actions to retry for selected sections"
            return
        }

        isRetryingFailedPlexSectionActions = true
        statusMessage = "Retrying \(failedEntries.count) failed section action(s)..."

        Task {
            var queuedResults: [(String, String, PlexSectionActionKind)] = []
            var failedResults: [(String, String, PlexSectionActionKind, String)] = []

            for entry in failedEntries {
                guard let action = PlexSectionActionKind(rawValue: entry.actionLabel) else {
                    continue
                }

                do {
                    try await performTrackedSectionAction(
                        baseURL: serverURL,
                        token: token,
                        sectionKey: entry.sectionKey,
                        sectionLabel: entry.sectionLabel,
                        action: action
                    )
                    queuedResults.append((entry.sectionKey, entry.sectionLabel, action))
                } catch {
                    failedResults.append((entry.sectionKey, entry.sectionLabel, action, error.localizedDescription))
                }
            }

            DispatchQueue.main.async {
                self.isRetryingFailedPlexSectionActions = false

                for (sectionKey, sectionLabel, action) in queuedResults {
                    self.rememberQueuedPlexSectionJob(sectionKey: sectionKey, sectionLabel: sectionLabel, action: action)
                    self.recordPlexSectionAction(
                        sectionKey: sectionKey,
                        sectionLabel: sectionLabel,
                        action: action,
                        outcome: "Retry queued"
                    )
                }

                for (sectionKey, sectionLabel, action, message) in failedResults {
                    self.recordPlexSectionAction(
                        sectionKey: sectionKey,
                        sectionLabel: sectionLabel,
                        action: action,
                        outcome: "Retry failed: \(message)"
                    )
                }

                self.statusMessage = "Retry complete: \(queuedResults.count) queued, \(failedResults.count) failed"
                self.notifyIfEnabled(title: "Retry Complete", body: self.statusMessage)
            }
        }
    }

    func cancelLastQueuedPlexSectionJob() {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before cancelling section job"
            return
        }

        let sectionKey = lastQueuedPlexSectionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sectionLabel = lastQueuedPlexSectionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionLabel = lastQueuedPlexSectionAction.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sectionKey.isEmpty,
              !sectionLabel.isEmpty,
              !actionLabel.isEmpty,
              let action = PlexSectionActionKind(rawValue: actionLabel) else {
            statusMessage = "No queued section job available to cancel"
            return
        }

        isCancellingPlexSectionJob = true
        statusMessage = "Requesting cancel for \(actionLabel) on \(sectionLabel)..."

        Task {
            do {
                try await queuePlexSectionCancel(baseURL: serverURL, token: token, sectionKey: sectionKey, action: action)
                DispatchQueue.main.async {
                    self.isCancellingPlexSectionJob = false
                    self.statusMessage = "Cancel requested for \(actionLabel) on \(sectionLabel)"
                    self.recordPlexSectionAction(sectionKey: sectionKey, sectionLabel: sectionLabel, action: action, outcome: "Cancel requested")
                    self.clearQueuedPlexSectionJob()
                    self.notifyIfEnabled(title: "Section Job Cancel", body: "Cancel requested for \(actionLabel) in \(sectionLabel)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isCancellingPlexSectionJob = false
                    self.statusMessage = "Cancel failed for \(actionLabel) on \(sectionLabel): \(error.localizedDescription)"
                    self.recordPlexSectionAction(sectionKey: sectionKey, sectionLabel: sectionLabel, action: action, outcome: "Cancel failed")
                    self.notifyIfEnabled(title: "Cancel Failed", body: "\(actionLabel) in \(sectionLabel)")
                }
            }
        }
    }

    func clearPlexSectionActionHistory() {
        plexSectionActionHistory.removeAll()
        statusMessage = "Cleared section action history"
    }

    func exportSectionActionHistory(format: SectionActionHistoryExportFormat, selectedSectionKeys: Set<String> = []) {
        let normalizedKeys = Set(selectedSectionKeys.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })

        let entriesToExport: [PlexSectionActionHistoryEntry]
        if normalizedKeys.isEmpty {
            entriesToExport = plexSectionActionHistory
        } else {
            entriesToExport = plexSectionActionHistory.filter { normalizedKeys.contains($0.sectionKey) }
        }

        guard !entriesToExport.isEmpty else {
            statusMessage = "No section history entries to export"
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedFileTypes = [format.fileExtension]
        panel.nameFieldStringValue = "plex_section_history_\(Self.fileTimestamp()).\(format.fileExtension)"
        panel.title = "Export Section History"
        panel.message = "Save section history as \(format.fileExtension.uppercased())"

        guard panel.runModal() == .OK, let url = panel.url else {
            statusMessage = "Section history export cancelled"
            return
        }

        do {
            switch format {
            case .csv:
                try csvDataForSectionActionHistory(entries: entriesToExport).write(to: url, options: .atomic)
            case .json:
                try jsonDataForSectionActionHistory(entries: entriesToExport).write(to: url, options: .atomic)
            }
            statusMessage = "Exported \(entriesToExport.count) section history entries"
        } catch {
            statusMessage = "Failed to export section history: \(error.localizedDescription)"
        }
    }

    func lockAllPlexMetadata(itemIds: [Int], entityLabel: String) {
        setPlexMetadataLockState(itemIds: itemIds, entityLabel: entityLabel, isLocked: true)
    }

    func formattedSectionActionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func formattedSectionJobDuration(_ job: PlexSectionJobMonitorItem) -> String {
        let end = job.finishedAt ?? Date()
        let seconds = max(0, end.timeIntervalSince(job.startedAt))
        return String(format: "%.1fs", seconds)
    }

    func clearSectionJobMonitor() {
        activeSectionJobs.removeAll()
        completedSectionJobs.removeAll()
        statusMessage = "Cleared section job monitor"
    }

    func unlockAllPlexMetadata(itemIds: [Int], entityLabel: String) {
        setPlexMetadataLockState(itemIds: itemIds, entityLabel: entityLabel, isLocked: false)
    }

    private func setPlexMetadataLockState(itemIds: [Int], entityLabel: String, isLocked: Bool) {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before updating metadata lock"
            return
        }

        let uniqueIds = Array(Set(itemIds)).sorted()
        guard !uniqueIds.isEmpty else {
            statusMessage = "Select at least one \(entityLabel) to update metadata lock"
            return
        }

        let lockFields = plexLockFieldNames(for: entityLabel)
        let actionWord = isLocked ? "Locking" : "Unlocking"
        statusMessage = "\(actionWord) Plex metadata for \(uniqueIds.count) \(entityLabel)(s)..."

        Task {
            var successCount = 0
            var failureCount = 0

            for id in uniqueIds {
                do {
                    try await queuePlexMetadataLock(baseURL: serverURL, token: token, itemId: id, lockFields: lockFields, isLocked: isLocked)
                    successCount += 1
                } catch {
                    failureCount += 1
                }
            }

            DispatchQueue.main.async {
                let pastTense = isLocked ? "locked" : "unlocked"
                self.statusMessage = "Plex metadata \(pastTense): \(successCount) succeeded, \(failureCount) failed"
            }
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

    private func normalizePlexServerURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "http://\(trimmed)"
        }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        return trimmed
    }

    private func fetchPlexIdentity(baseURL: URL, token: String) async throws -> PlexServerIdentity {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/identity"
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "PlexTVEditor",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Plex API returned HTTP \(httpResponse.statusCode)"]
            )
        }

        let delegate = PlexIdentityXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(), let identity = delegate.identity else {
            throw NSError(
                domain: "PlexTVEditor",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not parse Plex identity response"]
            )
        }

        return identity
    }

    private func fetchPlexLibrarySections(baseURL: URL, token: String) async throws -> [PlexLibrarySection] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/library/sections"
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "PlexTVEditor",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Plex API returned HTTP \(httpResponse.statusCode)"]
            )
        }

        let delegate = PlexSectionsXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw NSError(
                domain: "PlexTVEditor",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Could not parse Plex library sections response"]
            )
        }

        return delegate.sections
    }

    private func queuePlexMetadataRefresh(baseURL: URL, token: String, itemId: Int) async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/library/metadata/\(itemId)/refresh"
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        func runRequest(method: String) async throws -> HTTPURLResponse {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 12
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return http
        }

        let putResponse = try await runRequest(method: "PUT")
        if (200...299).contains(putResponse.statusCode) {
            return
        }

        // Some Plex endpoints accept GET for refresh on specific versions.
        let getResponse = try await runRequest(method: "GET")
        guard (200...299).contains(getResponse.statusCode) else {
            throw NSError(
                domain: "PlexTVEditor",
                code: getResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Metadata refresh failed for id \(itemId)"]
            )
        }
    }

    private func queuePlexMetadataAnalyze(baseURL: URL, token: String, itemId: Int) async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/library/metadata/\(itemId)/analyze"
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        func runRequest(method: String) async throws -> HTTPURLResponse {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 12
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return http
        }

        let putResponse = try await runRequest(method: "PUT")
        if (200...299).contains(putResponse.statusCode) {
            return
        }

        let getResponse = try await runRequest(method: "GET")
        guard (200...299).contains(getResponse.statusCode) else {
            throw NSError(
                domain: "PlexTVEditor",
                code: getResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Metadata analyze failed for id \(itemId)"]
            )
        }
    }

    private func queuePlexSectionRefresh(baseURL: URL, token: String, sectionKey: String) async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/library/sections/\(sectionKey)/refresh"
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        func runRequest(method: String) async throws -> HTTPURLResponse {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 15
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return http
        }

        let putResponse = try await runRequest(method: "PUT")
        if (200...299).contains(putResponse.statusCode) {
            return
        }

        let getResponse = try await runRequest(method: "GET")
        guard (200...299).contains(getResponse.statusCode) else {
            throw NSError(
                domain: "PlexTVEditor",
                code: getResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Section refresh failed for section \(sectionKey)"]
            )
        }
    }

    private func queuePlexSectionAnalyze(baseURL: URL, token: String, sectionKey: String) async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/library/sections/\(sectionKey)/analyze"
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        func runRequest(method: String) async throws -> HTTPURLResponse {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 15
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return http
        }

        let putResponse = try await runRequest(method: "PUT")
        if (200...299).contains(putResponse.statusCode) {
            return
        }

        let getResponse = try await runRequest(method: "GET")
        guard (200...299).contains(getResponse.statusCode) else {
            throw NSError(
                domain: "PlexTVEditor",
                code: getResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Section analyze failed for section \(sectionKey)"]
            )
        }
    }

    private func queuePlexSectionEmptyTrash(baseURL: URL, token: String, sectionKey: String) async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/library/sections/\(sectionKey)/emptyTrash"
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        func runRequest(method: String) async throws -> HTTPURLResponse {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 20
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return http
        }

        let putResponse = try await runRequest(method: "PUT")
        if (200...299).contains(putResponse.statusCode) {
            return
        }

        let getResponse = try await runRequest(method: "GET")
        guard (200...299).contains(getResponse.statusCode) else {
            throw NSError(
                domain: "PlexTVEditor",
                code: getResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Empty trash failed for section \(sectionKey)"]
            )
        }
    }

    private func queuePlexSectionCancel(baseURL: URL, token: String, sectionKey: String, action: PlexSectionActionKind) async throws {
        let candidates: [(path: String, method: String)] = [
            ("/library/sections/\(sectionKey)/\(action.pathComponent)/cancel", "PUT"),
            ("/library/sections/\(sectionKey)/\(action.pathComponent)/cancel", "POST"),
            ("/library/sections/\(sectionKey)/\(action.pathComponent)", "DELETE")
        ]

        var lastStatusCode: Int?

        for candidate in candidates {
            do {
                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
                components?.path = candidate.path
                components?.queryItems = [
                    URLQueryItem(name: "X-Plex-Token", value: token)
                ]

                guard let url = components?.url else { continue }

                var request = URLRequest(url: url)
                request.httpMethod = candidate.method
                request.timeoutInterval = 12

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }

                if (200...299).contains(http.statusCode) {
                    return
                }

                lastStatusCode = http.statusCode
            } catch {
                continue
            }
        }

        throw NSError(
            domain: "PlexTVEditor",
            code: lastStatusCode ?? -1,
            userInfo: [NSLocalizedDescriptionKey: "Plex server did not accept cancel for this section job"]
        )
    }

    private func queuePlexSectionAction(baseURL: URL, token: String, sectionKey: String, action: PlexSectionActionKind) async throws {
        switch action {
        case .refresh:
            try await queuePlexSectionRefresh(baseURL: baseURL, token: token, sectionKey: sectionKey)
        case .analyze:
            try await queuePlexSectionAnalyze(baseURL: baseURL, token: token, sectionKey: sectionKey)
        case .emptyTrash:
            try await queuePlexSectionEmptyTrash(baseURL: baseURL, token: token, sectionKey: sectionKey)
        }
    }

    private func performTrackedSectionAction(
        baseURL: URL,
        token: String,
        sectionKey: String,
        sectionLabel: String,
        action: PlexSectionActionKind
    ) async throws {
        let jobId = beginSectionJob(sectionKey: sectionKey, sectionLabel: sectionLabel, actionLabel: action.rawValue)
        let retries = max(0, sectionActionMaxRetries)
        let delayNanos = UInt64(max(0, sectionActionRetryDelaySeconds) * 1_000_000_000)

        var lastError: Error?

        for attempt in 0...retries {
            do {
                try await queuePlexSectionAction(baseURL: baseURL, token: token, sectionKey: sectionKey, action: action)
                endSectionJob(jobId: jobId, status: "Queued")
                return
            } catch {
                lastError = error
                if attempt < retries {
                    updateSectionJobStatus(jobId: jobId, status: "Retrying \(attempt + 1)/\(retries)")
                    if delayNanos > 0 {
                        try? await Task.sleep(nanoseconds: delayNanos)
                    }
                }
            }
        }

        endSectionJob(jobId: jobId, status: "Failed")
        throw lastError ?? NSError(domain: "PlexTVEditor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Section action failed"])
    }

    private func beginSectionJob(sectionKey: String, sectionLabel: String, actionLabel: String) -> UUID {
        let job = PlexSectionJobMonitorItem(
            id: UUID(),
            sectionKey: sectionKey,
            sectionLabel: sectionLabel,
            actionLabel: actionLabel,
            startedAt: Date(),
            finishedAt: nil,
            status: "Running"
        )

        DispatchQueue.main.async {
            self.activeSectionJobs.insert(job, at: 0)
            if self.activeSectionJobs.count > 100 {
                self.activeSectionJobs = Array(self.activeSectionJobs.prefix(100))
            }
        }

        return job.id
    }

    private func endSectionJob(jobId: UUID, status: String) {
        DispatchQueue.main.async {
            guard let index = self.activeSectionJobs.firstIndex(where: { $0.id == jobId }) else { return }
            var job = self.activeSectionJobs.remove(at: index)
            job.finishedAt = Date()
            job.status = status
            self.completedSectionJobs.insert(job, at: 0)
            if self.completedSectionJobs.count > 300 {
                self.completedSectionJobs = Array(self.completedSectionJobs.prefix(300))
            }
        }
    }

    private func updateSectionJobStatus(jobId: UUID, status: String) {
        DispatchQueue.main.async {
            guard let index = self.activeSectionJobs.firstIndex(where: { $0.id == jobId }) else { return }
            self.activeSectionJobs[index].status = status
        }
    }

    private func refreshSchedulerTimerState() {
        schedulerTimer?.invalidate()
        schedulerTimer = nil

        guard schedulerEnabled else { return }
        if schedulerNextRunAt == nil {
            schedulerNextRunAt = nextSchedulerRunDate(from: Date())
        }

        schedulerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluateSchedulerTick()
        }
    }

    private func evaluateSchedulerTick() {
        guard schedulerEnabled else { return }
        guard let nextRun = schedulerNextRunAt else {
            schedulerNextRunAt = nextSchedulerRunDate(from: Date())
            return
        }

        guard Date() >= nextRun else { return }

        switch schedulerScope {
        case .tv:
            runBulkPlexSectionMaintenance(sectionType: "show")
        case .movie:
            runBulkPlexSectionMaintenance(sectionType: "movie")
        case .both:
            runBulkPlexSectionMaintenance(sectionType: "show")
            runBulkPlexSectionMaintenance(sectionType: "movie")
        }

        schedulerLastRunAt = Date()
        schedulerNextRunAt = nextSchedulerRunDate(from: Date())
        saveSettings()
        notifyIfEnabled(title: "Scheduled Maintenance", body: "Scheduled Plex maintenance started")
    }

    private func nextSchedulerRunDate(from date: Date) -> Date {
        let calendar = Calendar.current
        switch schedulerFrequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(604800)
        }
    }

    private func runPresetOnSections(preset: PlexSectionActionPreset, sections: [PlexLibrarySection]) {
        let normalizedServerURL = normalizePlexServerURL(plexServerURL)
        guard !normalizedServerURL.isEmpty,
              let serverURL = URL(string: normalizedServerURL) else {
            statusMessage = "Enter a valid Plex server URL"
            return
        }

        let token = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = "Enter Plex token before running preset"
            return
        }

        let actions: [PlexSectionActionKind] = [
            (preset.includeRefresh && plexCapabilities.canRefreshSection) ? .refresh : nil,
            (preset.includeAnalyze && plexCapabilities.canAnalyzeSection) ? .analyze : nil,
            (preset.includeEmptyTrash && plexCapabilities.canEmptyTrashSection) ? .emptyTrash : nil
        ].compactMap { $0 }

        guard !actions.isEmpty else {
            statusMessage = "Preset has no enabled actions"
            return
        }

        isRunningBulkPlexSectionMaintenance = true
        bulkPlexSectionMaintenanceProgress = "0/\(sections.count) sections queued"

        Task {
            var completed = 0
            for section in sections {
                for action in actions {
                    _ = try? await performTrackedSectionAction(
                        baseURL: serverURL,
                        token: token,
                        sectionKey: section.key,
                        sectionLabel: section.title,
                        action: action
                    )
                    DispatchQueue.main.async {
                        self.recordPlexSectionAction(sectionKey: section.key, sectionLabel: section.title, action: action, outcome: "Queued via preset \(preset.name)")
                    }
                }
                completed += 1
                let progress = "\(completed)/\(sections.count) sections queued"
                DispatchQueue.main.async {
                    self.bulkPlexSectionMaintenanceProgress = progress
                }
            }

            DispatchQueue.main.async {
                self.isRunningBulkPlexSectionMaintenance = false
                self.bulkPlexSectionMaintenanceProgress = ""
                self.statusMessage = "Preset \(preset.name) queued for \(sections.count) section(s)"
                self.notifyIfEnabled(title: "Preset Queued", body: "\(preset.name) queued for \(sections.count) section(s)")
            }
        }
    }

    private func fetchTrashCount(baseURL: URL, token: String, sectionKey: String) async throws -> Int {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/library/sections/\(sectionKey)/all"
        components?.queryItems = [
            URLQueryItem(name: "trash", value: "1"),
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let parserDelegate = PlexMediaContainerSizeParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        if parser.parse(), let count = parserDelegate.size {
            return count
        }

        if let xmlText = String(data: data, encoding: .utf8) {
            return xmlText.components(separatedBy: "<Video ").count - 1
        }

        return 0
    }

    private func ensureDefaultPresetsIfNeeded() {
        guard plexActionPresets.isEmpty else { return }
        plexActionPresets = [
            PlexSectionActionPreset(id: UUID(), name: "TV Safe Maintenance", sectionType: "show", includeRefresh: true, includeAnalyze: true, includeEmptyTrash: false, runOnAllSections: false),
            PlexSectionActionPreset(id: UUID(), name: "Movie Safe Maintenance", sectionType: "movie", includeRefresh: true, includeAnalyze: true, includeEmptyTrash: false, runOnAllSections: false),
            PlexSectionActionPreset(id: UUID(), name: "TV Full Cleanup", sectionType: "show", includeRefresh: true, includeAnalyze: true, includeEmptyTrash: true, runOnAllSections: true)
        ]
        selectedPlexPresetId = plexActionPresets.first?.id.uuidString ?? ""
    }

    private func notifyIfEnabled(title: String, body: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func probePlexEndpoint(baseURL: URL, token: String, path: String) async -> Bool {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]

        guard let url = components?.url else { return false }

        let methods = ["OPTIONS", "HEAD"]
        for method in methods {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.timeoutInterval = 8
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                if http.statusCode == 404 { continue }
                return true
            } catch {
                continue
            }
        }

        return false
    }

    private func latestFailedSectionActions(for sectionKeys: Set<String>) -> [PlexSectionActionHistoryEntry] {
        var seen: Set<String> = []
        var results: [PlexSectionActionHistoryEntry] = []

        for entry in plexSectionActionHistory {
            guard sectionKeys.contains(entry.sectionKey) else { continue }
            guard entry.outcome.lowercased().contains("failed") else { continue }

            let dedupeKey = "\(entry.sectionKey)|\(entry.actionLabel)"
            guard !seen.contains(dedupeKey) else { continue }

            seen.insert(dedupeKey)
            results.append(entry)
        }

        return results
    }

    private func rememberQueuedPlexSectionJob(sectionKey: String, sectionLabel: String, action: PlexSectionActionKind) {
        lastQueuedPlexSectionKey = sectionKey
        lastQueuedPlexSectionLabel = sectionLabel
        lastQueuedPlexSectionAction = action.rawValue
    }

    private func clearQueuedPlexSectionJob() {
        lastQueuedPlexSectionKey = ""
        lastQueuedPlexSectionLabel = ""
        lastQueuedPlexSectionAction = ""
    }

    private func recordPlexSectionAction(sectionKey: String, sectionLabel: String, action: PlexSectionActionKind, outcome: String) {
        let entry = PlexSectionActionHistoryEntry(
            timestamp: Date(),
            sectionKey: sectionKey,
            sectionLabel: sectionLabel,
            actionLabel: action.rawValue,
            outcome: outcome
        )

        plexSectionActionHistory.insert(entry, at: 0)
        if plexSectionActionHistory.count > 120 {
            plexSectionActionHistory = Array(plexSectionActionHistory.prefix(120))
        }
    }

    private func queuePlexMetadataLock(baseURL: URL, token: String, itemId: Int, lockFields: [String], isLocked: Bool) async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/library/metadata/\(itemId)"

        let lockValue = isLocked ? "1" : "0"
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]
        queryItems.append(contentsOf: lockFields.map { URLQueryItem(name: "\($0).locked", value: lockValue) })
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        func runRequest(method: String) async throws -> HTTPURLResponse {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 12
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return http
        }

        let putResponse = try await runRequest(method: "PUT")
        if (200...299).contains(putResponse.statusCode) {
            return
        }

        // Some Plex deployments accept POST for metadata update endpoints.
        let postResponse = try await runRequest(method: "POST")
        guard (200...299).contains(postResponse.statusCode) else {
            throw NSError(
                domain: "PlexTVEditor",
                code: postResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Metadata lock failed for id \(itemId)"]
            )
        }
    }

    private func plexLockFieldNames(for entityLabel: String) -> [String] {
        let commonFields = [
            "title",
            "titleSort",
            "summary",
            "originallyAvailableAt",
            "rating",
            "audienceRating",
            "userRating",
            "thumb",
            "art",
            "genre",
            "collection",
            "label",
            "writer",
            "director"
        ]

        if entityLabel.lowercased().contains("movie") {
            return commonFields + [
                "tagline",
                "studio",
                "contentRating",
                "year",
                "originalTitle",
                "country"
            ]
        }

        return commonFields
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

    private func rememberRecentShow(_ showId: Int) {
        recentShowIds.removeAll(where: { $0 == showId })
        recentShowIds.insert(showId, at: 0)
        if recentShowIds.count > 12 {
            recentShowIds = Array(recentShowIds.prefix(12))
        }
    }

    private func logBatchStatusIfNeeded(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lower = trimmed.lowercased()
        let markers = [
            "updated",
            "remap",
            "remapped",
            "failed",
            "synced",
            "applied",
            "created plex season",
            "backup created"
        ]

        guard markers.contains(where: { lower.contains($0) }) else { return }

        let tmdbContextString: String?
        if let context = lastTMDBContext() {
            tmdbContextString = "S\(context.season)E\(context.episode)"
        } else {
            tmdbContextString = nil
        }

        let entry = ChangeLogEntry(
            id: UUID(),
            timestampISO8601: Self.changeLogDateFormatter.string(from: Date()),
            message: trimmed,
            showId: selectedShowId > 0 ? selectedShowId : nil,
            showTitle: shows.first(where: { $0.id == selectedShowId })?.title,
            seasonId: selectedSeasonId > 0 ? selectedSeasonId : nil,
            tmdbShowId: lastResolvedTMDBShowId,
            tmdbContext: tmdbContextString
        )

        changeLogEntries.insert(entry, at: 0)
        if changeLogEntries.count > 1000 {
            changeLogEntries = Array(changeLogEntries.prefix(1000))
        }
    }

    private func csvDataForChangeLog() throws -> Data {
        var rows: [String] = []
        rows.append("timestamp,message,show_id,show_title,season_id,tmdb_show_id,tmdb_context")

        for entry in changeLogEntries {
            let fields: [String] = [
                entry.timestampISO8601,
                entry.message,
                entry.showId.map(String.init) ?? "",
                entry.showTitle ?? "",
                entry.seasonId.map(String.init) ?? "",
                entry.tmdbShowId.map(String.init) ?? "",
                entry.tmdbContext ?? ""
            ]
            rows.append(fields.map(Self.csvEscape).joined(separator: ","))
        }

        let csv = rows.joined(separator: "\n")
        guard let data = csv.data(using: .utf8) else {
            throw NSError(domain: "PlexTVEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode CSV as UTF-8"])
        }
        return data
    }

    private func jsonDataForChangeLog() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(changeLogEntries)
    }

    private func csvDataForSectionActionHistory(entries: [PlexSectionActionHistoryEntry]) throws -> Data {
        var lines: [String] = []
        lines.append("timestamp,section_key,section_label,action,outcome")

        for entry in entries {
            let fields: [String] = [
                Self.changeLogDateFormatter.string(from: entry.timestamp),
                entry.sectionKey,
                entry.sectionLabel,
                entry.actionLabel,
                entry.outcome
            ]
            lines.append(fields.map(Self.csvEscape).joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n")
        guard let data = csv.data(using: .utf8) else {
            throw NSError(domain: "PlexTVEditor", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not encode section history CSV as UTF-8"])
        }
        return data
    }

    private func jsonDataForSectionActionHistory(entries: [PlexSectionActionHistoryEntry]) throws -> Data {
        struct ExportRow: Codable {
            let id: UUID
            let timestampISO8601: String
            let sectionKey: String
            let sectionLabel: String
            let action: String
            let outcome: String
        }

        let payload = entries.map {
            ExportRow(
                id: $0.id,
                timestampISO8601: Self.changeLogDateFormatter.string(from: $0.timestamp),
                sectionKey: $0.sectionKey,
                sectionLabel: $0.sectionLabel,
                action: $0.actionLabel,
                outcome: $0.outcome
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private func csvDataForDryRun(rows: [DryRunDiffRow]) throws -> Data {
        var lines: [String] = []
        lines.append("episode_id,current_code,mapped_code,current_title,mapped_title,current_air_date,mapped_air_date,note")

        for row in rows {
            let fields: [String] = [
                String(row.episodeId),
                row.currentCode,
                row.mappedCode,
                row.currentTitle,
                row.mappedTitle,
                row.currentAirDate,
                row.mappedAirDate,
                row.note
            ]
            lines.append(fields.map(Self.csvEscape).joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n")
        guard let data = csv.data(using: .utf8) else {
            throw NSError(domain: "PlexTVEditor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode dry run CSV as UTF-8"])
        }
        return data
    }

    private func jsonDataForDryRun(rows: [DryRunDiffRow]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rows)
    }

    private func canAcquireExclusiveSQLiteLock(atPath path: String) -> Bool {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            if db != nil {
                sqlite3_close(db)
            }
            return false
        }

        defer {
            sqlite3_close(db)
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let beginResult = sqlite3_exec(db, "BEGIN EXCLUSIVE;", nil, nil, &errorPointer)

        if beginResult != SQLITE_OK {
            if errorPointer != nil {
                sqlite3_free(errorPointer)
            }
            return false
        }

        _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        return true
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
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
    let plexServerURL: String?
    let plexToken: String?
    let selectedPlexTVSectionKey: String?
    let selectedPlexMovieSectionKey: String?
    let plexServerProfiles: [PlexServerProfile]?
    let selectedPlexProfileId: String?
    let plexActionPresets: [PlexSectionActionPreset]?
    let selectedPlexPresetId: String?
    let sectionActionMaxRetries: Int?
    let sectionActionRetryDelaySeconds: Double?
    let schedulerEnabled: Bool?
    let schedulerFrequency: String?
    let schedulerScope: String?
    let schedulerLastRunAt: Date?
    let schedulerNextRunAt: Date?
    let notificationsEnabled: Bool?
    let plexCapabilities: PlexCapabilities?
    let capabilitySummary: String?
}
