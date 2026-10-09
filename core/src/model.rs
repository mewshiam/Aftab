//! Data models — a faithful, resilient mirror of the CCloud JSON contract.
//!
//! Field names, shapes, and endpoint semantics follow the upstream Kotlin
//! models (`Movie.kt`, `SearchResult.kt`, `Series.kt`, `SeasonsRepository.kt`).
//! Unlike upstream, malformed items are skipped individually instead of
//! poisoning the whole list, mirroring the `catch { continue }` loops in
//! `BaseRepository`-derived parsers.

use serde::{Deserialize, Serialize};

/// Sort order for catalog listings (`FilterType` upstream).
///
/// Wire values are the path segments `created` / `year` / `imdb`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FilterType {
    /// Newest first — wire value `created`.
    Default,
    /// Highest release year first — wire value `year`.
    ByYear,
    /// Highest IMDb score first — wire value `imdb`.
    ByImdb,
}

impl FilterType {
    /// The path segment the API expects.
    pub fn as_wire(self) -> &'static str {
        match self {
            FilterType::Default => "created",
            FilterType::ByYear => "year",
            FilterType::ByImdb => "imdb",
        }
    }

    /// Parse from the wire segment (inverse of [`as_wire`]).
    pub fn from_wire(s: &str) -> Option<FilterType> {
        match s {
            "created" => Some(FilterType::Default),
            "year" => Some(FilterType::ByYear),
            "imdb" => Some(FilterType::ByImdb),
            _ => None,
        }
    }
}

/// A content genre (`{ "id": 1, "title": "اکشن" }`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Genre {
    #[serde(default)]
    pub id: i64,
    #[serde(default)]
    pub title: String,
}

/// A country entry (`{ "id": 3, "title": "ایران", "image": "https://…" }`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Country {
    #[serde(default)]
    pub id: i64,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub image: String,
}

/// A playable file: one quality of one movie / episode.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Source {
    #[serde(default)]
    pub id: i64,
    /// e.g. `"1080"`, `"720"`, `"Unknown"`.
    #[serde(default)]
    pub quality: String,
    /// e.g. `"mp4"`, `"mkv"`, `"Unknown"`.
    #[serde(default)]
    pub r#type: String,
    #[serde(default)]
    pub url: String,
}

impl Source {
    /// Best-effort numeric quality for sorting (e.g. `"1080"` → 1080).
    pub fn quality_rank(&self) -> i64 {
        self.quality
            .trim()
            .trim_end_matches('p')
            .parse()
            .unwrap_or(0)
    }
}

/// Shared poster/listing fields for movies, series, and search results.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Poster {
    #[serde(default)]
    pub id: i64,
    /// `"movie"` or `"serie"`.
    #[serde(default, rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub year: i32,
    #[serde(default)]
    pub imdb: f64,
    #[serde(default)]
    pub rating: f64,
    /// Optional on the wire (`"null"` / `"N/A"` upstream).
    #[serde(default)]
    pub duration: Option<String>,
    #[serde(default)]
    pub image: String,
    #[serde(default)]
    pub cover: String,
    #[serde(default)]
    pub genres: Vec<Genre>,
    #[serde(default)]
    pub sources: Vec<Source>,
    #[serde(default)]
    pub country: Vec<Country>,
}

/// A movie listing (has playable sources).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Movie {
    #[serde(default)]
    pub id: i64,
    #[serde(default, rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub year: i32,
    #[serde(default)]
    pub imdb: f64,
    #[serde(default)]
    pub rating: f64,
    #[serde(default)]
    pub duration: Option<String>,
    #[serde(default)]
    pub image: String,
    #[serde(default)]
    pub cover: String,
    #[serde(default)]
    pub genres: Vec<Genre>,
    #[serde(default)]
    pub sources: Vec<Source>,
    #[serde(default)]
    pub country: Vec<Country>,
}

impl From<Poster> for Movie {
    fn from(p: Poster) -> Self {
        Movie {
            id: p.id,
            kind: p.kind,
            title: p.title,
            description: p.description,
            year: p.year,
            imdb: p.imdb,
            rating: p.rating,
            duration: p.duration,
            image: p.image,
            cover: p.cover,
            genres: p.genres,
            sources: p.sources,
            country: p.country,
        }
    }
}

