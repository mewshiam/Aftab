/// Favorites / progress / settings, persisted by the core's atomic JSON
/// store. All calls run in `Isolate.run` with a fresh store handle — the
/// atomic-write design in `core/src/store.rs` makes that safe.

library aftab_store;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/sources.dart';
import 'aftab_ffi.dart';
import 'models.dart';

/// One persisted favorite (shape of `FavoriteItem` in the core).
class Favorite {
  const Favorite({
    required this.id,
    required this.kind,
    required this.title,
    required this.image,
    required this.year,
    required this.addedAt,
  });

  final int id;
  final String kind;
  final String title;
  final String image;
  final int year;
  final int addedAt;

  factory Favorite.fromJson(Map<String, dynamic> json) => Favorite(
        id: (json['id'] as num?)?.toInt() ?? 0,
        kind: json['type'] as String? ?? '',
        title: json['title'] as String? ?? '',
        image: json['image'] as String? ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        addedAt: (json['added_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': kind,
        'title': title,
        'image': image,
        'year': year,
        'added_at': addedAt,
      };
}

/// Watch progress for one item.
class WatchProgress {
  const WatchProgress({
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
  });

  final double positionSeconds;
  final double durationSeconds;
  final int updatedAt;

  double get fraction {
    if (durationSeconds <= 0) return 0;
    final f = positionSeconds / durationSeconds;
    if (f < 0) return 0;
    if (f > 1) return 1;
    return f;
  }

  factory WatchProgress.fromJson(Map<String, dynamic> json) => WatchProgress(
        positionSeconds: (json['position'] as num?)?.toDouble() ?? 0,
        durationSeconds: (json['duration'] as num?)?.toDouble() ?? 0,
        updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      );
}

/// Where the store file lives. `PathProvider` needs plugins on the platform
/// side; in `flutter test` there is no plugin, so a temp directory is used.
Future<String> storePath() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'aftab-store.json');
  } catch (_) {
    return p.join(Directory.systemTemp.path, 'aftab-store-test.json');
  }
}

class AftabStore implements StoreSource {
  const AftabStore._();

  static const AftabStore instance = AftabStore._();

  /// All favorites, newest first.
  @override
  Future<List<Favorite>> favorites() async {
    final path = await storePath();
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<List<Favorite>>(path, (store) {
        final raw = ffi.favoritesJson(store);
        final decoded = jsonDecode(raw);
        if (decoded is! List) return const <Favorite>[];
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(Favorite.fromJson)
            .toList(growable: false);
      });
    });
  }

  /// Add or refresh a favorite for [item].
  @override
  Future<bool> addFavorite(CatalogItem item) async {
    final path = await storePath();
    final json = jsonEncode(Favorite(
      id: item.id,
      kind: item.kind,
      title: item.title,
      image: item.image,
      year: item.year,
      addedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ).toJson());
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<bool>(path, (store) => ffi.addFavorite(store, json));
    });
  }

  /// Remove the favorite for [item]; true if it existed.
  @override
  Future<bool> removeFavorite(CatalogItem item) async {
    final path = await storePath();
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<bool>(
          path, (store) => ffi.removeFavorite(store, item.kind, item.id));
    });
  }

  /// Is [item] favorited?
  @override
  Future<bool> isFavorite(CatalogItem item) async {
    final path = await storePath();
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<bool>(
          path, (store) => ffi.isFavorite(store, item.kind, item.id));
    });
  }

  /// Record playback progress.
  @override
  Future<bool> setProgress(
      CatalogItem item, double positionSeconds, double durationSeconds) async {
    final path = await storePath();
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<bool>(path,
          (store) => ffi.setProgress(store, item.kind, item.id, positionSeconds, durationSeconds));
    });
  }

  /// Read playback progress; null when absent.
  @override
  Future<WatchProgress?> progress(CatalogItem item) async {
    final path = await storePath();
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<WatchProgress?>(
        path,
        (store) {
          final json = ffi.progress(store, item.kind, item.id);
          if (json == null) return null;
          return WatchProgress.fromJson(json);
        },
      );
    });
  }

  /// Every progress entry, newest first — continue watching / history.
  @override
  Future<List<WatchEntry>> progressAll() async {
    final path = await storePath();
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<List<WatchEntry>>(path, (store) {
        final raw = ffi.progressAllJson(store);
        final decoded = jsonDecode(raw);
        if (decoded is! List) return const <WatchEntry>[];
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(WatchEntry.fromJson)
            .toList(growable: false);
      });
    });
  }

  /// Clear playback progress ("watched" / "start over").
  @override
  Future<bool> clearProgress(CatalogItem item) async {
    final path = await storePath();
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<bool>(
          path, (store) => ffi.clearProgress(store, item.kind, item.id));
    });
  }

  /// Write a setting.
  @override
  Future<bool> setSetting(String name, String value) async {
    final path = await storePath();
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<bool>(
          path, (store) => ffi.setSetting(store, name, value));
    });
  }

  /// Read a setting; null when unset.
  @override
  Future<String?> getSetting(String name) async {
    final path = await storePath();
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withStore<String?>(
          path, (store) => ffi.getSetting(store, name));
    });
  }
}
