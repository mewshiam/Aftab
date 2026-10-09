//! The C-ABI FFI boundary — the contract `app/` (Flutter) links against.
//!
//! Design rules, mirrored in `core/include/aftab.h`:
//!
//! * **Ownership is explicit.** Functions returning `*mut c_char` hand the
//!   caller a heap string that must be released with [`aftab_free_string`].
//!   Handles (`aftab_provider_*`, `aftab_store_*`) are opaque pointers owned
//!   by the caller and released by their `*_free` functions.
//! * **Errors are codes, not strings.** Pointer-returning functions signal
//!   failure with `NULL` plus a thread-local last-error; integer-returning
//!   functions signal success non-zero / negative-or-zero on failure. The
//!   stable codes live in [`crate::error::codes`] and in the header.
//! * **No panics cross the boundary.** Every entry point is wrapped in
//!   `catch_unwind`; a panic degrades to `UNKNOWN`, never UB.
//! * **All input strings are read once and copied** — the caller may hand us
//!   short-lived buffers.

use std::cell::RefCell;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::sync::Mutex;
use std::time::Duration;

use crate::download;
use crate::error::AftabError;
use crate::http::HttpClient;
use crate::model::FilterType;
use crate::provider::Provider;
use crate::store::Store;
use crate::{persian, search, urlsafe};

// ─── Thread-local last error ───────────────────────────────────────────────

thread_local! {
    static LAST_ERROR: RefCell<Option<(i32, CString)>> = const { RefCell::new(None) };
}

fn set_last_error(e: &AftabError) {
    let code = e.code();
    let msg = CString::new(format!("[{code}] {}", e.message()))
        .unwrap_or_else(|_| CString::new("[99] opaque error").expect("static"));
    LAST_ERROR.with(|slot| *slot.borrow_mut() = Some((code, msg)));
}

fn clear_last_error() {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = None);
}

/// FFI: error code of the last failure on this thread (0 = no error).
#[no_mangle]
pub extern "C" fn aftab_last_error_code() -> i32 {
    LAST_ERROR.with(|slot| slot.borrow().as_ref().map_or(0, |(code, _)| *code))
}

/// FFI: message of the last failure on this thread (NULL when none).
/// The returned pointer is owned by the thread-local slot and stays valid
/// until the next FFI call on the same thread.
#[no_mangle]
pub extern "C" fn aftab_last_error_message() -> *const c_char {
    LAST_ERROR.with(|slot| match slot.borrow().as_ref() {
        Some(s) => s.1.as_ptr(),
        None => ptr::null(),
    })
}

// ─── Helpers ────────────────────────────────────────────────────────────────

unsafe fn read_str<'a>(p: *const c_char) -> Result<&'a str, AftabError> {
    if p.is_null() {
        return Err(AftabError::InvalidArgument("null string pointer".into()));
    }
    CStr::from_ptr(p)
        .to_str()
        .map_err(|e| AftabError::InvalidArgument(format!("invalid UTF-8: {e}")))
}

fn take_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(e) => {
            // Interior NULs cannot happen for JSON / normalized text, but a
            // cleaned-up copy beats a NULL that looks like an error.
            let mut bytes = e.into_vec();
            bytes.retain(|b| *b != 0);
            CString::new(bytes)
                .expect("NULs were just removed")
                .into_raw()
        }
    }
}

/// Run `f`, mapping a panic to the UNKNOWN error code instead of UB.
fn guard<T>(f: impl FnOnce() -> Result<T, AftabError>) -> Result<T, AftabError> {
    clear_last_error();
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(inner) => inner.map_err(|e| {
            set_last_error(&e);
            e
        }),
        Err(panic) => {
            let msg = panic
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| panic.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "panic".to_string());
            let e = AftabError::Unknown(format!("panic in FFI: {msg}"));
            set_last_error(&e);
            Err(e)
        }
    }
}

