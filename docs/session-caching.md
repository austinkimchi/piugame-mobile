# Session history caching

Sessions keeps its latest history in memory and can restore a saved first page after the current MyPIU account is verified. A fresh `/me` check runs alongside the Sessions request. Saved rows can appear while that request is pending, with a saved-at label; a successful network page replaces them. Refresh failures retain visible history and provide a retry. This does not add offline authentication.

The private cache is separate from public catalog/image caches. Its schema-1 key includes server origin, account ID, performance version and a SHA-256 token fingerprint. It stores no access token, password, email or profile. iOS files use data protection and backup exclusion; Android uses the app-private cache directory already excluded from app backup.

Only an exact first page of at most 20 sessions is saved, for at most 24 hours. Each encoded entry is limited to 2 MiB and total retained/staging bytes to 4 MiB across the current account's two versions. Oversized pages remain fully visible from the network but are not truncated for storage. Corrupt, expired, future-dated or unknown-schema files are cache misses. Disk errors cannot turn a successful network response into an error.

The server must return `selectedVersion` from the same account preference used for its play and artwork query. Missing, null, unknown or preference-mismatched versions remain displayable but are not persisted. This is backward compatible with older servers. A cached page never enables its saved continuation offset; pagination begins only after a fresh first page is published.

Account/token changes, logout, authorization rejection and imports fence old requests and writes. Storage clears complete before new cache IO, so an older cleanup cannot erase a newer saved page. A late read cannot overwrite fresh UI, and a late old-token success or error cannot invalidate the replacement Android session.

Tests use synthetic history fixtures and disposable directories. They cover identity/version isolation, byte/age bounds, corruption, failed storage, cached-first publication, fresh-page precedence, cursor gating, cancellation, account replacement and late callbacks. Authenticated Simulator timing and physical-device measurements are separate acceptance work; no speedup number is inferred from unit tests.
