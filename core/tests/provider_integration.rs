//! Provider integration tests against a **real local HTTP server**.
//!
//! These verify the wire contract end-to-end: URL shapes the upstream
//! servers expect, failover when the primary is down or misbehaving,
//! lenient parsing of mixed-quality payloads, and error taxonomy when
//! everything is unreachable. The only thing "faked" is the remote server
//! itself — the provider, its HTTP client, and the failover loop run
//! exactly as they do in production.

mod common;

use aftab::error::codes;
use aftab::model::FilterType;
use aftab::provider::{Origin, Provider};

use common::{spawn_refusing_server, spawn_server, Resp};

fn movie_json(id: i64, title: &str) -> String {
    format!(
        r#"{{"id": {id}, "type": "movie", "title": "{title}", "description": "توضیح {id}",
            "year": 2020, "imdb": 7.1, "rating": 8.0, "duration": "1h 30m",
            "image": "https://img.example/{id}.jpg", "cover": "https://img.example/{id}c.jpg",
            "genres": [{{"id": 1, "title": "اکشن"}}],
            "sources": [{{"id": {id}, "quality": "1080", "type": "mp4", "url": "https://cdn.example/{id}.mp4"}}],
            "country": [{{"id": 3, "title": "ایران", "image": "https://img.example/ir.png"}}]}}"#
    )
}

fn movies_body() -> String {
    format!("[{}, {}]", movie_json(1, "گوشه"), movie_json(2, "شب‌طولانی"))
}

#[test]
fn movies_come_from_the_primary_server_with_the_upstream_path() {
    let server = spawn_server(|req| {
        assert_eq!(req.method, "GET", "catalog calls are plain GETs");
        if req.path.starts_with("/api/movie/by/filtres/") {
            Resp::json(movies_body())
        } else {
            Resp::error()
        }
    });
    let p = Provider::new(&server.base, "KEY", &[]).unwrap();

    let sourced = p.movies(0, FilterType::Default, 0).unwrap();
    assert_eq!(sourced.origin, Origin::Primary);
    assert_eq!(sourced.value.len(), 2);
    assert_eq!(sourced.value[0].title, "گوشه");
    assert_eq!(sourced.value[1].title, "شب‌طولانی");

    // The exact upstream path shape:
    assert_eq!(
        server.recorded(),
        vec!["/api/movie/by/filtres/0/created/0/KEY".to_string()]
    );
}

#[test]
fn filter_and_page_reach_the_wire() {
    let server = spawn_server(|_| Resp::json("[]"));
    let p = Provider::new(&server.base, "KEY", &[]).unwrap();

    p.movies(4, FilterType::ByImdb, 7).unwrap();
    assert_eq!(
        server.recorded(),
        vec!["/api/movie/by/filtres/4/imdb/7/KEY".to_string()]
    );

    p.series(2, FilterType::ByYear, 3).unwrap();
    assert!(server.hits_containing("/api/serie/by/filtres/2/year/3/KEY") == 1);

    p.country_posters(9, FilterType::ByImdb, 2).unwrap();
    assert!(server.hits_containing("/api/poster/by/filtres/0/9/imdb/2/KEY") == 1);
}

#[test]
fn failover_to_helper_on_server_error() {
    // The primary always 500s — like a struggling origin server.
    let primary = spawn_server(|_| Resp::error());
    let helper = spawn_server(|req| {
        if req.path.starts_with("/api/movie/by/filtres/") {
            Resp::json(movies_body())
        } else {
            Resp::error()
        }
    });

    let p = Provider::new(&primary.base, "KEY", &[&helper.base]).unwrap();
    let sourced = p.movies(0, FilterType::Default, 0).unwrap();

    assert_eq!(sourced.origin, Origin::Helper(0));
    assert_eq!(sourced.value.len(), 2);
    // The helper saw the *same path* the primary would have:
    assert_eq!(
        helper.hits_containing("/api/movie/by/filtres/0/created/0/KEY"),
        1
    );
}

#[test]
fn failover_skips_a_dead_helper_and_uses_the_next() {
    let primary = spawn_server(|_| Resp::error());

    // A "server down" that deterministically refuses on every platform.
    let dead = spawn_refusing_server();

    let helper2 = spawn_server(|_| Resp::json(movies_body()));

    let p = Provider::new(&primary.base, "KEY", &[&dead.base, &helper2.base]).unwrap();
    let sourced = p.movies(0, FilterType::Default, 0).unwrap();

    assert_eq!(sourced.origin, Origin::Helper(1), "dead helper is skipped");
    assert_eq!(sourced.value.len(), 2);
}

#[test]
fn all_servers_unreachable_is_a_network_error_with_context() {
    // Two refusing servers — deterministic on every platform.
    let d1 = spawn_refusing_server();
    let d2 = spawn_refusing_server();

    let p = Provider::new(&d1.base, "KEY", &[&d2.base]).unwrap();
    let err = p.genres().err().unwrap();

    assert_eq!(err.code(), codes::NETWORK);
    let msg = err.message();
    assert!(msg.contains("all providers failed"), "message: {msg}");
    assert!(
        msg.contains("helper#0"),
        "helper attempts are recorded: {msg}"
    );
}

