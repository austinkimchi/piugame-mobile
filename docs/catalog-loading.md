# Catalog loading

The default Songs catalog uses `GET /api/catalog/v1/{version}` plus the bearer-authenticated `/api/mobile/v1/catalog/overlay?version=...` for signed-in users. The overlay supplies favorites and per-song chart hints. Search, custom filters/sorts, favorites, and recommendation feeds retain their existing endpoints and behavior.

Public snapshots use a separate typed disk cache per game version, conditional ETag requests, and shared in-flight downloads. Only validated schema-1 supported views with matching version, unique slugs, and `total == songs.count` enter this cache. It contains no account favorites or recommendations. Account catalog results remain in the existing account/version-scoped cache; old responses cannot replace a newer account/query, and favorite mutations made during a fetch take precedence. Successful imports refresh chart hints.

Saved rows remain visible while refreshing; refresh errors offer retry. A cold legacy server publishes its first page before fetching remaining pages. Only a missing snapshot/overlay endpoint (HTTP 404) permits that fallback. Failed, repeated, or capped page walks never become complete snapshots. The display preserves default series-descending Mongo binary order; it does not display the API's slug ordering.

On iOS, Home artwork reads the public cache immediately and revalidates it, preferring the selected game before filling missing titles from the other game. Android restores the public artwork index while loading the catalog. Shared image downloads and disk image caching are provided by the existing platform image loaders.

Validation for this change: 88 iOS unit tests passed after integration with Sessions caching, including 15 snapshot/overlay/loading tests. The exact Swift comparator matched all 675 Phoenix 2 and 639 Phoenix records in the captured legacy default ordering. Android has corresponding cache, transport, progressive-loading, error, and import tests; its Gradle checks run in CI because this Mac has no Android SDK. No physical-device update is part of this change.