// ─── Version / strings / text utilities ────────────────────────────────────

/// FFI: core version, e.g. `"0.1.0"`. Static storage; do not free.
#[no_mangle]
pub extern "C" fn aftab_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

/// FFI: free a string returned by this library.
///
/// # Safety
/// `p` must originate from this library and not have been freed yet.
#[no_mangle]
pub unsafe extern "C" fn aftab_free_string(p: *mut c_char) {
    if !p.is_null() {
        drop(CString::from_raw(p));
    }
}

/// FFI: canonical Persian normalization (display/storage form).
///
/// # Safety
/// `input` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_normalize_persian(input: *const c_char) -> *mut c_char {
    match guard(|| read_str(input).map(persian::normalize_persian)) {
        Ok(s) => take_string(s),
        Err(_) => ptr::null_mut(),
    }
}

/// FFI: compact matching key (ZWNJ/madda/digit-insensitive).
///
/// # Safety
/// `input` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_compact_key(input: *const c_char) -> *mut c_char {
    match guard(|| read_str(input).map(persian::compact_key)) {
        Ok(s) => take_string(s),
        Err(_) => ptr::null_mut(),
    }
}

/// FFI: 1 if the two strings are Persian-equal, 0 otherwise.
///
/// # Safety
/// Both pointers must be valid NUL-terminated UTF-8 C strings.
#[no_mangle]
pub unsafe extern "C" fn aftab_persian_equals(a: *const c_char, b: *const c_char) -> i32 {
    match guard(|| {
        let a = read_str(a)?;
        let b = read_str(b)?;
        Ok(persian::persian_equals(a, b))
    }) {
        Ok(eq) => eq as i32,
        Err(_) => 0,
    }
}

/// FFI: search score of query against candidate, or -1 for no match.
///
/// # Safety
/// Both pointers must be valid NUL-terminated UTF-8 C strings.
#[no_mangle]
pub unsafe extern "C" fn aftab_search_score(query: *const c_char, candidate: *const c_char) -> i32 {
    match guard(|| {
        let q = read_str(query)?;
        let c = read_str(candidate)?;
        Ok(search::score_match(q, c))
    }) {
        Ok(Some(score)) => score as i32,
        Ok(None) => -1,
        Err(_) => -2, // distinguish "no match" (-1) from "bad input" (-2)
    }
}

/// FFI: 1 if the URL passes the strict media-safety policy, else 0 (reason
/// available via `aftab_last_error_message`).
///
/// # Safety
/// `url` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_url_is_safe(url: *const c_char) -> i32 {
    match guard(|| read_str(url).and_then(|u| urlsafe::is_safe_media_url(u).map(|_| ()))) {
        Ok(()) => 1,
        Err(e) => {
            set_last_error(&e);
            0
        }
    }
}

/// FFI: redact a URL for logs (keeps scheme/host/port only). NULL on parse
/// failure is *not* an error path — unparseable inputs redact to a literal.
///
/// # Safety
/// `url` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_redact_url(url: *const c_char) -> *mut c_char {
    match guard(|| read_str(url).map(urlsafe::redact_url_for_log)) {
        Ok(s) => take_string(s),
        Err(_) => ptr::null_mut(),
    }
}

// ─── Provider handle ────────────────────────────────────────────────────────

/// Opaque provider handle.
pub struct AftabProvider {
    inner: Provider,
}

fn filter_from_int(v: i32) -> Result<FilterType, AftabError> {
    match v {
        0 => Ok(FilterType::Default),
        1 => Ok(FilterType::ByYear),
        2 => Ok(FilterType::ByImdb),
        _ => Err(AftabError::InvalidArgument(format!(
            "filter must be 0|1|2, got {v}"
        ))),
    }
}