#[test]
fn malformed_items_are_skipped_not_fatal() {
    let body = format!(
        "[{}, {{\"id\": \"broken\"}}, {}]",
        movie_json(1, "خوب"),
        movie_json(2, "نیز خوب")
    );
    let server = spawn_server(move |_| Resp::json(body.clone()));
    let p = Provider::new(&server.base, "KEY", &[]).unwrap();

    let sourced = p.movies(0, FilterType::Default, 0).unwrap();
    assert_eq!(
        sourced.value.len(),
        2,
        "the malformed middle item is skipped"
    );
    assert_eq!(sourced.value[0].title, "خوب");
}

#[test]
fn search_hits_the_upstream_path_with_percent20_encoding() {
    let server = spawn_server(|req| {
        if req.path.starts_with("/api/search/") {
            Resp::json(format!(
                "{{\"posters\": [{}]}}",
                movie_json(11, "سلطان محمود")
            ))
        } else {
            Resp::error()
        }
    });
    let p = Provider::new(&server.base, "KEY", &[]).unwrap();

    let sourced = p.search("سلطان محمود").unwrap();
    assert_eq!(sourced.value.posters.len(), 1);
    assert_eq!(sourced.value.posters[0].title, "سلطان محمود");

    // Persian UTF-8 percent-encoded, space as %20 (never '+'), key at the end.
    let expected =
        "/api/search/%D8%B3%D9%84%D8%B7%D8%A7%D9%86%20%D9%85%D8%AD%D9%85%D9%88%D8%AF/KEY/";
    assert_eq!(server.recorded(), vec![expected.to_string()]);
}

#[test]
fn genres_and_countries_paths() {
    let server = spawn_server(|req| {
        if req.path.starts_with("/api/genre/all/") {
            Resp::json(r#"[{"id": 1, "title": "اکشن"}, {"id": 2, "title": "درام"}]"#)
        } else if req.path.starts_with("/api/country/all/") {
            Resp::json(r#"[{"id": 3, "title": "ایران", "image": "https://img.example/ir.png"}]"#)
        } else {
            Resp::error()
        }
    });
    let p = Provider::new(&server.base, "KEY", &[]).unwrap();

    let genres = p.genres().unwrap();
    assert_eq!(genres.value.len(), 2);
    assert_eq!(genres.value[1].title, "درام");

    let countries = p.countries().unwrap();
    assert_eq!(countries.value.len(), 1);
    assert_eq!(countries.value[0].title, "ایران");

    let recs = server.recorded();
    assert!(recs.contains(&"/api/genre/all/KEY".to_string()));
    assert!(recs.contains(&"/api/country/all/KEY/".to_string()));
}

#[test]
fn seasons_nest_episodes_and_sources() {
    let server = spawn_server(|req| {
        if req.path.starts_with("/api/season/by/serie/") {
            Resp::json(
                r#"[
                    {"id": 1, "title": "فصل اول", "episodes": [
                        {"id": 10, "title": "قسمت ۱", "description": "آغاز", "duration": "45m",
                         "image": "https://img.example/e10.jpg",
                         "sources": [
                            {"id": 100, "quality": "1080", "type": "mp4", "url": "https://cdn.example/e10-1080.mp4"},
                            {"id": 101, "quality": "720", "type": "mkv", "url": "https://cdn.example/e10-720.mkv"}]},
                        {"id": 11, "title": "قسمت ۲", "description": "", "duration": null,
                         "image": "", "sources": []}
                    ]}
                ]"#,
            )
        } else {
            Resp::error()
        }
    });
    let p = Provider::new(&server.base, "KEY", &[]).unwrap();

    let sourced = p.seasons(42).unwrap();
    assert_eq!(sourced.value.len(), 1);
    let season = &sourced.value[0];
    assert_eq!(season.title, "فصل اول");
    assert_eq!(season.episodes.len(), 2);
    assert_eq!(season.episodes[0].sources.len(), 2);
    assert_eq!(season.episodes[0].sources[0].quality, "1080");
    assert_eq!(season.episodes[1].sources.len(), 0);
    assert_eq!(season.best_quality(), Some(1080));

    assert_eq!(
        server.recorded(),
        vec!["/api/season/by/serie/42/KEY/".to_string()]
    );
}

#[test]
fn empty_search_query_never_reaches_the_wire() {
    let server = spawn_server(|_| Resp::json("[]"));
    let p = Provider::new(&server.base, "KEY", &[]).unwrap();

    let err = p.search("   ").err().unwrap();
    assert_eq!(err.code(), codes::INVALID_ARGUMENT);
    assert!(server.recorded().is_empty(), "no request was made");
}

#[test]
fn a_failing_helper_does_not_poison_a_later_call() {
    // Primary flaky (500 twice, then fine), helper healthy: three sequential
    // calls must each resolve correctly regardless of earlier failures.
    let counter = std::sync::atomic::AtomicUsize::new(0);
    let primary = spawn_server(move |_| {
        use std::sync::atomic::Ordering;
        let n = counter.fetch_add(1, Ordering::SeqCst);
        if n < 2 {
            Resp::error()
        } else {
            Resp::json(movies_body())
        }
    });
    let helper = spawn_server(|_| Resp::json(movies_body()));

    let p = Provider::new(&primary.base, "KEY", &[&helper.base]).unwrap();
    let first = p.movies(0, FilterType::Default, 0).unwrap();
    assert_eq!(first.origin, Origin::Helper(0));
    let second = p.movies(0, FilterType::Default, 1).unwrap();
    assert_eq!(second.origin, Origin::Helper(0));
    let third = p.movies(0, FilterType::Default, 2).unwrap();
    assert_eq!(third.origin, Origin::Primary, "primary recovered");
}
