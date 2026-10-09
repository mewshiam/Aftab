//! Local persistence: favorites, watch progress, and settings.
//!
//! One JSON document per install, written atomically (temp file + `rename`)
//! so a crash mid-write can never corrupt state — the pattern upstream
//! implements with `SharedPreferences`, which does not exist on Windows.

use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{AftabError, AftabResult};

/// On-disk schema version. Bump and migrate in [`Store::migrate`] when the
/// shape changes.
const SCHEMA_VERSION: u32 = 1;

/// A favorite entry.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FavoriteItem {
    /// Content id as reported by the provider.
    pub id: i64,
    /// `"movie"` or `"serie"`.
    #[serde(rename = "type")]
    pub kind: String,
    pub title: String,
    #[serde(default)]
    pub image: String,
    #[serde(default)]
    pub year: i32,
    /// Unix seconds when the favorite was added.
    pub added_at: i64,
}

/// Watch progress for one piece of content.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Progress {
    /// Playback position, seconds.
    pub position: f64,
    /// Total duration, seconds (0 if unknown).
    pub duration: f64,
    /// Unix seconds of the last update.
    pub updated_at: i64,
}

impl Progress {
    /// Fraction watched, 0.0–1.0 (unknown duration → 0.0).
    pub fn fraction(&self) -> f64 {
        if self.duration <= 0.0 {
            0.0
        } else {
            (self.position / self.duration).clamp(0.0, 1.0)
        }
    }
}

/// One progress entry with its content key, as returned by [`Store::progress_all`].
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProgressEntry {
    /// `"movie"` or `"serie"`.
    pub kind: String,
    /// Provider id of the movie or series.
    pub id: i64,
    /// The stored progress.
    pub progress: Progress,
}

/// The whole persisted document.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoreData {
    pub version: u32,
    pub favorites: Vec<FavoriteItem>,
    /// Keyed `"{type}:{id}"`.
    pub progress: std::collections::BTreeMap<String, Progress>,
    pub settings: std::collections::BTreeMap<String, String>,
}

impl Default for StoreData {
    fn default() -> Self {
        StoreData {
            version: SCHEMA_VERSION,
            favorites: Vec::new(),
            progress: Default::default(),
            settings: Default::default(),
        }
    }
}

/// A handle to the on-disk store. All mutations write through immediately.
pub struct Store {
    path: PathBuf,
    data: StoreData,
}

impl Store {
    /// Open (or create) the store at `path`.
    pub fn open<P: AsRef<Path>>(path: P) -> AftabResult<Store> {
        let path = path.as_ref().to_path_buf();
        let data = match fs::read_to_string(&path) {
            Ok(text) => {
                let parsed: StoreData = serde_json::from_str(&text).map_err(|e| {
                    AftabError::Storage(format!("corrupt store at {}: {e}", path.display()))
                })?;
                Store::migrate(parsed)?
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => StoreData::default(),
            Err(e) => {
                return Err(AftabError::Storage(format!(
                    "cannot read {}: {e}",
                    path.display()
                )))
            }
        };
        Ok(Store { path, data })
    }

    /// Schema migrations. v1 is current; future versions chain from here.
    fn migrate(mut data: StoreData) -> AftabResult<StoreData> {
        if data.version > SCHEMA_VERSION {
            return Err(AftabError::Storage(format!(
                "store schema {} is newer than this build understands ({SCHEMA_VERSION})",
                data.version
            )));
        }
        data.version = SCHEMA_VERSION;
        Ok(data)
    }

    /// Persist atomically: write alongside the target, then rename over it.
    fn save(&self) -> AftabResult<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let tmp = self.path.with_extension("json.tmp");
        let text = serde_json::to_string_pretty(&self.data)
            .map_err(|e| AftabError::Storage(format!("serialize failed: {e}")))?;
        fs::write(&tmp, text.as_bytes())?;
        fs::rename(&tmp, &self.path)?;
        Ok(())
    }

    /// A snapshot of the whole document (FFI serializes this straight out).
    pub fn data(&self) -> &StoreData {
        &self.data
    }

    fn key(kind: &str, id: i64) -> String {
        format!("{kind}:{id}")
    }

    // ── Favorites ────────────────────────────────────────────────────────

    /// All favorites, newest first.
    pub fn favorites(&self) -> Vec<FavoriteItem> {
        let mut f = self.data.favorites.clone();
        f.sort_by_key(|f| std::cmp::Reverse(f.added_at));
        f
    }

