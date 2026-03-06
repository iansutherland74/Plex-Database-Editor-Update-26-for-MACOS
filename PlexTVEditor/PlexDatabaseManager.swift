import Foundation
import SQLite3

class PlexDatabaseManager {
    let dbPath: String
    let plexSqlitePath: String
    
    init(dbPath: String, plexSqlitePath: String = "/Applications/Plex Media Server.app/Contents/MacOS/Plex SQLite") {
        self.dbPath = dbPath
        self.plexSqlitePath = plexSqlitePath
    }

    private static func sqlLiteral(_ raw: String) -> String {
        let escaped = raw.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }

    private static func parseChangesCount(_ output: String) -> Int {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            if let value = Int(line) {
                return value
            }
        }
        return 0
    }

    private static func parseLastInt(_ output: String) -> Int? {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            if let value = Int(line), value > 0 {
                return value
            }
        }
        return nil
    }

    private func runPlexSQLite(sql: String) -> String? {
        // Write operations are routed through Plex SQLite to match Plex's expected DB handling.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plexSqlitePath)
        process.arguments = [dbPath, sql]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                print("Plex SQLite write failed: \(errorText)")
                return nil
            }

            return String(data: outputData, encoding: .utf8) ?? ""
        } catch {
            print("Failed to run Plex SQLite at \(plexSqlitePath): \(error)")
            return nil
        }
    }
    
    // MARK: - Shows
    
    func getShows() -> [PlexShow] {
        var shows: [PlexShow] = []
        var db: OpaquePointer?
        
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("Failed to open database at \(dbPath)")
            return []
        }
        defer { sqlite3_close(db) }
        
        // Query for type=2 (TV shows)
        let query = """
        SELECT id, title, year
        FROM metadata_items
        WHERE metadata_type = 2
        ORDER BY title COLLATE NOCASE
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("Failed to prepare query")
            return []
        }
        defer { sqlite3_finalize(statement) }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let year = Int(sqlite3_column_int(statement, 2))
            
            shows.append(PlexShow(id: id, title: title, year: year > 0 ? year : nil))
        }
        
        return shows
    }

    // MARK: - Movies

    func getMovies() -> [PlexMovie] {
        var movies: [PlexMovie] = []
        var db: OpaquePointer?

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("Failed to open database at \(dbPath)")
            return []
        }
        defer { sqlite3_close(db) }

        // Query for type=1 (movies)
        let query = """
        SELECT id, title, year
        FROM metadata_items
        WHERE metadata_type = 1
        ORDER BY title COLLATE NOCASE
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("Failed to prepare movies query")
            return []
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let year = Int(sqlite3_column_int(statement, 2))

            movies.append(PlexMovie(id: id, title: title, year: year > 0 ? year : nil))
        }

        return movies
    }
    
    // MARK: - Seasons
    
    func getSeasons(for showId: Int) -> [Season] {
        var seasons: [Season] = []
        var db: OpaquePointer?
        
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        
        let query = """
        SELECT
            s.id,
            s."index" AS season_number,
            (SELECT COUNT(*) FROM metadata_items e WHERE e.parent_id = s.id AND e.metadata_type = 4) AS episode_count
        FROM metadata_items s
        WHERE s.parent_id = ? AND s.metadata_type = 3
        ORDER BY s."index"
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(showId))
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let seasonId = Int(sqlite3_column_int(statement, 0))
            let seasonNumber = Int(sqlite3_column_int(statement, 1))
            let episodeCount = Int(sqlite3_column_int(statement, 2))
            seasons.append(Season(id: seasonId, season_number: seasonNumber, episode_count: episodeCount))
        }
        
        return seasons
    }

    func getSeasonId(for showId: Int, seasonNumber: Int) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let query = """
        SELECT id
        FROM metadata_items
        WHERE parent_id = ? AND metadata_type = 3 AND "index" = ?
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(showId))
        sqlite3_bind_int(statement, 2, Int32(seasonNumber))

        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }

        return nil
    }

    func ensureSeasonId(for showId: Int, seasonNumber: Int) -> Int? {
        if let existing = getSeasonId(for: showId, seasonNumber: seasonNumber) {
            return existing
        }

        let now = Int(Date().timeIntervalSince1970)
        let seasonTitle = "Season \(seasonNumber)"

        let query = """
        BEGIN IMMEDIATE;
        INSERT INTO metadata_items (
            library_section_id,
            parent_id,
            metadata_type,
            title,
            title_sort,
            "index",
            added_at,
            created_at,
            updated_at,
            changed_at,
            resources_changed_at
        )
        SELECT
            library_section_id,
            \(showId),
            3,
            \(Self.sqlLiteral(seasonTitle)),
            \(Self.sqlLiteral(seasonTitle)),
            \(seasonNumber),
            \(now),
            \(now),
            \(now),
            \(now),
            \(now)
        FROM metadata_items
        WHERE id = \(showId) AND metadata_type = 2
        LIMIT 1;

        SELECT id
        FROM metadata_items
        WHERE parent_id = \(showId) AND metadata_type = 3 AND "index" = \(seasonNumber)
        ORDER BY id DESC
        LIMIT 1;
        COMMIT;
        """

        guard let output = runPlexSQLite(sql: query) else {
            return nil
        }

        return Self.parseLastInt(output)
    }
    
    // MARK: - Episodes
    
    func getEpisodes(for seasonId: Int) -> [Episode] {
        var episodes: [Episode] = []
        var db: OpaquePointer?
        
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        
        let query = """
        SELECT
            e.id,
            COALESCE(s."index", 0) AS season_number,
            e."index" AS episode_number,
            e.title,
            datetime(e.originally_available_at, 'unixepoch') AS air_date,
            e.user_thumb_url
        FROM metadata_items e
        LEFT JOIN metadata_items s ON s.id = e.parent_id
        WHERE e.parent_id = ? AND e.metadata_type = 4
        ORDER BY e."index"
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(seasonId))
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let seasonNum = Int(sqlite3_column_int(statement, 1))
            let episodeNum = Int(sqlite3_column_int(statement, 2))
            let title = String(cString: sqlite3_column_text(statement, 3))
            let airDate = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            let thumbURL = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            
            episodes.append(Episode(
                id: id,
                season_number: seasonNum,
                episode_number: episodeNum,
                name: title,
                air_date: airDate,
                still_path: thumbURL
            ))
        }
        
        return episodes
    }
    
    // MARK: - Update Operations

    func remapEpisode(
        episodeId: Int,
        seasonId: Int,
        episodeNumber: Int,
        title: String?,
        airDateUnix: Int64?,
        summary: String?,
        year: Int?,
        thumbURL: String?,
        artURL: String?,
        bannerURL: String?,
        squareArtURL: String?
    ) -> Bool {
        // One transaction keeps S/E remap + metadata/artwork updates atomic.
        let now = Int(Date().timeIntervalSince1970)
        let titleExpr = title.map { Self.sqlLiteral($0) } ?? "title"
        let titleSortExpr = title.map { Self.sqlLiteral($0) } ?? "title_sort"
        let originalTitleExpr = title.map { Self.sqlLiteral($0) } ?? "original_title"
        let airDateExpr = airDateUnix.map { String($0) } ?? "originally_available_at"
        let summaryExpr = summary.map { Self.sqlLiteral($0) } ?? "summary"
        let yearExpr = year.map { String($0) } ?? "year"
        let thumbExpr = thumbURL.map { Self.sqlLiteral($0) } ?? "user_thumb_url"
        let artExpr = artURL.map { Self.sqlLiteral($0) } ?? "user_art_url"
        let bannerExpr = bannerURL.map { Self.sqlLiteral($0) } ?? "user_banner_url"
        let squareArtExpr = squareArtURL.map { Self.sqlLiteral($0) } ?? "user_square_art_url"

        let query = """
        BEGIN IMMEDIATE;
        -- If another episode already occupies target S/E, move it to the end of that season.
        -- This keeps the target slot free for the remapped file and avoids refilling the source slot.
        UPDATE metadata_items
        SET
            "index" = (
                SELECT COALESCE(MAX(mi."index"), 0) + 1
                FROM metadata_items mi
                WHERE mi.parent_id = \(seasonId) AND mi.metadata_type = 4 AND mi.id != metadata_items.id
            ),
            updated_at = \(now),
            changed_at = \(now),
            resources_changed_at = \(now)
        WHERE
            parent_id = \(seasonId)
            AND metadata_type = 4
            AND "index" = \(episodeNumber)
            AND id != \(episodeId);

        UPDATE metadata_items
        SET
            parent_id = \(seasonId),
            "index" = \(episodeNumber),
            title = \(titleExpr),
            title_sort = \(titleSortExpr),
            original_title = \(originalTitleExpr),
            originally_available_at = \(airDateExpr),
            summary = \(summaryExpr),
            year = \(yearExpr),
            user_thumb_url = \(thumbExpr),
            user_art_url = \(artExpr),
            user_banner_url = \(bannerExpr),
            user_square_art_url = \(squareArtExpr),
            refreshed_at = \(now),
            updated_at = \(now),
            changed_at = \(now),
            resources_changed_at = \(now)
        WHERE id = \(episodeId) AND metadata_type = 4;
        SELECT changes();
        UPDATE media_items
        SET updated_at = \(now)
        WHERE metadata_item_id = \(episodeId);
        UPDATE media_parts
        SET updated_at = \(now)
        WHERE media_item_id IN (
            SELECT id
            FROM media_items
            WHERE metadata_item_id = \(episodeId)
        );
        COMMIT;
        """

        guard let output = runPlexSQLite(sql: query) else {
            return false
        }

        return Self.parseChangesCount(output) > 0
    }

    func updateEpisodeThumbnail(
        episodeId: Int,
        thumbURL: String,
        artURL: String? = nil,
        bannerURL: String? = nil,
        squareArtURL: String? = nil
    ) -> Bool {
        // Keep artwork fields and timestamps in sync so Plex notices changes promptly.
        let now = Int(Date().timeIntervalSince1970)
        let thumbExpr = Self.sqlLiteral(thumbURL)
        let artExpr = artURL.map { Self.sqlLiteral($0) } ?? "user_art_url"
        let bannerExpr = bannerURL.map { Self.sqlLiteral($0) } ?? "user_banner_url"
        let squareArtExpr = squareArtURL.map { Self.sqlLiteral($0) } ?? "user_square_art_url"

        let query = """
        BEGIN IMMEDIATE;
        UPDATE metadata_items
        SET
            user_thumb_url = \(thumbExpr),
            user_art_url = \(artExpr),
            user_banner_url = \(bannerExpr),
            user_square_art_url = \(squareArtExpr),
            refreshed_at = \(now),
            updated_at = \(now),
            changed_at = \(now),
            resources_changed_at = \(now)
        WHERE id = \(episodeId) AND metadata_type = 4;
        SELECT changes();
        UPDATE media_items
        SET updated_at = \(now)
        WHERE metadata_item_id = \(episodeId);
        UPDATE media_parts
        SET updated_at = \(now)
        WHERE media_item_id IN (
            SELECT id
            FROM media_items
            WHERE metadata_item_id = \(episodeId)
        );
        COMMIT;
        """

        guard let output = runPlexSQLite(sql: query) else {
            return false
        }

        return Self.parseChangesCount(output) > 0
    }

    func updateSeasonPoster(
        seasonId: Int,
        posterURL: String,
        artURL: String? = nil,
        bannerURL: String? = nil,
        squareArtURL: String? = nil
    ) -> Bool {
        // Season artwork uses the same metadata_items artwork columns as episodes.
        let now = Int(Date().timeIntervalSince1970)
        let posterExpr = Self.sqlLiteral(posterURL)
        let artExpr = artURL.map { Self.sqlLiteral($0) } ?? "user_art_url"
        let bannerExpr = bannerURL.map { Self.sqlLiteral($0) } ?? "user_banner_url"
        let squareArtExpr = squareArtURL.map { Self.sqlLiteral($0) } ?? "user_square_art_url"

        let query = """
        BEGIN IMMEDIATE;
        UPDATE metadata_items
        SET
            user_thumb_url = \(posterExpr),
            user_art_url = \(artExpr),
            user_banner_url = \(bannerExpr),
            user_square_art_url = \(squareArtExpr),
            refreshed_at = \(now),
            updated_at = \(now),
            changed_at = \(now),
            resources_changed_at = \(now)
        WHERE id = \(seasonId) AND metadata_type = 3;
        SELECT changes();
        COMMIT;
        """

        guard let output = runPlexSQLite(sql: query) else {
            return false
        }

        return Self.parseChangesCount(output) > 0
    }

    func updateMetadataDates(itemIds: [Int], date: Date) -> Int {
        guard !itemIds.isEmpty else { return 0 }

        let unixTime = Int64(date.timeIntervalSince1970)
        let idList = itemIds.map(String.init).joined(separator: ",")
        let query = """
        BEGIN IMMEDIATE;
        UPDATE metadata_items
        SET
            originally_available_at = \(unixTime),
            updated_at = CAST(strftime('%s','now') AS INTEGER),
            changed_at = CAST(strftime('%s','now') AS INTEGER),
            resources_changed_at = CAST(strftime('%s','now') AS INTEGER)
        WHERE id IN (\(idList));
        SELECT changes();
        COMMIT;
        """

        guard let output = runPlexSQLite(sql: query) else {
            return 0
        }

        return Self.parseChangesCount(output)
    }
    
    func updateEpisodeDate(episodeId: Int, date: Date) -> Bool {
        return updateMetadataDates(itemIds: [episodeId], date: date) == 1
    }
    
    func createBackup() -> String? {
        // Backups are timestamped and stored outside the Plex DB folder for safer rollback.
        let fileManager = FileManager.default
        let backupDir = (NSHomeDirectory() as NSString).appendingPathComponent(".plex_tv_editor_backups")
        
        do {
            try fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true, attributes: nil)
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            let backupPath = (backupDir as NSString).appendingPathComponent("plex_\(timestamp).db")
            
            try fileManager.copyItem(atPath: dbPath, toPath: backupPath)
            return backupPath
        } catch {
            print("Backup failed: \(error)")
            return nil
        }
    }
    
    // MARK: - File Path & 3D Detection
    
    func getFilePath(forItemId itemId: Int) -> String? {
        var db: OpaquePointer?
        
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("Failed to open database")
            return nil
        }
        defer { sqlite3_close(db) }
        
        let query = """
        SELECT mp.file
        FROM media_parts mp
        JOIN media_items mi ON mp.media_item_id = mi.id
        WHERE mi.metadata_item_id = ?
        LIMIT 1
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("Failed to prepare getFilePath query")
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(itemId))
        
        if sqlite3_step(statement) == SQLITE_ROW,
           let cString = sqlite3_column_text(statement, 0) {
            return String(cString: cString)
        }
        
        return nil
    }
    
    static func detect3DFormat(fromPath path: String) -> String? {
        let upperPath = path.uppercased()
        
        // Full Side-By-Side variants
        if upperPath.contains("FSBS") || upperPath.contains("FULL-SBS") || upperPath.contains("FULLSBS") {
            return "FSBS"
        }
        
        // Half Side-By-Side variants
        if upperPath.contains("HSBS") || upperPath.contains("HALF-SBS") || upperPath.contains("HALFSBS") {
            return "HSBS"
        }
        
        // Generic Side-By-Side (treat as half)
        if upperPath.contains("SBS") || upperPath.contains("SIDE-BY-SIDE") || upperPath.contains("SIDEBYSIDE") {
            return "SBS"
        }
        
        // Full Top-And-Bottom variants
        if upperPath.contains("FTAB") || upperPath.contains("FULL-TAB") || upperPath.contains("FULLTAB") ||
           upperPath.contains("FOU") || upperPath.contains("FULL-OU") {
            return "FTAB"
        }
        
        // Half Top-And-Bottom variants
        if upperPath.contains("HTAB") || upperPath.contains("HALF-TAB") || upperPath.contains("HALFTAB") ||
           upperPath.contains("HOU") || upperPath.contains("HALF-OU") {
            return "HTAB"
        }
        
        // Generic Top-And-Bottom or Over-Under
        if upperPath.contains("TAB") || upperPath.contains("TOP-AND-BOTTOM") ||
           upperPath.contains("OU") || upperPath.contains("OVER-UNDER") {
            return "TAB"
        }
        
        // MVC (Multi-View Coding - Blu-ray 3D)
        if upperPath.contains("MVC") || upperPath.contains("3DBD") || upperPath.contains("3D-BD") {
            return "3D"
        }
        
        // Generic 3D marker (if nothing else matched)
        if upperPath.contains(".3D.") || upperPath.contains("_3D_") || upperPath.contains("-3D-") ||
           upperPath.contains(" 3D ") || upperPath.contains("[3D]") || upperPath.contains("(3D)") {
            return "3D"
        }
        
        return nil
    }
    
    func updateEdition(itemId: Int, edition: String) -> Bool {
        guard createBackup() != nil else {
            print("Failed to create backup before updating edition")
            return false
        }

        let now = Int(Date().timeIntervalSince1970)

        let query = """
        BEGIN IMMEDIATE;
        UPDATE metadata_items
        SET
            edition_title = \(Self.sqlLiteral(edition)),
            updated_at = \(now),
            changed_at = \(now),
            resources_changed_at = \(now)
        WHERE id = \(itemId);
        SELECT changes();
        COMMIT;
        """

        guard let output = runPlexSQLite(sql: query) else {
            return false
        }

        return Self.parseChangesCount(output) > 0
    }
}
