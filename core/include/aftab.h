/*
 * aftab.h — public C-ABI of libaftab (Aftab Media core, آفتاب مدیا).
 *
 * This is the contract the Flutter application links against. It is stable:
 * symbols are additive-only; error codes are never renumbered.
 *
 * Ownership rules
 * ---------------
 *  - Strings returned as `char *` are heap allocations owned by the caller
 *    and must be released with `aftab_free_string`.
 *  - Handles (`aftab_provider_*`, `aftab_store_*`) are opaque pointers owned
 *    by the caller and released with the matching `*_free` function.
 *  - `const char *` returns (version, last-error message) belong to the
 *    library and stay valid until the next call on the same thread.
 *
 * Error rules
 * -----------
 *  - Pointer-returning functions signal failure with NULL; the cause is in
 *    the thread-local last-error (code + message).
 *  - `aftab_search_score` returns -1 for "no match" and -2 for bad input.
 *  - `aftab_download_file` returns -1 on failure, byte count on success.
 *  - Boolean-style returns: 1 = true/success, 0 = false/failure.
 *
 * Threading
 * ---------
 *  All functions are thread-safe. The last-error slot is per-thread.
 *  Provider calls are read-only and may run concurrently on one handle;
 *  store calls serialize internally.
 */

#ifndef AFTAB_H
#define AFTAB_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Stable error codes (mirror of Rust `error::codes`) ────────────────── */

#define AFTAB_OK                0
#define AFTAB_NETWORK           1
#define AFTAB_BAD_RESPONSE      2
#define AFTAB_PARSE             3
#define AFTAB_BAD_URL           4
#define AFTAB_UNSAFE_URL        5
#define AFTAB_UNSUPPORTED_SCHEME 6
#define AFTAB_IO                7
#define AFTAB_INVALID_ARGUMENT  8
#define AFTAB_STORAGE           9
#define AFTAB_NOT_FOUND         10
#define AFTAB_OUT_OF_MEMORY     11
#define AFTAB_UNKNOWN           99

/* ── Sort filters (aftab_provider_movies / _series / _country_posters) ──── */

#define AFTAB_FILTER_DEFAULT    0   /* newest first            */
#define AFTAB_FILTER_BY_YEAR    1   /* highest year first      */
#define AFTAB_FILTER_BY_IMDB    2   /* highest IMDb score first */

/* ── Version & errors ───────────────────────────────────────────────────── */

/* Library version, e.g. "0.1.0". Static storage; do not free. */
const char *aftab_version(void);

/* Error code of the last failure on this thread (AFTAB_OK when none). */
int32_t aftab_last_error_code(void);

/* Message of the last failure on this thread (NULL when none). Library
 * storage; valid until the next call on the same thread. Do not free. */
const char *aftab_last_error_message(void);

/* ── String & text utilities ────────────────────────────────────────────── */

/* Free a heap string returned by this library. NULL is a no-op. */
void aftab_free_string(char *s);

/* Canonical Persian normalization (display/storage form). NULL on error. */
char *aftab_normalize_persian(const char *input);

/* Compact matching key (ZWNJ/madda/digit-insensitive). NULL on error. */
char *aftab_compact_key(const char *input);

/* 1 if the two strings are Persian-equal, else 0. */
int32_t aftab_persian_equals(const char *a, const char *b);

/* Search score of query vs candidate (>= 25 when matched), -1 no match,
 * -2 bad input. */
int32_t aftab_search_score(const char *query, const char *candidate);

/* ── URL safety ─────────────────────────────────────────────────────────── */

/* 1 if the URL passes the strict media-safety policy (http/https, no
 * userinfo, public host — SSRF guard), else 0 with last-error set. */
int32_t aftab_url_is_safe(const char *url);

/* Redact a URL for logging: keeps scheme/host/port, drops path/query.
 * Caller frees. NULL on bad input pointer. */
char *aftab_redact_url(const char *url);

/* ── Provider (catalog client with failover) ────────────────────────────── */

typedef struct AftabProvider AftabProvider; /* opaque */

/* Provider with upstream defaults (base, helpers, API key). NULL on error. */
AftabProvider *aftab_provider_default(void);