/// A series listing (sources arrive per-episode via [`Season`]).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Series {
    #[serde(default)]
    pub id: i64,
    #[serde(default, rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub year: i32,
    #[serde(default)]
    pub imdb: f64,
    #[serde(default)]
    pub rating: f64,
    #[serde(default)]
    pub duration: Option<String>,
    #[serde(default)]
    pub image: String,
    #[serde(default)]
    pub cover: String,
    #[serde(default)]
    pub genres: Vec<Genre>,
    #[serde(default)]
    pub country: Vec<Country>,
}

impl From<Series> for Movie {
    /// The Flutter layer renders series and movies through one card widget,
    /// exactly like upstream's `Series.toMovie()`.
    fn from(s: Series) -> Self {
        Movie {
            id: s.id,
            kind: s.kind,
            title: s.title,
            description: s.description,
            year: s.year,
            imdb: s.imdb,
            rating: s.rating,
            duration: s.duration,
            image: s.image,
            cover: s.cover,
            genres: s.genres,
            sources: Vec::new(),
            country: s.country,
        }
    }
}

/// One episode inside a season.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Episode {
    #[serde(default)]
    pub id: i64,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub duration: Option<String>,
    #[serde(default)]
    pub image: String,
    #[serde(default)]
    pub sources: Vec<Source>,
}

/// One season of a series.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Season {
    #[serde(default)]
    pub id: i64,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub episodes: Vec<Episode>,
}

impl Season {
    /// Highest available numeric quality across all episodes.
    pub fn best_quality(&self) -> Option<i64> {
        self.episodes
            .iter()
            .flat_map(|e| e.sources.iter())
            .map(Source::quality_rank)
            .filter(|q| *q > 0)
            .max()
    }
}

/// Search response wrapper: `{ "posters": [ … ] }`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SearchResult {
    #[serde(default)]
    pub posters: Vec<Poster>,
}

