//! Downloader integration tests against a **real local HTTP server**.
//!
//! `Range` semantics are the whole story here: a CDN that honors ranges
//! (206), a CDN that ignores them (200), and the `.part`-file dance that
//! makes flaky-diaspora-network downloads survivable.

mod common;

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use aftab::download::Download;
use aftab::http::HttpClient;
use aftab::urlsafe::Policy;

use common::{range_aware, range_blind, spawn_server};

/// Deterministic pseudo-media payload (4096 bytes).
const fn make_payload() -> [u8; 4096] {
    let mut out = [0u8; 4096];
    let mut i = 0usize;
    while i < 4096 {
        out[i] = (i % 251) as u8;
        i += 1;
    }
    out
}

static PAYLOAD: &[u8] = &make_payload();

fn temp_dest(tag: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "aftab-dl-{}-{}-{}.mp4",
        tag,
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ))
}

fn client() -> HttpClient {
    HttpClient::new(std::time::Duration::from_secs(10))
}

#[test]
fn full_download_over_200() {
    let server = spawn_server(range_aware(PAYLOAD));
    let dest = temp_dest("full");
    let url = server.url("/media/movie.mp4");

    let bytes = Download::with_policy(&client(), &url, &dest, Policy::TRUSTED)
        .unwrap()
        .run(None)
        .unwrap();

    assert_eq!(bytes, PAYLOAD.len() as u64);
    assert_eq!(fs::read(&dest).unwrap(), PAYLOAD.to_vec(), "exact bytes");
    assert!(dest.exists());
    assert!(
        !dest.with_extension("mp4.part").exists(),
        "part file renamed away"
    );
    fs::remove_file(&dest).ok();
}

#[test]
fn resume_from_a_partial_part_file_with_206() {
    let server = spawn_server(range_aware(PAYLOAD));
    let dest = temp_dest("resume");
    let url = server.url("/media/movie.mp4");

    // Simulate a previous run that died halfway: 1000 bytes on disk.
    let part = dest.with_extension("mp4.part");
    fs::write(&part, &PAYLOAD[..1000]).unwrap();

    let bytes = Download::with_policy(&client(), &url, &dest, Policy::TRUSTED)
        .unwrap()
        .run(None)
        .unwrap();

    assert_eq!(bytes, PAYLOAD.len() as u64, "total after resume");
    assert_eq!(
        fs::read(&dest).unwrap(),
        PAYLOAD.to_vec(),
        "resumed file intact"
    );
    assert!(
        server.hits_containing("[range 1000]") == 1,
        "server saw the Range header"
    );
    assert!(!part.exists(), "part file renamed away");
    fs::remove_file(&dest).ok();
}

#[test]
fn a_range_blind_server_triggers_a_clean_restart() {
    let server = spawn_server(range_blind(PAYLOAD));
    let dest = temp_dest("blind");
    let url = server.url("/media/movie.mp4");

    // Stale partial data from a *different* transfer must not survive.
    let part = dest.with_extension("mp4.part");
    fs::write(&part, b"stale garbage prefix that must be discarded").unwrap();

    let bytes = Download::with_policy(&client(), &url, &dest, Policy::TRUSTED)
        .unwrap()
        .run(None)
        .unwrap();

    assert_eq!(bytes, PAYLOAD.len() as u64);
    let on_disk = fs::read(&dest).unwrap();
    assert_eq!(
        on_disk,
        PAYLOAD.to_vec(),
        "no garbage prefix, no double-write"
    );
    fs::remove_file(&dest).ok();
}

#[test]
fn progress_callback_sees_totals() {
    let server = spawn_server(range_aware(PAYLOAD));
    let dest = temp_dest("progress");
    let url = server.url("/media/movie.mp4");

    let mut seen: Vec<(u64, Option<u64>)> = Vec::new();
    {
        let mut cb = |done: u64, total: Option<u64>| seen.push((done, total));
        Download::with_policy(&client(), &url, &dest, Policy::TRUSTED)
            .unwrap()
            .run(Some(&mut cb))
            .unwrap();
    }

    assert!(!seen.is_empty(), "callback fired");
    let (last_done, last_total) = *seen.last().unwrap();
    assert_eq!(last_done, PAYLOAD.len() as u64);
    assert_eq!(last_total, Some(PAYLOAD.len() as u64));
    fs::remove_file(&dest).ok();
}

#[test]
fn resume_progress_report_is_relative_to_the_whole_file() {
    let server = spawn_server(range_aware(PAYLOAD));
    let dest = temp_dest("resume-progress");
    let url = server.url("/media/movie.mp4");

    let part = dest.with_extension("mp4.part");
    fs::write(&part, &PAYLOAD[..1000]).unwrap();

    let mut seen: Vec<(u64, Option<u64>)> = Vec::new();
    {
        let mut cb = |done: u64, total: Option<u64>| seen.push((done, total));
        Download::with_policy(&client(), &url, &dest, Policy::TRUSTED)
            .unwrap()
            .run(Some(&mut cb))
            .unwrap();
    }

    let (done, total) = *seen.last().unwrap();
    assert_eq!(done, PAYLOAD.len() as u64, "done counts the whole file");
    assert_eq!(
        total,
        Some(PAYLOAD.len() as u64),
        "total includes the prefix"
    );
    fs::remove_file(&dest).ok();
}

#[test]
fn no_resume_always_restarts_from_zero() {
    let server = spawn_server(range_aware(PAYLOAD));
    let dest = temp_dest("noresume");
    let url = server.url("/media/movie.mp4");

    let part = dest.with_extension("mp4.part");
    fs::write(&part, &PAYLOAD[..1000]).unwrap();

    let bytes = Download::with_policy(&client(), &url, &dest, Policy::TRUSTED)
        .unwrap()
        .no_resume()
        .run(None)
        .unwrap();

    assert_eq!(bytes, PAYLOAD.len() as u64);
    // No Range header was sent — the request was a plain GET.
    let recs = server.recorded();
    assert_eq!(recs.len(), 1);
    assert!(!recs[0].contains("[range"), "plain request: {}", recs[0]);
    assert_eq!(fs::read(&dest).unwrap(), PAYLOAD.to_vec());
    fs::remove_file(&dest).ok();
}

#[test]
fn strict_policy_still_blocks_local_servers_at_construction() {
    let server = spawn_server(range_aware(PAYLOAD));
    let dest = temp_dest("strict");
    let url = server.url("/media/movie.mp4");

    let err = Download::new(&client(), &url, &dest).err().unwrap();
    assert_eq!(err.code(), aftab::error::codes::UNSAFE_URL);
    // And nothing was ever requested:
    assert!(server.recorded().is_empty());
    assert!(!dest.exists());
}

#[test]
fn server_error_status_is_surfaced_as_bad_response() {
    let server = spawn_server(|_| common::Resp::error());
    let dest = temp_dest("err500");
    let url = server.url("/media/movie.mp4");

    let err = Download::with_policy(&client(), &url, &dest, Policy::TRUSTED)
        .unwrap()
        .run(None)
        .err()
        .unwrap();
    assert_eq!(err.code(), aftab::error::codes::BAD_RESPONSE);
    assert!(err.message().contains("500"), "status is in the message");
    fs::remove_file(&dest).ok();
}
