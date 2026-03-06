import Foundation

class TMDBClient {
    private let baseURL = "https://api.themoviedb.org/3"
    
    // MARK: - Search
    
    func searchShows(query: String, apiKey: String) async throws -> [TMDBShow] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/search/tv?api_key=\(apiKey)&query=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.results
    }
    
    // MARK: - Show Details
    
    func getShowInfo(showId: Int, apiKey: String) async throws -> TMDBShow {
        let urlString = "\(baseURL)/tv/\(showId)?api_key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBShow.self, from: data)
    }
    
    // MARK: - Seasons
    
    func getSeason(showId: Int, seasonNumber: Int, apiKey: String) async throws -> TMDBSeasonResponse {
        let urlString = "\(baseURL)/tv/\(showId)/season/\(seasonNumber)?api_key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBSeasonResponse.self, from: data)
    }
    
    // MARK: - Episodes
    
    func getEpisodes(showId: Int, seasonNumber: Int, apiKey: String) async throws -> [Episode] {
        let season = try await getSeason(showId: showId, seasonNumber: seasonNumber, apiKey: apiKey)
        return season.episodes?.map { ep in
            Episode(
                id: ep.id,
                season_number: ep.season_number,
                episode_number: ep.episode_number,
                name: ep.name,
                air_date: ep.air_date,
                still_path: ep.still_path
            )
        } ?? []
    }
    
    // MARK: - Images
    
    func getPosterURL(posterPath: String) -> URL? {
        let imageBaseURL = "https://image.tmdb.org/t/p/w342"
        return URL(string: "\(imageBaseURL)\(posterPath)")
    }

    func getStillURL(stillPath: String) -> URL? {
        let imageBaseURL = "https://image.tmdb.org/t/p/w780"
        return URL(string: "\(imageBaseURL)\(stillPath)")
    }
}

// MARK: - API Response Models

struct SearchResponse: Codable {
    let results: [TMDBShow]
    let total_results: Int
    let total_pages: Int
}

struct TMDBSeasonResponse: Codable {
    let season_number: Int
    let poster_path: String?
    let episodes: [TMDBEpisodeResponse]?
}

struct TMDBEpisodeResponse: Codable {
    let id: Int
    let episode_number: Int
    let season_number: Int
    let name: String
    let air_date: String?
    let overview: String?
    let still_path: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case episode_number
        case season_number
        case name
        case air_date
        case overview
        case still_path
    }
}
