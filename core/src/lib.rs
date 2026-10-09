//! # aftab-core — the heart of آفتاب مدیا (Aftab Media)
//!
//! One Rust core, three platforms. Everything that is *not pixels* lives
//! here and is exposed to the Flutter application through a stable C-ABI
//! (`ffi` module + `include/aftab.h`):
//!
//! * [`model`] — the CCloud-compatible data contract (movies, series,
//!   seasons, episodes, sources, genres, countries, search results).
//! * [`persian`] — Persian text normalization: Arabic→Farsi codepoint
//!   folding, digit folding, ZWNJ policy, compact matching keys.
//! * [`search`] — Persian-aware ranking: exact / word-prefix / prefix /
//!   substring / subsequence, tuned for twelve-key remotes.
//! * [`http`] — timeout-bounded HTTP client (rustls, no OpenSSL).
//! * [`provider`] — the catalog API client with upstream-identical
//!   failover to helper servers.
//! * [`store`] — atomic JSON persistence for favorites, watch progress,
//!   and settings.
//! * [`download`] — resumable downloads via HTTP `Range`.
//! * [`urlsafe`] — the SSRF guard for untrusted media URLs.
//! * [`error`] — the stable error taxonomy that crosses the FFI boundary.
//!
//! ## Design principles
//!
//! 1. **Persian-first.** Normalization and search are core services, not a
//!    UI afterthought — `آفتاب` and `افتاب` are the same word here.
//! 2. **Real evidence.** The provider and downloader are tested against
//!    live local HTTP servers, not mocks of our own code.
//! 3. **Fail loud, fail coded.** Every failure maps to a stable numeric
//!    code before it crosses into Dart.
//! 4. **No panics across FFI.** Every entry point is panic-guarded.

pub mod download;
pub mod error;
pub mod ffi;
pub mod http;
pub mod model;
pub mod persian;
pub mod provider;
pub mod search;
pub mod store;
pub mod urlsafe;

/// Crate version (`MAJOR.MINOR.PATCH`).
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Crate version, for callers that prefer a function.
pub fn version() -> &'static str {
    VERSION
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_semver_shaped() {
        // Three dot-separated numeric components — pinned so a bad release
        // cut fails here rather than in the FFI header generator.
        let parts: Vec<&str> = VERSION.split('.').collect();
        assert_eq!(parts.len(), 3, "version = {VERSION}");
        assert!(parts.iter().all(|p| p.chars().all(|c| c.is_ascii_digit())));
    }

    #[test]
    fn version_matches_ffi() {
        // The FFI string and the Rust constant must never drift apart.
        let ffi_version = crate::ffi::aftab_version();
        let cstr = unsafe { std::ffi::CStr::from_ptr(ffi_version) };
        assert_eq!(cstr.to_str().unwrap(), VERSION);
    }
}