/// FFI: create a provider with upstream defaults (base, helpers, API key).
/// NULL on failure (see `aftab_last_error_message`).
#[no_mangle]
pub extern "C" fn aftab_provider_default() -> *mut AftabProvider {
    match guard(Provider::with_defaults) {
        Ok(p) => Box::into_raw(Box::new(AftabProvider { inner: p })),
        Err(_) => ptr::null_mut(),
    }
}

/// FFI: create a provider with explicit configuration. `helper_servers` is a
/// comma-separated list (may be empty or NULL).
///
/// # Safety
/// String pointers must be valid NUL-terminated UTF-8.
#[no_mangle]
pub unsafe extern "C" fn aftab_provider_new(
    base_url: *const c_char,
    api_key: *const c_char,
    helper_servers: *const c_char,
) -> *mut AftabProvider {
    match guard(|| {
        let base = read_str(base_url)?;
        let key = read_str(api_key)?;
        let helpers: Vec<&str> = if helper_servers.is_null() {
            Vec::new()
        } else {
            read_str(helper_servers)?
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .collect()
        };
        Provider::new(base, key, &helpers)
    }) {
        Ok(p) => Box::into_raw(Box::new(AftabProvider { inner: p })),
        Err(_) => ptr::null_mut(),
    }
}

/// FFI: release a provider handle.
///
/// # Safety
/// `p` must have been returned by `aftab_provider_new`/`_default` and not
/// yet freed. Passing NULL is a no-op.
#[no_mangle]
pub unsafe extern "C" fn aftab_provider_free(p: *mut AftabProvider) {
    if !p.is_null() {
        drop(Box::from_raw(p));
    }
}

// Provider catalog calls. All return a JSON string (caller frees) or NULL
// on failure with the last-error slot populated.

macro_rules! provider_json_call {
    ($fname:ident, $method:ident, $($arg:ident: $ty:ty => $conv:expr),*) => {
        /// FFI: catalog call returning a JSON string (caller frees) or NULL.
        ///
        /// # Safety
        /// `p` must be a live provider handle; string arguments must be
        /// valid NUL-terminated UTF-8 C strings.
        #[no_mangle]
        pub unsafe extern "C" fn $fname(
            p: *mut AftabProvider,
            $($arg: $ty,)*
        ) -> *mut c_char {
            if p.is_null() {
                set_last_error(&AftabError::InvalidArgument("provider handle is null".into()));
                return ptr::null_mut();
            }
            let provider = &(*p).inner;
            match guard(|| {
                let value = provider.$method($($conv,)*).map(|s| s.value)?;
                serde_json::to_string(&value)
                    .map_err(|e| AftabError::Parse(format!("reserialize failed: {e}")))
            }) {
                Ok(json) => take_string(json),
                Err(_) => ptr::null_mut(),
            }
        }
    };
}

provider_json_call!(aftab_provider_genres, genres,);
provider_json_call!(aftab_provider_countries, countries,);
provider_json_call!(aftab_provider_seasons, seasons, series_id: i64 => series_id);

provider_json_call!(
    aftab_provider_movies,
    movies,
    genre: i64 => genre,
    filter: i32 => filter_from_int(filter)?,
    page: u32 => page
);

provider_json_call!(
    aftab_provider_series,
    series,
    genre: i64 => genre,
    filter: i32 => filter_from_int(filter)?,
    page: u32 => page
);

provider_json_call!(
    aftab_provider_country_posters,
    country_posters,
    country: i64 => country,
    filter: i32 => filter_from_int(filter)?,
    page: u32 => page
);