/// Parse a JSON array of `T`, skipping items that fail to parse —
/// the same tolerance the upstream Kotlin `catch { continue }` loops have.
pub fn parse_array_lenient<T: for<'de> Deserialize<'de>>(
    json: &str,
) -> Result<Vec<T>, crate::error::AftabError> {
    let raw: Vec<serde_json::Value> = serde_json::from_str(json)?;
    let mut out = Vec::with_capacity(raw.len());
    let mut skipped = 0usize;
    for value in raw {
        match serde_json::from_value::<T>(value) {
            Ok(item) => out.push(item),
            Err(_) => skipped += 1,
        }
    }
    if out.is_empty() && skipped > 0 {
        // Everything was malformed: that is a parse failure, not an empty list.
        return Err(crate::error::AftabError::Parse(format!(
            "all {skipped} array items failed to parse"
        )));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const MOVIE_JSON: &str = r#"{
        "id": 12,
        "type": "movie",
        "title": "گوشه",
        "description": "یک فیلم",
        "year": 2023,
        "imdb": 7.4,
        "rating": 8.1,
        "duration": "1h 52m",
        "image": "https://img.example/p.jpg",
        "cover": "https://img.example/c.jpg",
        "genres": [{"id": 1, "title": "اکشن"}],
        "sources": [{"id": 9, "quality": "1080", "type": "mp4", "url": "https://cdn.example/v.mp4"}],
        "country": [{"id": 3, "title": "ایران", "image": "https://img.example/ir.png"}]
    }"#;

    #[test]
    fn parses_a_full_movie() {
        let m: Movie = serde_json::from_str(MOVIE_JSON).unwrap();
        assert_eq!(m.id, 12);
        assert_eq!(m.title, "گوشه");
        assert_eq!(m.duration.as_deref(), Some("1h 52m"));
        assert_eq!(m.sources.len(), 1);
        assert_eq!(m.sources[0].quality_rank(), 1080);
        assert_eq!(m.genres[0].title, "اکشن");
    }

    #[test]
    fn tolerates_missing_optional_fields() {
        let m: Movie = serde_json::from_str(r#"{"id": 5, "title": "بدون سال"}"#).unwrap();
        assert_eq!(m.year, 0);
        assert!(m.duration.is_none());
        assert!(m.sources.is_empty());
    }

    #[test]
    fn filter_type_wire_roundtrip() {
        assert_eq!(FilterType::Default.as_wire(), "created");
        assert_eq!(FilterType::ByYear.as_wire(), "year");
        assert_eq!(FilterType::ByImdb.as_wire(), "imdb");
        for f in [FilterType::Default, FilterType::ByYear, FilterType::ByImdb] {
            assert_eq!(FilterType::from_wire(f.as_wire()), Some(f));
        }
        assert_eq!(FilterType::from_wire("bogus"), None);
    }

    #[test]
    fn lenient_array_skips_bad_items() {
        // `"not a number"` for an i64 field fails typed parsing;
        // a bare JSON string is not an object at all.
        let json = format!("[{MOVIE_JSON}, {{\"id\": \"not a number\"}}, \"just a string\"]");
        let movies: Vec<Movie> = parse_array_lenient(&json).unwrap();
        assert_eq!(movies.len(), 1, "only the well-formed item survives");
        assert_eq!(movies[0].id, 12);
    }

    #[test]
    fn lenient_array_allows_empty_objects_like_upstream() {
        // Upstream's optInt/optString defaulting turns `{}` into a movie of
        // defaults — we preserve that tolerance.
        let movies: Vec<Movie> = parse_array_lenient("[{}]").unwrap();
        assert_eq!(movies.len(), 1);
        assert_eq!(movies[0].id, 0);
        assert_eq!(movies[0].title, "");
    }

    #[test]
    fn lenient_array_all_bad_is_an_error() {
        let err = parse_array_lenient::<Movie>(r#"[{"id": "x"}, {"id": "y"}]"#).unwrap_err();
        assert_eq!(err.code(), crate::error::codes::PARSE);
    }

    #[test]
    fn lenient_array_empty_is_ok() {
        let movies: Vec<Movie> = parse_array_lenient("[]").unwrap();
        assert!(movies.is_empty());
    }

    #[test]
    fn search_result_shape() {
        let r: SearchResult =
            serde_json::from_str(&format!(r#"{{"posters": [{MOVIE_JSON}]}}"#)).unwrap();
        assert_eq!(r.posters.len(), 1);
        assert_eq!(r.posters[0].kind, "movie");
    }

    #[test]
    fn poster_to_movie_conversion() {
        let p: Poster = serde_json::from_str(MOVIE_JSON).unwrap();
        let m: Movie = p.into();
        assert_eq!(m.title, "گوشه");
        assert_eq!(m.sources.len(), 1);
    }

    #[test]
    fn season_best_quality() {
        let s: Season = serde_json::from_str(
            r#"{"id": 1, "title": "فصل اول", "episodes": [
                {"id": 1, "title": "قسمت ۱", "sources": [
                    {"id": 1, "quality": "720", "type": "mkv", "url": "https://x/1.mkv"},
                    {"id": 2, "quality": "1080", "type": "mp4", "url": "https://x/1.mp4"}]},
                {"id": 2, "title": "قسمت ۲", "sources": [
                    {"id": 3, "quality": "480", "type": "mp4", "url": "https://x/2.mp4"}]}]}"#,
        )
        .unwrap();
        assert_eq!(s.best_quality(), Some(1080));
        assert_eq!(s.episodes.len(), 2);
    }

    #[test]
    fn quality_rank_defaults_to_zero() {
        let s: Source =
            serde_json::from_str(r#"{"id": 1, "quality": "Unknown", "type": "mp4", "url": "u"}"#)
                .unwrap();
        assert_eq!(s.quality_rank(), 0);
    }

    #[test]
    fn series_to_movie_keeps_identity() {
        let s: Series =
            serde_json::from_str(r#"{"id": 7, "type": "serie", "title": "سرزمین", "year": 2020}"#)
                .unwrap();
        let m: Movie = s.into();
        assert_eq!(m.id, 7);
        assert_eq!(m.kind, "serie");
        assert!(m.sources.is_empty(), "series carry sources per episode");
    }
}
