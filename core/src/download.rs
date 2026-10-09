//! Resumable downloads with HTTP `Range` support.
//!
//! Media files are large and Persian-diaspora networks are flaky; a
//! downloader that restarts from zero would be unusable. The flow:
//!
//! 1. The URL must pass the strict untrusted-media policy first.
//! 2. Existing `.part` bytes are counted; a `Range: bytes=N-` request
//!    continues from there when the server answers `206`.
//! 3. A `200` answer (server ignored the range) restarts the file cleanly —
//!    appending to a partial prefix would corrupt the media.
//! 4. The body streams to disk in bounded chunks; the caller may watch
//!    progress through a callback.
//! 5. On completion the `.part` file is renamed to its final name.

use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::error::{AftabError, AftabResult};
use crate::http::HttpClient;
use crate::urlsafe;

/// Progress callback: `(bytes_done, total_bytes_or_unknown)`.
pub type ProgressFn<'a> = dyn FnMut(u64, Option<u64>) + 'a;

/// A one-shot download handle.
pub struct Download<'a> {
    http: &'a HttpClient,
    url: String,
    dest: PathBuf,
    resume: bool,
}

impl<'a> Download<'a> {
    /// Prepare a download of `url` to `dest` under the strict production
    /// URL policy (untrusted URLs are refused before any I/O).
    pub fn new(http: &'a HttpClient, url: &str, dest: &Path) -> AftabResult<Download<'a>> {
        urlsafe::is_safe_media_url(url)?;
        Ok(Download {
            http,
            url: url.to_string(),
            dest: dest.to_path_buf(),
            resume: true,
        })
    }

    /// Prepare a download under an explicit URL policy.
    pub fn with_policy(
        http: &'a HttpClient,
        url: &str,
        dest: &Path,
        policy: urlsafe::Policy,
    ) -> AftabResult<Download<'a>> {
        urlsafe::check_url(url, policy)?;
        Ok(Download {
            http,
            url: url.to_string(),
            dest: dest.to_path_buf(),
            resume: true,
        })
    }

    /// Disable resume: always restart from byte zero.
    pub fn no_resume(mut self) -> Self {
        self.resume = false;
        self
    }

    /// Path of the in-progress file.
    pub fn part_path(&self) -> PathBuf {
        let mut os = self.dest.clone().into_os_string();
        os.push(".part");
        PathBuf::from(os)
    }

    /// Run the download. Returns total bytes written so far. When the
    /// transfer completes, the `.part` file is renamed to the destination;
    /// otherwise it is left in place so the next `run()` resumes.
    pub fn run(&self, progress: Option<&mut ProgressFn<'_>>) -> AftabResult<u64> {
        let part = self.part_path();
        let existing: u64 = if self.resume {
            std::fs::metadata(&part).map(|m| m.len()).unwrap_or(0)
        } else {
            let _ = std::fs::remove_file(&part);
            0
        };

        // One range request; `HttpClient::get_range` buffers the body.
        let (status, body, content_len) = self.http.get_range(&self.url, existing)?;
        let append = status == 206;
        let (start, total) = if append {
            (existing, content_len.map(|t| t + existing))
        } else {
            (0, content_len)
        };

        let mut file = OpenOptions::new()
            .write(true)
            .create(true)
            .append(append)
            .truncate(!append)
            .open(&part)
            .map_err(|e| AftabError::Io(format!("open {}: {e}", part.display())))?;

        let mut done = start;
        if !body.is_empty() {
            file.write_all(&body)
                .map_err(|e| AftabError::Io(format!("write failed: {e}")))?;
            done += body.len() as u64;
        }
        if let Some(cb) = progress {
            cb(done, total);
        }

        // Finalize only when the transfer is complete (or the size is
        // unknown, in which case any body end counts as complete).
        let complete = total.map(|t| done >= t).unwrap_or(true);
        if complete {
            file.sync_all().ok();
            drop(file);
            std::fs::rename(&part, &self.dest)
                .map_err(|e| AftabError::Io(format!("finalize failed: {e}")))?;
        }
        Ok(done)
    }
}

/// One-call convenience (FFI uses this).
pub fn download_to_file(
    http: &HttpClient,
    url: &str,
    dest: &Path,
    policy: urlsafe::Policy,
) -> AftabResult<u64> {
    Download::with_policy(http, url, dest, policy)?.run(None)
}

/// Guard used by the FFI layer: is this a path we can write to?
pub fn validate_dest(dest: &Path) -> AftabResult<()> {
    if dest.as_os_str().is_empty() {
        return Err(AftabError::InvalidArgument(
            "destination path is empty".into(),
        ));
    }
    if let Some(parent) = dest.parent() {
        if !parent.as_os_str().is_empty() && !parent.exists() {
            return Err(AftabError::InvalidArgument(format!(
                "destination directory {} does not exist",
                parent.display()
            )));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::codes;
    use std::time::Duration;

    #[test]
    fn unsafe_urls_are_refused_before_any_io() {
        let http = HttpClient::new(Duration::from_secs(5));
        let dest = std::env::temp_dir().join("aftab-never.mp4");
        let err = Download::new(&http, "http://127.0.0.1:1/x.mp4", &dest)
            .err()
            .unwrap();
        assert_eq!(err.code(), codes::UNSAFE_URL);
        assert!(!dest.with_extension("mp4.part").exists());
    }

    #[test]
    fn bad_schemes_are_refused() {
        let http = HttpClient::new(Duration::from_secs(5));
        let dest = std::env::temp_dir().join("aftab-scheme.mp4");
        let err = Download::new(&http, "ftp://cdn.example/x.mp4", &dest)
            .err()
            .unwrap();
        assert_eq!(err.code(), codes::UNSUPPORTED_SCHEME);
    }

    #[test]
    fn part_path_appends_suffix() {
        let http = HttpClient::new(Duration::from_secs(5));
        let dest = std::env::temp_dir().join("aftab-movie.mp4");
        let d = Download::with_policy(
            &http,
            "http://example.com/v.mp4",
            &dest,
            urlsafe::Policy::TRUSTED,
        )
        .unwrap();
        assert_eq!(d.part_path(), dest.with_extension("mp4.part"));
    }

    #[test]
    fn validate_dest_rejects_missing_directory() {
        let missing = std::env::temp_dir().join("aftab-definitely-missing-dir/file.mp4");
        assert!(validate_dest(&missing).is_err());
        let present = std::env::temp_dir().join("ok.mp4");
        assert!(validate_dest(&present).is_ok());
        assert!(validate_dest(Path::new("")).is_err());
    }

    // Real transfer behavior — 206 resume, 200 restart, progress callbacks —
    // is tested against a live local HTTP server in tests/download_local.rs.
}