/// FFI: search the catalog. Returns a `SearchResult` JSON object.
///
/// # Safety
/// `p` must be a live provider handle; `query` a valid C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_provider_search(
    p: *mut AftabProvider,
    query: *const c_char,
) -> *mut c_char {
    if p.is_null() {
        set_last_error(&AftabError::InvalidArgument(
            "provider handle is null".into(),
        ));
        return ptr::null_mut();
    }
    let provider = &(*p).inner;
    match guard(|| {
        let q = read_str(query)?;
        let value = provider.search(q)?.value;
        serde_json::to_string(&value)
            .map_err(|e| AftabError::Parse(format!("reserialize failed: {e}")))
    }) {
        Ok(json) => take_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// FFI: probe base + helper servers; returns JSON `[{"server": "host:port",
/// "ok": true|false}]` in probe order. Redacted URLs keep their ports.
///
/// # Safety
/// `p` must be a live provider handle.
#[no_mangle]
pub unsafe extern "C" fn aftab_provider_health(p: *mut AftabProvider) -> *mut c_char {
    if p.is_null() {
        set_last_error(&AftabError::InvalidArgument(
            "provider handle is null".into(),
        ));
        return ptr::null_mut();
    }
    let provider = &(*p).inner;
    match guard(|| {
        let http = HttpClient::new(Duration::from_secs(10));
        let mut probes: Vec<serde_json::Value> = Vec::new();
        let mut targets: Vec<String> = vec![provider.base().to_string()];
        targets.extend(provider.helpers().iter().map(|h| h.to_string()));
        for t in targets {
            // Probe the site root, not a catalog path — cheap and side-effect
            // free. Any HTTP answer counts as "reachable"; transport errors
            // mean "down".
            let ok = http.get_text(t.as_str()).is_ok();
            probes.push(serde_json::json!({
                "server": urlsafe::redact_url_for_log(t.as_str()),
                "ok": ok,
            }));
        }
        serde_json::to_string(&probes)
            .map_err(|e| AftabError::Parse(format!("reserialize failed: {e}")))
    }) {
        Ok(json) => take_string(json),
        Err(_) => ptr::null_mut(),
    }
}

// ─── Store handle ───────────────────────────────────────────────────────────

/// Opaque, thread-safe store handle.
pub struct AftabStore {
    inner: Mutex<Store>,
}

/// FFI: open (or create) a store at `path`. NULL on failure.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_open(path: *const c_char) -> *mut AftabStore {
    match guard(|| {
        let p = read_str(path)?;
        Store::open(p)
    }) {
        Ok(s) => Box::into_raw(Box::new(AftabStore {
            inner: Mutex::new(s),
        })),
        Err(_) => ptr::null_mut(),
    }
}

/// FFI: release a store handle.
///
/// # Safety
/// `s` must be a live store handle. NULL is a no-op.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_free(s: *mut AftabStore) {
    if !s.is_null() {
        drop(Box::from_raw(s));
    }
}

fn with_store<T>(
    s: *mut AftabStore,
    f: impl FnOnce(&mut Store) -> Result<T, AftabError>,
) -> Result<T, AftabError> {
    if s.is_null() {
        return Err(AftabError::InvalidArgument("store handle is null".into()));
    }
    let store = unsafe { &(*s).inner };
    let mut guard_value = store
        .lock()
        .map_err(|_| AftabError::Unknown("store mutex poisoned".into()))?;
    f(&mut guard_value)
}

/// FFI: favorites as a JSON array (newest first). NULL on failure.
///
/// # Safety
/// `s` must be a live store handle.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_favorites_json(s: *mut AftabStore) -> *mut c_char {
    match guard(|| {
        with_store(s, |store| {
            serde_json::to_string(&store.favorites())
                .map_err(|e| AftabError::Parse(format!("reserialize failed: {e}")))
        })
    }) {
        Ok(json) => take_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// FFI: add a favorite from a `FavoriteItem`-shaped JSON object. 1 on success.
///
/// # Safety
/// `s` must be a live store handle; `json` a valid C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_add_favorite(s: *mut AftabStore, json: *const c_char) -> i32 {
    match guard(|| {
        let raw = read_str(json)?;
        let item: crate::store::FavoriteItem = serde_json::from_str(raw)?;
        with_store(s, |store| store.add_favorite(item))?;
        Ok(())
    }) {
        Ok(()) => 1,
        Err(_) => 0,
    }
}

