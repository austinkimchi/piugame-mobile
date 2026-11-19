import Foundation

/// Authenticated data is fetched separately and is never persisted in PublicCatalogStore.
struct MobileCatalogOverlay: Decodable, Sendable {
    let schemaVersion: Int
    let version: String
    let favoriteSlugs: [String]
    let recommendations: [String: [String: String?]]

    func settingFavorite(_ saved: Bool, slug: String) -> MobileCatalogOverlay {
        var favorites = Set(favoriteSlugs)
        if saved { favorites.insert(slug) } else { favorites.remove(slug) }
        return MobileCatalogOverlay(schemaVersion: schemaVersion, version: version,
                                    favoriteSlugs: favorites.sorted(), recommendations: recommendations)
    }

    func applying(to snapshot: PublicCatalogSnapshot) throws -> CatalogSearchPage {
        guard schemaVersion == 1, version == snapshot.selectedVersion else {
            throw PublicCatalogError.invalidSnapshot
        }
        let favorites = Set(favoriteSlugs)
        let songs = snapshot.defaultPage.songs.map { song in
            CatalogSong(slug: song.slug, title: song.title, artist: song.artist,
                        supportedVersions: song.supportedVersions, imagePath: song.imagePath,
                        bpm: song.bpm, chartSummary: song.chartSummary, folder: song.folder,
                        folderPosition: song.folderPosition, series: song.series, tags: song.tags,
                        isPremium: song.isPremium, isFavorite: favorites.contains(song.slug),
                        recommendedChartToken: recommendations[song.slug]?["all"] ?? nil)
        }
        return CatalogSearchPage(songs: songs, nextCursor: nil, total: snapshot.total,
                                 filterOptions: snapshot.filterOptions)
    }
}