/* Provider with explicit configuration. `helper_servers` is a
 * comma-separated list ("https://a.example,https://b.example") or NULL for
 * no failover. NULL on error. */
AftabProvider *aftab_provider_new(const char *base_url,
                                  const char *api_key,
                                  const char *helper_servers);

void aftab_provider_free(AftabProvider *p);

/* Catalog calls. Each returns a JSON string (caller frees) — arrays for
 * movies/series/posters/genres/countries/seasons, an object for search —
 * or NULL on failure with last-error set. Field shapes are documented in
 * docs/PROVIDER-API.md.
 *
 *   movies:          genre (0 = all), filter (AFTAB_FILTER_*), page (0-based)
 *   series:          genre, filter, page
 *   country_posters: country id, filter, page
 *   search:          free-text query (Persian normalization applied to the
 *                    encoding, not the wire)
 *   seasons:         series id
 */
char *aftab_provider_movies(AftabProvider *p, int64_t genre,
                            int32_t filter, uint32_t page);
char *aftab_provider_series(AftabProvider *p, int64_t genre,
                            int32_t filter, uint32_t page);
char *aftab_provider_country_posters(AftabProvider *p, int64_t country,
                                     int32_t filter, uint32_t page);
char *aftab_provider_search(AftabProvider *p, const char *query);
char *aftab_provider_genres(AftabProvider *p);
char *aftab_provider_countries(AftabProvider *p);
char *aftab_provider_seasons(AftabProvider *p, int64_t series_id);

/* Probe base + helper servers. Returns a JSON array of
 * {"server": "scheme://host[:port]", "ok": bool} in probe order.
 * Caller frees. NULL on error. */
char *aftab_provider_health(AftabProvider *p);

/* ── Store (favorites / progress / settings) ────────────────────────────── */

typedef struct AftabStore AftabStore; /* opaque */

/* Open or create the store at `path`. NULL on error. */
AftabStore *aftab_store_open(const char *path);

void aftab_store_free(AftabStore *s);

/* Favorites as a JSON array, newest first. Caller frees. NULL on error. */
char *aftab_store_favorites_json(AftabStore *s);

/* Add a favorite from a FavoriteItem-shaped JSON object:
 * {"id": 5, "type": "movie", "title": "...", "image": "...",
 *  "year": 2024, "added_at": 1700000000}. 1 on success, 0 on failure. */
int32_t aftab_store_add_favorite(AftabStore *s, const char *json);

/* Remove a favorite. 1 if it existed, 0 otherwise. */
int32_t aftab_store_remove_favorite(AftabStore *s, const char *kind,
                                    int64_t id);

/* 1 if favorited, 0 otherwise. */
int32_t aftab_store_is_favorite(AftabStore *s, const char *kind, int64_t id);

/* Record playback progress in seconds. 1 on success, 0 on failure. */
int32_t aftab_store_set_progress(AftabStore *s, const char *kind, int64_t id,
                                 double position, double duration);

/* Progress for one item as a JSON object, or the string "null" when none.
 * Caller frees. NULL on error. */
char *aftab_store_progress_json(AftabStore *s, const char *kind, int64_t id);

/* Every progress entry, newest first, as a JSON array of
 * {kind, id, progress:{position,duration,updated_at}} — the
 * "continue watching" / history feed. Caller frees. NULL on error. */
char *aftab_store_progress_all_json(AftabStore *s);

/* Clear progress. 1 if it existed, 0 otherwise. */
int32_t aftab_store_clear_progress(AftabStore *s, const char *kind,
                                   int64_t id);

/* Settings map. 1 on success, 0 on failure. */
int32_t aftab_store_set_setting(AftabStore *s, const char *name,
                                const char *value);

/* Read a setting (caller frees), or NULL when unset. Distinguish unset
 * from error via `aftab_last_error_code()`. */
char *aftab_store_get_setting(AftabStore *s, const char *name);

/* ── Download ───────────────────────────────────────────────────────────── */

/* Synchronously download `url` to `dest_path`. Returns the byte count, or
 * -1 on failure (last-error set). `allow_private` must be 0 in production;
 * non-zero exists for local fixture tooling only. */
int64_t aftab_download_file(const char *url, const char *dest_path,
                            int32_t allow_private);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* AFTAB_H */
