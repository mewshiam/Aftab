//! The provider: a CCloud-compatible catalog client with helper-server
//! failover.
//!
//! This module is a faithful Rust re-implementation of the upstream Kotlin
//! repositories (`BaseRepository.executeRequest` + `MovieRepository`,
//! `SeriesRepository`, `SearchRepository`, `GenreRepository`,
//! `CountryRepository`, `CountryPostersRepository`, `SeasonsRepository`).
//! The wire contract is unchanged — see `docs/PROVIDER-API.md`.
//!
//! Failover semantics, inherited from upstream and made observable:
//!
//! 1. Try the primary base URL.
//! 2. On a transport error *or* any non-2xx status, retry the identical path
//!    and query against each helper server in order (host replaced, scheme
//!    upgraded to HTTPS when the helper is HTTPS).
//! 3. If every server fails, surface the *primary* error (upstream throws
//!    `primaryException`; we do the same, with the helper attempts recorded
//!    in the error chain).
//!
//! Malformed array items are skipped, exactly like upstream's
//! `catch { continue }` loops — one bad movie must not blank the catalog.

use std::fmt;

use url::Url;

use crate::error::{AftabError, AftabResult};
use crate::http::HttpClient;
use crate::model::{
    parse_array_lenient, Country, Episode, FilterType, Genre, Movie, Poster, SearchResult, Season,
    Series,
};
use crate::urlsafe::encode_path_segment;

/// Default primary API base (as hardcoded upstream).
pub const DEFAULT_BASE_URL: &str = "https://server-hi-speed-iran.info";
/// Default helper servers for failover (as hardcoded upstream).
pub const DEFAULT_HELPER_SERVERS: &[&str] =
    &["https://hostinnegar.com", "https://windowsdiba.info"];
/// Default API key (as hardcoded upstream; overridable per instance).
pub const DEFAULT_API_KEY: &str = "4F5A9C3D9A86FA54EACEDDD635185";

/// Where a response came from — makes failover observable in tests and logs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Origin {
    Primary,
    Helper(usize),
}

impl fmt::Display for Origin {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Origin::Primary => write!(f, "primary"),
            Origin::Helper(i) => write!(f, "helper#{i}"),
        }
    }
}

/// A response together with the server it came from.
#[derive(Debug, Clone)]
pub struct Sourced<T> {
    pub value: T,
    pub origin: Origin,
    pub server: String,
}

/// The catalog client.
pub struct Provider {
    base: Url,
    api_key: String,
    helpers: Vec<Url>,
    http: HttpClient,
}

impl Provider {
    /// Build a provider with the upstream defaults (primary + helpers + key).
    pub fn with_defaults() -> AftabResult<Self> {
        Provider::new(DEFAULT_BASE_URL, DEFAULT_API_KEY, DEFAULT_HELPER_SERVERS)
    }

    /// Build a provider with explicit configuration. Helper servers may be
    /// empty (no failover).
    pub fn new(base_url: &str, api_key: &str, helper_servers: &[&str]) -> AftabResult<Self> {
        if api_key.trim().is_empty() {
            return Err(AftabError::InvalidArgument(
                "API key must not be empty".into(),
            ));
        }
        let base = Url::parse(base_url)
            .map_err(|e| AftabError::BadUrl(format!("base URL {base_url:?}: {e}")))?;
        match base.scheme() {
            "http" | "https" => {}
            other => {
                return Err(AftabError::UnsupportedScheme(format!(
                    "provider base scheme {other:?}"
                )))
            }
        }
        let mut helpers = Vec::with_capacity(helper_servers.len());
        for h in helper_servers {
            helpers
                .push(Url::parse(h).map_err(|e| AftabError::BadUrl(format!("helper {h:?}: {e}")))?);
        }
        Ok(Provider {
            base,
            api_key: api_key.to_string(),
            helpers,
            http: HttpClient::default(),
        })
    }

    /// Swap the HTTP client (tests use short timeouts).
    pub fn with_http(mut self, http: HttpClient) -> Self {
        self.http = http;
        self
    }

    /// The primary base URL.
    pub fn base(&self) -> &Url {
        &self.base
    }

    /// Helper server URLs, in failover order.
    pub fn helpers(&self) -> &[Url] {
        &self.helpers
    }

    // ── Catalog endpoints ────────────────────────────────────────────────

    /// Movies filtered by genre and sort, one page at a time.
    pub fn movies(
        &self,
        genre: i64,
        filter: FilterType,
        page: u32,
    ) -> AftabResult<Sourced<Vec<Movie>>> {
        let path = format!(
            "/api/movie/by/filtres/{}/{}/{}/{}",
            genre,
            filter.as_wire(),
            page,
            self.api_key
        );
        let (origin, server, body) = self.fetch_json(&path)?;
        Ok(Sourced {
            value: parse_array_lenient(&body)?,
            origin,
            server,
        })
    }