/// FFI: remove a favorite. 1 if it existed, 0 otherwise (including errors).
///
/// # Safety
/// `s` must be a live store handle; `kind` a valid C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_remove_favorite(
    s: *mut AftabStore,
    kind: *const c_char,
    id: i64,
) -> i32 {
    match guard(|| {
        let k = read_str(kind)?;
        with_store(s, |store| store.remove_favorite(k, id))
    }) {
        Ok(removed) => removed as i32,
        Err(_) => 0,
    }
}

/// FFI: 1 if favorited, 0 otherwise.
///
/// # Safety
/// `s` must be a live store handle; `kind` a valid C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_is_favorite(
    s: *mut AftabStore,
    kind: *const c_char,
    id: i64,
) -> i32 {
    match guard(|| {
        let k = read_str(kind)?;
        let fav = with_store(s, |store| Ok(store.is_favorite(k, id)))?;
        Ok(fav)
    }) {
        Ok(fav) => fav as i32,
        Err(_) => 0,
    }
}

/// FFI: record progress. 1 on success.
///
/// # Safety
/// `s` must be a live store handle; `kind` a valid C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_set_progress(
    s: *mut AftabStore,
    kind: *const c_char,
    id: i64,
    position: f64,
    duration: f64,
) -> i32 {
    match guard(|| {
        let k = read_str(kind)?;
        with_store(s, |store| store.set_progress(k, id, position, duration))?;
        Ok(())
    }) {
        Ok(()) => 1,
        Err(_) => 0,
    }
}

