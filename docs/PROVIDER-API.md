# The Provider API contract

<div dir="rtl">

این سند قرارداد سیمی میان هستهٔ Rust و سرورهای کاتالوگ را مشخص می‌کند —
دقیقاً همان قراردادی که اپ اصلی CCloud رعایت می‌کند. هستهٔ آفتاب این
قرارداد را بدون تغییر حفظ کرده است تا با سرورهای موجود سازگار بماند؛
تنها بهبود، «قابل‌مشاهده‌شدن» تعویض سرور و آزمون‌پذیری کامل است.

</div>

## Base configuration

| Setting | Value (upstream defaults) |
|---|---|
| Primary base | `https://server-hi-speed-iran.info` |
| Helper server 1 | `https://hostinnegar.com` |
| Helper server 2 | `https://windowsdiba.info` |
| API key | path segment `4F5A9C3D9A86FA54EACEDDD635185` |

The API key is part of the URL path, not a header — inherited behavior
that this client preserves verbatim.

## Endpoints

All calls are plain `GET`s; responses are JSON; no auth headers.

### Movies

```
GET /api/movie/by/filtres/{genreId}/{sort}/{page}/{API_KEY}
```

- `genreId` — `0` for all genres.
- `sort` — `created` (newest) | `year` | `imdb`.
- `page` — 0-based.

Response: JSON **array** of movie objects.

```json
[{
  "id": 12,
  "type": "movie",
  "title": "گوشه",
  "description": "…",
  "year": 2023,
  "imdb": 7.4,
  "rating": 8.1,
  "duration": "1h 52m",
  "image": "https://…/poster.jpg",
  "cover": "https://…/cover.jpg",
  "genres":  [{"id": 1, "title": "اکشن"}],
  "sources": [{"id": 9, "quality": "1080", "type": "mp4", "url": "https://…/v.mp4"}],
  "country": [{"id": 3, "title": "ایران", "image": "https://…/ir.png"}]
}]
```

### Series

```
GET /api/serie/by/filtres/{genreId}/{sort}/{page}/{API_KEY}
```

Same shape as movies **without** `sources` (series carry sources
per-episode — see Seasons).

### Country posters

```
GET /api/poster/by/filtres/0/{countryId}/{sort}/{page}/{API_KEY}
```

Note the literal `0` genre slot. Response: array of poster objects (movie
shape, `type` may be `movie` or `serie`).

### Search

```
GET /api/search/{percentEncodedQuery}/{API_KEY}/
```

- The query is UTF-8 percent-encoded as a **path segment**: spaces are
  `%20` (never `+` — the upstream Kotlin `URLEncoder.encode` needed a
  `.replace("+", "%20")` patch for exactly this reason).
- Trailing slash after the key.

Response: an **object**, not an array:

```json
{"posters": [ { …poster objects… } ]}
```

### Genres

```
GET /api/genre/all/{API_KEY}
```

Response: `[{"id": 1, "title": "اکشن"}, …]`

### Countries

```
GET /api/country/all/{API_KEY}/
```

Response: `[{"id": 3, "title": "ایران", "image": "…"}]`

### Seasons & episodes

```
GET /api/season/by/serie/{seriesId}/{API_KEY}/
```

Response: array of seasons, each with nested episodes and their sources:

```json
[{
  "id": 1,
  "title": "فصل اول",
  "episodes": [{
    "id": 10,
    "title": "قسمت ۱",
    "description": "…",
    "duration": "45m",
    "image": "https://…/e10.jpg",
    "sources": [
      {"id": 100, "quality": "1080", "type": "mp4", "url": "https://…/e10-1080.mp4"},
      {"id": 101, "quality": "720",  "type": "mkv", "url": "https://…/e10-720.mkv"}
    ]
  }]
}]
```

## Failover semantics

Exactly as implemented by upstream's `BaseRepository.executeRequest`:

1. Try the primary base.
2. On a **transport error** (DNS, connect, read, timeout) **or any
   non-2xx status**, retry the identical path against each helper server
   in order — the host is swapped, path and (empty) query preserved:
   `https://server-hi-speed-iran.info/api/…` →
   `https://hostinnegar.com/api/…` →
   `https://windowsdiba.info/api/…`.
3. The first server to answer 2xx wins.
4. If every server fails, the **primary's** error is surfaced (upstream
   throws `primaryException`); the Aftab core additionally records which
   helpers were tried in the error message.

Health probing (`aftab_provider_health`) hits the site root of each
server in order; any HTTP answer (even a 404) counts as "reachable",
transport errors count as "down". Probe results are logged with
**redacted** URLs (scheme/host/port only — no paths, no keys).

## Tolerance rules (pinned by tests)

- A malformed item inside a response array is **skipped**; the rest of the
  page parses. (Upstream: `catch { continue }`.)
- An array where **every** item is malformed is a parse error, not an
  empty list — silently showing nothing would be worse than failing loud.
- Missing scalar fields default (`0` / `""` / `null`), matching
  `optInt`/`optString` upstream semantics.
- Empty search queries are rejected client-side (`AFTAB_INVALID_ARGUMENT`)
  and never reach the wire.

## Where this is tested

`core/tests/provider_integration.rs` pins every claim above against a real
local HTTP server: exact path shapes (including the `%20` search
encoding), 500-triggered failover, dead-helper skipping, lenient parsing,
all-unreachable error taxonomy, and recovery after transient failures.