    /// Series filtered by genre and sort, one page at a time.
    pub fn series(
        &self,
        genre: i64,
        filter: FilterType,
        page: u32,
    ) -> AftabResult<Sourced<Vec<Series>>> {
        let path = format!(
            "/api/serie/by/filtres/{}/{}/{}/{}",
            genre,
            filter.as_wire(),
            page,
            self.api_key
        );
        let (origin, server, body) = self.fetch_json(&path)?;
        Ok(Sourced {
            value: parse_array_lenient(&body)?,
            origin,
            server,
        })
    }

    /// Posters for one country (upstream `CountryPostersRepository`).
    pub fn country_posters(
        &self,
        country: i64,
        filter: FilterType,
        page: u32,
    ) -> AftabResult<Sourced<Vec<Poster>>> {
        let path = format!(
            "/api/poster/by/filtres/0/{}/{}/{}/{}",
            country,
            filter.as_wire(),
            page,
            self.api_key
        );
        let (origin, server, body) = self.fetch_json(&path)?;
        Ok(Sourced {
            value: parse_array_lenient(&body)?,
            origin,
            server,
        })
    }

    /// Full-text search (upstream `SearchRepository`).
    pub fn search(&self, query: &str) -> AftabResult<Sourced<SearchResult>> {
        let trimmed = query.trim();
        if trimmed.is_empty() {
            return Err(AftabError::InvalidArgument("search query is empty".into()));
        }
        let path = format!(
            "/api/search/{}/{}/",
            encode_path_segment(trimmed),
            self.api_key
        );
        let (origin, server, body) = self.fetch_json(&path)?;
        let value: SearchResult = serde_json::from_str(&body)?;
        Ok(Sourced {
            value,
            origin,
            server,
        })
    }

    /// All genres (upstream `GenreRepository`).
    pub fn genres(&self) -> AftabResult<Sourced<Vec<Genre>>> {
        let path = format!("/api/genre/all/{}", self.api_key);
        let (origin, server, body) = self.fetch_json(&path)?;
        Ok(Sourced {
            value: parse_array_lenient(&body)?,
            origin,
            server,
        })
    }

    /// All countries (upstream `CountryRepository`).
    pub fn countries(&self) -> AftabResult<Sourced<Vec<Country>>> {
        let path = format!("/api/country/all/{}/", self.api_key);
        let (origin, server, body) = self.fetch_json(&path)?;
        Ok(Sourced {
            value: parse_array_lenient(&body)?,
            origin,
            server,
        })
    }

    /// Seasons and episodes of one series (upstream `SeasonsRepository`).
    pub fn seasons(&self, series_id: i64) -> AftabResult<Sourced<Vec<Season>>> {
        let path = format!("/api/season/by/serie/{}/{}/", series_id, self.api_key);
        let (origin, server, body) = self.fetch_json(&path)?;
        Ok(Sourced {
            value: parse_array_lenient(&body)?,
            origin,
            server,
        })
    }

    // ── Failover core ───────────────────────────────────────────────────

    /// Fetch `path` from the primary, falling back to each helper server.
    /// Returns `(origin, server_host, body)`.
    fn fetch_json(&self, path: &str) -> AftabResult<(Origin, String, String)> {
        let primary_url = self.join(path);
        let primary_err = match self.http.get_text(primary_url.as_str()) {
            Ok(body) => return Ok((Origin::Primary, host_of(&primary_url), body)),
            Err(e) => e,
        };

        let mut attempts = Vec::new();
        for (i, helper) in self.helpers.iter().enumerate() {
            let candidate = self.rehost(path, helper);
            match self.http.get_text(candidate.as_str()) {
                Ok(body) => {
                    return Ok((Origin::Helper(i), host_of(&candidate), body));
                }
                Err(e) => attempts.push(format!("helper#{}: {}", i, e.code())),
            }
        }

        Err(AftabError::Network(format!(
            "all providers failed — primary: [{}] {}; helpers tried: {}",
            primary_err.code(),
            primary_err.message(),
            if attempts.is_empty() {
                "none".to_string()
            } else {
                attempts.join(", ")
            }
        )))
    }

    /// `base + path`, keeping the base's query string empty by construction.
    fn join(&self, path: &str) -> Url {
        self.base.join(path).expect("base is a valid absolute URL")
    }

    /// The same path and query on a different host (upstream's
    /// `primaryUrl.replace(Regex("^https?://[^/]+"), helperServer)`).
    fn rehost(&self, path: &str, host: &Url) -> Url {
        let mut url = host.join(path).expect("helper is a valid absolute URL");
        // Path built by us never carries a query; keep it that way.
        url.set_query(None);
        url
    }
}

