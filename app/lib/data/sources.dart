/// UI-facing data contracts.
///
/// Screens depend on [CatalogSource] and [StoreSource] instead of the FFI
/// clients directly, so widget tests can inject in-memory fakes while
/// production wires the real FFI-backed implementations
/// (`CatalogClient` / `AftabStore`).

library aftab_sources;

import '../core/models.dart';
import '../core/store.dart';

/// Catalog reads (provider API through the Rust core).
abstract class CatalogSource {
  Future<List<CatalogItem>> movies({
    int genre,
    CatalogSort sort,
    int page,
  });

  Future<List<CatalogItem>> series({
    int genre,
    CatalogSort sort,
    int page,
  });

  Future<List<CatalogItem>> search(String query);

  Future<List<Genre>> genres();

  Future<List<Season>> seasons(int seriesId);

  /// Resolves a partial item (favorites / continue-watching entries) back
  /// to a full catalog item with sources, via the provider's search —
  /// same id first, identical title as fallback.
  Future<CatalogItem?> resolveItem(CatalogItem partial);

  Future<List<Map<String, dynamic>>> health();

  Future<List<CatalogItem>> rank(
      String query, List<CatalogItem> items);
}

/// Local persistence (favorites, progress, settings) + downloads.
abstract class StoreSource {
  Future<List<Favorite>> favorites();

  Future<bool> addFavorite(CatalogItem item);

  Future<bool> removeFavorite(CatalogItem item);

  Future<bool> isFavorite(CatalogItem item);

  Future<bool> setProgress(
      CatalogItem item, double positionSeconds, double durationSeconds);

  Future<WatchProgress?> progress(CatalogItem item);

  /// Every progress entry, newest first — continue watching / history.
  Future<List<WatchEntry>> progressAll();

  Future<bool> clearProgress(CatalogItem item);

  Future<bool> setSetting(String name, String value);

  Future<String?> getSetting(String name);
}

/// One row of "continue watching" / history, straight from the core's
/// `aftab_store_progress_all_json`.
class WatchEntry {
  const WatchEntry({
    required this.kind,
    required this.id,
    required this.progress,
  });

  /// `"movie"` or `"serie"` — the store's content key.
  final String kind;
  final int id;
  final WatchProgress progress;

  factory WatchEntry.fromJson(Map<String, dynamic> json) {
    final rawProgress = json['progress'];
    return WatchEntry(
      kind: json['kind'] as String? ?? '',
      id: (json['id'] as num?)?.toInt() ?? 0,
      progress: rawProgress is Map<String, dynamic>
          ? WatchProgress.fromJson(rawProgress)
          : const WatchProgress(
              positionSeconds: 0, durationSeconds: 0, updatedAt: 0),
    );
  }
}