    /// Add (or refresh) a favorite. Returns true if it was newly added.
    pub fn add_favorite(&mut self, item: FavoriteItem) -> AftabResult<bool> {
        let key = Store::key(&item.kind, item.id);
        if item.kind.trim().is_empty() {
            return Err(AftabError::InvalidArgument("favorite kind is empty".into()));
        }
        let existed = self
            .data
            .favorites
            .iter()
            .any(|f| Store::key(&f.kind, f.id) == key);
        if existed {
            return Ok(false);
        }
        self.data.favorites.push(item);
        self.save()?;
        Ok(true)
    }

    /// Remove a favorite. Returns true if it existed.
    pub fn remove_favorite(&mut self, kind: &str, id: i64) -> AftabResult<bool> {
        let before = self.data.favorites.len();
        self.data
            .favorites
            .retain(|f| !(f.kind == kind && f.id == id));
        let removed = before != self.data.favorites.len();
        if removed {
            self.save()?;
        }
        Ok(removed)
    }

    /// Is this content favorited?
    pub fn is_favorite(&self, kind: &str, id: i64) -> bool {
        self.data
            .favorites
            .iter()
            .any(|f| f.kind == kind && f.id == id)
    }

    // ── Progress ─────────────────────────────────────────────────────────

    /// Record playback progress (seconds).
    pub fn set_progress(
        &mut self,
        kind: &str,
        id: i64,
        position: f64,
        duration: f64,
    ) -> AftabResult<()> {
        if !(position.is_finite() && position >= 0.0) {
            return Err(AftabError::InvalidArgument(format!(
                "position must be finite and non-negative, got {position}"
            )));
        }
        if !(duration.is_finite() && duration >= 0.0) {
            return Err(AftabError::InvalidArgument(format!(
                "duration must be finite and non-negative, got {duration}"
            )));
        }
        let key = Store::key(kind, id);
        self.data.progress.insert(
            key,
            Progress {
                position,
                duration,
                updated_at: now_unix(),
            },
        );
        self.save()
    }

    /// Read playback progress, if any.
    pub fn progress(&self, kind: &str, id: i64) -> Option<Progress> {
        self.data.progress.get(&Store::key(kind, id)).copied()
    }

    /// All progress entries, newest first — "continue watching" / history.
    ///
    /// The map is keyed `"{type}:{id}"`; entries are re-expanded into
    /// (kind, id) pairs so callers never need to know the key format.
    pub fn progress_all(&self) -> Vec<ProgressEntry> {
        let mut entries: Vec<ProgressEntry> = self
            .data
            .progress
            .iter()
            .filter_map(|(key, p)| {
                let (kind, id) = key.rsplit_once(':')?;
                let id: i64 = id.parse().ok()?;
                Some(ProgressEntry {
                    kind: kind.to_string(),
                    id,
                    progress: *p,
                })
            })
            .collect();
        entries.sort_by_key(|e| std::cmp::Reverse(e.progress.updated_at));
        entries
    }

    /// Drop "continue watching" state (explicit user action or finished).
    pub fn clear_progress(&mut self, kind: &str, id: i64) -> AftabResult<bool> {
        let key = Store::key(kind, id);
        let existed = self.data.progress.remove(&key).is_some();
        if existed {
            self.save()?;
        }
        Ok(existed)
    }

    // ── Settings ─────────────────────────────────────────────────────────

    /// Read a setting.
    pub fn setting(&self, name: &str) -> Option<&str> {
        self.data.settings.get(name).map(|s| s.as_str())
    }

    /// Write a setting.
    pub fn set_setting(&mut self, name: &str, value: &str) -> AftabResult<()> {
        self.data
            .settings
            .insert(name.to_string(), value.to_string());
        self.save()
    }
}

fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::codes;

    fn tmp_store(tag: &str) -> (Store, PathBuf) {
        let path = std::env::temp_dir().join(format!(
            "aftab-store-test-{tag}-{}-{}.json",
            std::process::id(),
            now_unix()
        ));
        (Store::open(&path).unwrap(), path)
    }

    fn fav(id: i64, kind: &str) -> FavoriteItem {
        FavoriteItem {
            id,
            kind: kind.into(),
            title: format!("عنوان {id}"),
            image: String::new(),
            year: 2024,
            added_at: 1000 + id,
        }
    }

    #[test]
    fn opens_missing_file_as_fresh_store() {
        let (mut s, path) = tmp_store("fresh");
        assert!(s.favorites().is_empty());
        assert!(s.add_favorite(fav(1, "movie")).unwrap());
        assert!(path.exists(), "saving creates the file");
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn favorites_roundtrip_through_disk() {
        let (mut s, path) = tmp_store("roundtrip");
        s.add_favorite(fav(7, "serie")).unwrap();
        s.add_favorite(fav(3, "movie")).unwrap();
        drop(s);

        let reopened = Store::open(&path).unwrap();
        assert_eq!(reopened.favorites().len(), 2);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn favorites_are_deduplicated_by_kind_and_id() {
        let (mut s, path) = tmp_store("dedup");
        assert!(s.add_favorite(fav(5, "movie")).unwrap());
        assert!(
            !s.add_favorite(fav(5, "movie")).unwrap(),
            "second add is a no-op"
        );
        assert!(
            s.add_favorite(fav(5, "serie")).unwrap(),
            "same id, other kind is distinct"
        );
        assert_eq!(s.favorites().len(), 2);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn favorites_listed_newest_first() {
        let (mut s, path) = tmp_store("order");
        s.add_favorite(fav(1, "movie")).unwrap(); // added_at 1001
        s.add_favorite(fav(9, "movie")).unwrap(); // added_at 1009
        let order: Vec<i64> = s.favorites().iter().map(|f| f.id).collect();
        assert_eq!(order, vec![9, 1]);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn remove_favorite_reports_existence() {
        let (mut s, path) = tmp_store("remove");
        s.add_favorite(fav(2, "movie")).unwrap();
        assert!(s.remove_favorite("movie", 2).unwrap());
        assert!(!s.remove_favorite("movie", 2).unwrap());
        assert!(!s.remove_favorite("serie", 2).unwrap());
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn progress_roundtrip_and_fraction() {
        let (mut s, path) = tmp_store("progress");
        s.set_progress("movie", 11, 540.0, 1080.0).unwrap();
        let p = s.progress("movie", 11).unwrap();
        assert!((p.fraction() - 0.5).abs() < 1e-9);
        assert!(p.updated_at > 1_600_000_000);
        assert!(s.progress("movie", 12).is_none());
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn progress_rejects_nans_and_negatives() {
        let (mut s, path) = tmp_store("nan");
        for (pos, dur) in [(-1.0, 10.0), (f64::NAN, 10.0), (5.0, f64::INFINITY)] {
            let err = s.set_progress("movie", 1, pos, dur).unwrap_err();
            assert_eq!(err.code(), codes::INVALID_ARGUMENT);
        }
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn clear_progress_only_touches_its_key() {
        let (mut s, path) = tmp_store("clear");
        s.set_progress("movie", 1, 10.0, 100.0).unwrap();
        s.set_progress("movie", 2, 20.0, 100.0).unwrap();
        assert!(s.clear_progress("movie", 1).unwrap());
        assert!(!s.clear_progress("movie", 1).unwrap());
        assert!(s.progress("movie", 2).is_some());
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn progress_all_expands_keys_and_sorts_newest_first() {
        let (mut s, path) = tmp_store("all");
        s.set_progress("movie", 11, 540.0, 1080.0).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        s.set_progress("serie", 7, 30.0, 1800.0).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        s.set_progress("movie", 12, 1.0, 600.0).unwrap();

        let all = s.progress_all();
        assert_eq!(all.len(), 3);
        // Newest first: the last write must lead.
        assert_eq!((all[0].kind.as_str(), all[0].id), ("movie", 12));
        assert_eq!((all[1].kind.as_str(), all[1].id), ("serie", 7));
        assert_eq!((all[2].kind.as_str(), all[2].id), ("movie", 11));
        assert!((all[1].progress.fraction() - 30.0 / 1800.0).abs() < 1e-9);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn settings_roundtrip() {
        let (mut s, path) = tmp_store("settings");
        s.set_setting("subtitle_size", "28").unwrap();
        assert_eq!(s.setting("subtitle_size"), Some("28"));
        s.set_setting("subtitle_size", "32").unwrap();
        assert_eq!(s.setting("subtitle_size"), Some("32"));
        drop(s);
        assert_eq!(
            Store::open(&path).unwrap().setting("subtitle_size"),
            Some("32")
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn corrupt_file_is_a_storage_error() {
        let path = std::env::temp_dir().join(format!("aftab-corrupt-{}.json", std::process::id()));
        std::fs::write(&path, b"{not json").unwrap();
        let err = Store::open(&path).err().unwrap();
        assert_eq!(err.code(), codes::STORAGE);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn future_schema_is_refused() {
        let path = std::env::temp_dir().join(format!("aftab-future-{}.json", std::process::id()));
        std::fs::write(
            &path,
            br#"{"version":99,"favorites":[],"progress":{},"settings":{}}"#,
        )
        .unwrap();
        let err = Store::open(&path).err().unwrap();
        assert_eq!(err.code(), codes::STORAGE);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn writes_are_atomic_no_tmp_left_behind() {
        let (mut s, path) = tmp_store("atomic");
        s.set_setting("k", "v").unwrap();
        let tmp = path.with_extension("json.tmp");
        assert!(!tmp.exists(), "rename removed the temp file");
        let _ = std::fs::remove_file(&path);
    }
}