fn host_of(url: &Url) -> String {
    match url.port() {
        Some(p) => format!("{}:{p}", url.host_str().unwrap_or("?")),
        None => url.host_str().unwrap_or("?").to_string(),
    }
}

/// Filter an episode list down to playable sources whose URLs pass the
/// strict untrusted-URL policy — the app calls this before handing URLs to
/// libmpv.
pub fn safe_episode_sources(episodes: &[Episode]) -> Vec<(usize, usize, String)> {
    let mut out = Vec::new();
    for (ei, ep) in episodes.iter().enumerate() {
        for (si, s) in ep.sources.iter().enumerate() {
            if crate::urlsafe::strict_ok(&s.url) {
                out.push((ei, si, s.url.clone()));
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::codes;

    #[test]
    fn default_provider_targets_upstream_primary_and_helpers() {
        let p = Provider::with_defaults().unwrap();
        assert_eq!(p.base().as_str(), "https://server-hi-speed-iran.info/");
        assert_eq!(p.helpers().len(), 2);
        assert_eq!(p.helpers()[0].as_str(), "https://hostinnegar.com/");
        assert_eq!(p.helpers()[1].as_str(), "https://windowsdiba.info/");
    }

    #[test]
    fn empty_api_key_is_rejected() {
        let err = Provider::new("https://x.example", "  ", &[]).err().unwrap();
        assert_eq!(err.code(), codes::INVALID_ARGUMENT);
    }

    #[test]
    fn non_http_base_is_rejected() {
        let err = Provider::new("ftp://x.example", "key", &[]).err().unwrap();
        assert_eq!(err.code(), codes::UNSUPPORTED_SCHEME);
    }

    #[test]
    fn bad_helper_url_is_rejected() {
        let err = Provider::new("https://x.example", "key", &["not a url"])
            .err()
            .unwrap();
        assert_eq!(err.code(), codes::BAD_URL);
    }

    #[test]
    fn movie_path_is_upstream_shape() {
        let p = Provider::with_defaults().unwrap();
        // Peek at URL construction via a private-adjacent helper:
        let url = p.join(&format!(
            "/api/movie/by/filtres/{}/{}/{}/{}",
            3,
            FilterType::ByImdb.as_wire(),
            2,
            p.api_key
        ));
        assert_eq!(
            url.path(),
            format!("/api/movie/by/filtres/3/imdb/2/{}", DEFAULT_API_KEY)
        );
    }

    #[test]
    fn search_path_is_upstream_shape_with_encoding() {
        let p = Provider::with_defaults().unwrap();
        let url = p.join(&format!(
            "/api/search/{}/{}/",
            encode_path_segment("سلطان محمود"),
            p.api_key
        ));
        assert!(url.path().starts_with("/api/search/%D8%B3"));
        assert!(url.path().contains("%20"), "spaces must be %20, not +");
        assert!(url.path().ends_with(&format!("/{}/", DEFAULT_API_KEY)));
    }

    #[test]
    fn rehost_swaps_host_keeps_path() {
        let p = Provider::with_defaults().unwrap();
        let path = "/api/movie/by/filtres/0/created/0/KEY";
        let helper_url = p.rehost(path, &p.helpers()[0]);
        assert_eq!(helper_url.host_str(), Some("hostinnegar.com"));
        assert_eq!(helper_url.path(), path);
    }

    #[test]
    fn rehost_to_http_helper_downgrades_scheme() {
        let p = Provider::new("https://x.example", "k", &["http://mirror.local"]).unwrap();
        let url = p.rehost("/api/genre/all/k", &p.helpers()[0]);
        assert_eq!(url.scheme(), "http");
        assert_eq!(url.host_str(), Some("mirror.local"));
    }

    #[test]
    fn empty_search_query_is_rejected() {
        let p = Provider::with_defaults().unwrap();
        let err = p.search("   ").unwrap_err();
        assert_eq!(err.code(), codes::INVALID_ARGUMENT);
    }

    #[test]
    fn seasons_path_is_upstream_shape() {
        let p = Provider::with_defaults().unwrap();
        let url = p.join(&format!("/api/season/by/serie/{}/", 7));
        assert_eq!(url.path(), "/api/season/by/serie/7/");
    }

    #[test]
    fn country_posters_path_is_upstream_shape() {
        let p = Provider::with_defaults().unwrap();
        let url = p.join(&format!(
            "/api/poster/by/filtres/0/{}/{}/{}/{}",
            3,
            FilterType::ByYear.as_wire(),
            1,
            p.api_key
        ));
        assert!(url.path().starts_with("/api/poster/by/filtres/0/3/year/1/"));
    }

    // Full network behavior — failover, lenient parsing, bad statuses — is
    // exercised against a real local HTTP server in tests/provider_integration.rs.
}
