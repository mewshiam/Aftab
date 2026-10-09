/// Watch index: display metadata (title / artwork) for progress entries.
///
/// The core's progress map stores only positions keyed by `"{type}:{id}"`.
/// Whenever playback starts, the player records the title and poster URL
/// here (a small JSON document inside the settings map), so "continue
/// watching" rows have something human-readable to show without an extra
/// provider round-trip.

library aftab_watch_index;

import 'dart:convert';

import '../core/models.dart';
import 'sources.dart';

/// One indexed, partially-watched title.
class WatchIndexEntry {
  const WatchIndexEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.image,
    required this.updatedAt,
  });

  final String kind;
  final int id;
  final String title;
  final String image;
  final int updatedAt;

  /// Entry key matching the core's progress key: `"{type}:{id}"`.
  String get key => '$kind:$id';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'id': id,
        'title': title,
        'image': image,
        'updated_at': updatedAt,
      };

  factory WatchIndexEntry.fromJson(Map<String, dynamic> json) =>
      WatchIndexEntry(
        kind: json['kind'] as String? ?? '',
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        image: json['image'] as String? ?? '',
        updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      );
}

/// Encode/decode helpers (pure functions, unit-testable).
String encodeWatchIndex(Map<String, WatchIndexEntry> index) {
  final list = index.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return jsonEncode(list.map((e) => e.toJson()).toList(growable: false));
}

Map<String, WatchIndexEntry> decodeWatchIndex(String? raw) {
  if (raw == null || raw.isEmpty) return <String, WatchIndexEntry>{};
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return <String, WatchIndexEntry>{};
  }
  if (decoded is! List) return <String, WatchIndexEntry>{};
  final entries = decoded
      .whereType<Map<String, dynamic>>()
      .map(WatchIndexEntry.fromJson);
  return <String, WatchIndexEntry>{for (final e in entries) e.key: e};
}

/// Registry façade over the settings-backed JSON document.
class WatchIndex {
  WatchIndex({required StoreSource store}) : _store = store;

  static const _kKey = 'ui.watch_index';

  final StoreSource _store;

  /// Newest-first snapshot, or null when unreadable.
  Future<List<WatchIndexEntry>> entries() async {
    final map = await _read();
    final list = map.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<WatchIndexEntry?> entry(String kind, int id) async =>
      (await _read())['$kind:$id'];

  /// Record (or refresh) display info for a title that just started
  /// playing. Also prunes entries older than 90 days to keep the
  /// document small.
  Future<void> record(CatalogItem item) async {
    final map = await _read();
    map[item.kindKey] = WatchIndexEntry(
      kind: item.kind,
      id: item.id,
      title: item.title,
      image: item.image,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final cutoff =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - 90 * 24 * 3600;
    map.removeWhere((_, e) => e.updatedAt < cutoff);
    await _store.setSetting(_kKey, encodeWatchIndex(map));
  }

  Future<Map<String, WatchIndexEntry>> _read() async {
    try {
      return decodeWatchIndex(await _store.getSetting(_kKey));
    } catch (_) {
      return <String, WatchIndexEntry>{};
    }
  }
}

extension on CatalogItem {
  String get kindKey => '$kind:$id';
}