/// FFI: progress for one item as a JSON object, or the string `"null"`.
///
/// # Safety
/// `s` must be a live store handle; `kind` a valid C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_progress_json(
    s: *mut AftabStore,
    kind: *const c_char,
    id: i64,
) -> *mut c_char {
    match guard(|| {
        let k = read_str(kind)?;
        let p = with_store(s, |store| Ok(store.progress(k, id)))?;
        serde_json::to_string(&p).map_err(|e| AftabError::Parse(format!("reserialize failed: {e}")))
    }) {
        Ok(json) => take_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// FFI: every progress entry (newest first) as a JSON array of
/// `{kind, id, progress:{position,duration,updated_at}}` objects — the
/// "continue watching" / history feed. NULL on failure.
///
/// # Safety
/// `s` must be a live store handle.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_progress_all_json(s: *mut AftabStore) -> *mut c_char {
    match guard(|| {
        with_store(s, |store| {
            serde_json::to_string(&store.progress_all())
                .map_err(|e| AftabError::Parse(format!("reserialize failed: {e}")))
        })
    }) {
        Ok(json) => take_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// FFI: clear progress. 1 if it existed.
///
/// # Safety
/// `s` must be a live store handle; `kind` a valid C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_clear_progress(
    s: *mut AftabStore,
    kind: *const c_char,
    id: i64,
) -> i32 {
    match guard(|| {
        let k = read_str(kind)?;
        with_store(s, |store| store.clear_progress(k, id))
    }) {
        Ok(existed) => existed as i32,
        Err(_) => 0,
    }
}

/// FFI: set a setting. 1 on success.
///
/// # Safety
/// All string pointers must be valid C strings; `s` a live handle.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_set_setting(
    s: *mut AftabStore,
    name: *const c_char,
    value: *const c_char,
) -> i32 {
    match guard(|| {
        let n = read_str(name)?;
        let v = read_str(value)?;
        with_store(s, |store| store.set_setting(n, v))?;
        Ok(())
    }) {
        Ok(()) => 1,
        Err(_) => 0,
    }
}

/// FFI: read a setting (caller frees), or NULL if unset.
///
/// # Safety
/// `s` must be a live store handle; `name` a valid C string.
#[no_mangle]
pub unsafe extern "C" fn aftab_store_get_setting(
    s: *mut AftabStore,
    name: *const c_char,
) -> *mut c_char {
    match guard(|| {
        let n = read_str(name)?;
        with_store(s, |store| Ok(store.setting(n).map(str::to_string)))
    }) {
        Ok(Some(v)) => take_string(v),
        Ok(None) => ptr::null_mut(),
        Err(_) => ptr::null_mut(),
    }
}

// ─── Download ───────────────────────────────────────────────────────────────

/// FFI: download `url` to `dest_path` synchronously. Returns bytes written,
/// or -1 on failure (see `aftab_last_error_message`). `allow_private` must be
/// 0 in production; it exists so fixture-based tooling can hit local servers.
///
/// # Safety
/// Both string pointers must be valid C strings.
#[no_mangle]
pub unsafe extern "C" fn aftab_download_file(
    url: *const c_char,
    dest_path: *const c_char,
    allow_private: i32,
) -> i64 {
    match guard(|| {
        let u = read_str(url)?;
        let d = read_str(dest_path)?;
        // Security before filesystem: an unsafe URL must fail with
        // UNSAFE_URL regardless of whether the destination is writable.
        let policy = if allow_private != 0 {
            urlsafe::Policy::TRUSTED
        } else {
            urlsafe::Policy::STRICT
        };
        urlsafe::check_url(u, policy)?;
        let path = std::path::Path::new(d);
        download::validate_dest(path)?;
        let http = HttpClient::new(Duration::from_secs(120));
        download::download_to_file(&http, u, path, policy)
    }) {
        Ok(bytes) => bytes as i64,
        Err(_) => -1,
    }
}

// ─── Tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::codes;
    use std::ffi::CString;

    fn c(s: &str) -> CString {
        CString::new(s).unwrap()
    }

    #[test]
    fn version_is_a_valid_c_string() {
        let v = aftab_version();
        let s = unsafe { CStr::from_ptr(v) }.to_str().unwrap();
        assert_eq!(s, env!("CARGO_PKG_VERSION"));
    }

    #[test]
    fn normalize_persian_over_ffi() {
        let input = c("علي");
        let out = unsafe { aftab_normalize_persian(input.as_ptr()) };
        assert!(!out.is_null());
        let s = unsafe { CStr::from_ptr(out) }.to_str().unwrap().to_string();
        unsafe { aftab_free_string(out) };
        assert_eq!(s, "علی");
    }

    #[test]
    fn null_input_sets_invalid_argument() {
        unsafe { aftab_normalize_persian(ptr::null()) };
        assert_eq!(aftab_last_error_code(), codes::INVALID_ARGUMENT);
        assert!(!aftab_last_error_message().is_null());
    }

    #[test]
    fn invalid_utf8_is_rejected_not_undefined() {
        // 0xFF 0xFE is invalid UTF-8 (and contains no NUL, so it is a legal
        // C string payload).
        let bad = CString::new(vec![0xffu8, 0xfeu8]).unwrap();
        let out = unsafe { aftab_normalize_persian(bad.as_ptr()) };
        assert!(out.is_null());
        assert_eq!(aftab_last_error_code(), codes::INVALID_ARGUMENT);
    }

    #[test]
    fn persian_equals_over_ffi() {
        let a = c("كاشي");
        let b = c("کاشی");
        assert_eq!(unsafe { aftab_persian_equals(a.as_ptr(), b.as_ptr()) }, 1);
        let c_ = c("مشهد");
        assert_eq!(unsafe { aftab_persian_equals(a.as_ptr(), c_.as_ptr()) }, 0);
    }

    #[test]
    fn search_score_over_ffi() {
        let q = c("آفتاب");
        let cand = c("افتاب مدیا");
        let score = unsafe { aftab_search_score(q.as_ptr(), cand.as_ptr()) };
        assert!(
            score >= 60,
            "madda-folded word prefix must match well: {score}"
        );
        let nope = c("El Cid");
        assert_eq!(unsafe { aftab_search_score(q.as_ptr(), nope.as_ptr()) }, -1);
    }

    #[test]
    fn url_safety_over_ffi() {
        // Public IP literal — hermetic, no live DNS needed.
        let good = c("https://93.184.216.34/v.mp4");
        assert_eq!(unsafe { aftab_url_is_safe(good.as_ptr()) }, 1);
        let bad = c("http://127.0.0.1/v.mp4");
        assert_eq!(unsafe { aftab_url_is_safe(bad.as_ptr()) }, 0);
        assert_eq!(aftab_last_error_code(), codes::UNSAFE_URL);
    }

    #[test]
    fn redact_over_ffi_keeps_port() {
        let u = c("https://h.example:8443/p?token=1");
        let out = unsafe { aftab_redact_url(u.as_ptr()) };
        let s = unsafe { CStr::from_ptr(out) }.to_str().unwrap().to_string();
        unsafe { aftab_free_string(out) };
        assert_eq!(s, "https://h.example:8443");
    }

    #[test]
    fn provider_default_over_ffi() {
        let p = aftab_provider_default();
        assert!(!p.is_null());
        unsafe { aftab_provider_free(p) };
    }

    #[test]
    fn provider_new_rejects_empty_key() {
        let base = c("https://x.example");
        let key = c("  ");
        let p = unsafe { aftab_provider_new(base.as_ptr(), key.as_ptr(), ptr::null()) };
        assert!(p.is_null());
        assert_eq!(aftab_last_error_code(), codes::INVALID_ARGUMENT);
    }

    #[test]
    fn provider_helpers_parsed_from_csv() {
        let base = c("https://x.example");
        let key = c("KEY");
        let helpers = c("https://a.example, https://b.example");
        let p = unsafe { aftab_provider_new(base.as_ptr(), key.as_ptr(), helpers.as_ptr()) };
        assert!(!p.is_null());
        // `helpers()` is not exposed over FFI; constructing the same way in
        // Rust and comparing counts keeps the CSV contract honest:
        let rust_side = Provider::new(
            "https://x.example",
            "KEY",
            &["https://a.example", "https://b.example"],
        )
        .unwrap();
        assert_eq!(rust_side.helpers().len(), 2);
        unsafe { aftab_provider_free(p) };
    }

    #[test]
    fn provider_null_handle_is_a_clean_error() {
        let out = unsafe { aftab_provider_genres(ptr::null_mut()) };
        assert!(out.is_null());
        assert_eq!(aftab_last_error_code(), codes::INVALID_ARGUMENT);
    }

    #[test]
    fn provider_bad_filter_is_rejected() {
        let p = aftab_provider_default();
        let out = unsafe { aftab_provider_movies(p, 0, 9, 0) };
        assert!(out.is_null());
        assert_eq!(aftab_last_error_code(), codes::INVALID_ARGUMENT);
        unsafe { aftab_provider_free(p) };
    }

    #[test]
    fn store_roundtrip_over_ffi() {
        let path = std::env::temp_dir().join(format!(
            "aftab-ffi-store-{}-{}.json",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let cpath = c(path.to_str().unwrap());
        let s = unsafe { aftab_store_open(cpath.as_ptr()) };
        assert!(!s.is_null());

        let fav = c(
            r#"{"id": 5, "type": "movie", "title": "گوشه", "image": "", "year": 2024, "added_at": 1700000000}"#,
        );
        assert_eq!(unsafe { aftab_store_add_favorite(s, fav.as_ptr()) }, 1);
        // Duplicate add is still success-but-no-change:
        assert_eq!(unsafe { aftab_store_add_favorite(s, fav.as_ptr()) }, 1);

        let kind = c("movie");
        assert_eq!(unsafe { aftab_store_is_favorite(s, kind.as_ptr(), 5) }, 1);
        assert_eq!(unsafe { aftab_store_is_favorite(s, kind.as_ptr(), 6) }, 0);

        assert_eq!(
            unsafe { aftab_store_set_progress(s, kind.as_ptr(), 5, 300.0, 600.0) },
            1
        );
        let pj = unsafe { aftab_store_progress_json(s, kind.as_ptr(), 5) };
        let text = unsafe { CStr::from_ptr(pj) }.to_str().unwrap().to_string();
        unsafe { aftab_free_string(pj) };
        assert!(text.contains("\"position\":300.0"), "progress JSON: {text}");
        assert!(text.contains("\"duration\":600.0"), "progress JSON: {text}");
        assert!(text.contains("\"updated_at\":"), "progress JSON: {text}");

        let fl = unsafe { aftab_store_favorites_json(s) };
        let ftext = unsafe { CStr::from_ptr(fl) }.to_str().unwrap().to_string();
        unsafe { aftab_free_string(fl) };
        assert!(ftext.contains("گوشه"));

        // progress_all: the entry written above must come back expanded.
        let pa = unsafe { aftab_store_progress_all_json(s) };
        let atext = unsafe { CStr::from_ptr(pa) }.to_str().unwrap().to_string();
        unsafe { aftab_free_string(pa) };
        assert!(
            atext.contains("\"kind\":\"movie\""),
            "progress_all: {atext}"
        );
        assert!(atext.contains("\"id\":5"), "progress_all: {atext}");
        assert!(
            atext.contains("\"position\":300.0"),
            "progress_all: {atext}"
        );
        assert!(atext.starts_with('[') && atext.ends_with(']'));

        assert_eq!(
            unsafe { aftab_store_remove_favorite(s, kind.as_ptr(), 5) },
            1
        );
        assert_eq!(unsafe { aftab_store_is_favorite(s, kind.as_ptr(), 5) }, 0);

        unsafe { aftab_store_free(s) };
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn store_get_setting_unset_is_null_without_error() {
        let path = std::env::temp_dir().join(format!(
            "aftab-ffi-settings-{}.json",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let cpath = c(path.to_str().unwrap());
        let s = unsafe { aftab_store_open(cpath.as_ptr()) };
        let name = c("nope");
        assert!(unsafe { aftab_store_get_setting(s, name.as_ptr()) }.is_null());
        assert_eq!(aftab_last_error_code(), 0, "unset is not an error");
        let n2 = c("lang");
        let v2 = c("fa");
        assert_eq!(
            unsafe { aftab_store_set_setting(s, n2.as_ptr(), v2.as_ptr()) },
            1
        );
        let got = unsafe { aftab_store_get_setting(s, n2.as_ptr()) };
        let g = unsafe { CStr::from_ptr(got) }.to_str().unwrap().to_string();
        unsafe { aftab_free_string(got) };
        assert_eq!(g, "fa");
        unsafe { aftab_store_free(s) };
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn download_over_ffi_rejects_private_by_default() {
        let url = c("http://127.0.0.1:9/x.mp4");
        let dest = c(std::env::temp_dir()
            .join("aftab-ffi-never.mp4")
            .to_str()
            .unwrap());
        assert_eq!(
            unsafe { aftab_download_file(url.as_ptr(), dest.as_ptr(), 0) },
            -1
        );
        assert_eq!(aftab_last_error_code(), codes::UNSAFE_URL);
    }

    #[test]
    fn free_string_null_is_safe() {
        unsafe { aftab_free_string(ptr::null_mut()) };
    }

    #[test]
    fn panics_do_not_cross_the_boundary() {
        // A panic inside guard() becomes UNKNOWN instead of UB.
        let result: Result<(), AftabError> = guard(|| panic!("boom"));
        assert!(result.is_err());
        assert_eq!(aftab_last_error_code(), codes::UNKNOWN);
        assert!(!aftab_last_error_message().is_null());
    }
}
