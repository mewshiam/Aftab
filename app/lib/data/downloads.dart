/// Offline downloads: files fetched by the core's resumable downloader,
/// with a small metadata index in the settings map.
///
/// The core's `aftab_download_file` is synchronous and resumable
/// (HTTP Range), so downloads run inside `Isolate.run` and the UI shows an
/// indeterminate "downloading" state until the byte count returns.

library aftab_downloads;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/aftab_ffi.dart';
import '../core/models.dart';
import 'sources.dart';

/// One persisted download record.
class DownloadRecord {
  const DownloadRecord({
    required this.kind,
    required this.id,
    required this.title,
    required this.image,
    required this.path,
    required this.bytes,
    required this.addedAt,
  });

  final String kind;
  final int id;
  final String title;
  final String image;
  final String path;
  final int bytes;
  final int addedAt;

  String get key => '$kind:$id';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'id': id,
        'title': title,
        'image': image,
        'path': path,
        'bytes': bytes,
        'added_at': addedAt,
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) =>
      DownloadRecord(
        kind: json['kind'] as String? ?? '',
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        image: json['image'] as String? ?? '',
        path: json['path'] as String? ?? '',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        addedAt: (json['added_at'] as num?)?.toInt() ?? 0,
      );
}

/// Where downloaded media lives. Falls back to a temp directory in tests.
Future<String> downloadsDirPath() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final target = Directory(p.join(dir.path, 'downloads'));
    if (!target.existsSync()) target.createSync(recursive: true);
    return target.path;
  } catch (_) {
    return Directory.systemTemp.path;
  }
}

/// Encode/decode helpers (pure, unit-testable).
String encodeDownloads(List<DownloadRecord> records) => jsonEncode(
    records.map((r) => r.toJson()).toList(growable: false));

List<DownloadRecord> decodeDownloads(String? raw) {
  if (raw == null || raw.isEmpty) return const <DownloadRecord>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const <DownloadRecord>[];
  }
  if (decoded is! List) return const <DownloadRecord>[];
  final records =
      decoded.whereType<Map<String, dynamic>>().map(DownloadRecord.fromJson);
  // Prune records whose file vanished (e.g. external cleanup).
  return records.where((r) => File(r.path).existsSync()).toList(growable: false);
}

class DownloadManager {
  DownloadManager({required StoreSource store}) : _store = store;

  static const _kKey = 'ui.downloads';

  final StoreSource _store;

  /// All download records, newest first (missing files pruned).
  Future<List<DownloadRecord>> records() async {
    final list = await _read();
    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  Future<DownloadRecord?> recordFor(CatalogItem item) async {
    final list = await _read();
    for (final r in list) {
      if (r.kind == item.kind && r.id == item.id) return r;
    }
    return null;
  }

  /// Downloads [source] of [item] through the core's resumable
  /// downloader. Returns the finished record. Throws [AftabException] on
  /// failure (surfaced by the UI as an error snackbar).
  Future<DownloadRecord> download(CatalogItem item, Source source) async {
    final dir = await downloadsDirPath();
    final ext = source.type.isEmpty ? 'mp4' : source.type;
    final path = p.join(dir, 'movie-${item.id}.$ext');
    final bytes = await Isolate.run(() {
      return AftabFfi.instance.downloadFile(source.url, path);
    });
    final record = DownloadRecord(
      kind: item.kind,
      id: item.id,
      title: item.title,
      image: item.image,
      path: path,
      bytes: bytes,
      addedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final list = await _read();
    list.removeWhere((r) => r.key == record.key);
    list.add(record);
    await _store.setSetting(_kKey, encodeDownloads(list));
    return record;
  }

  /// Deletes the file and the record.
  Future<void> remove(DownloadRecord record) async {
    final list = await _read();
    list.removeWhere((r) => r.key == record.key);
    await _store.setSetting(_kKey, encodeDownloads(list));
    try {
      final f = File(record.path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // A missing file is fine — the record is already gone.
    }
  }

  Future<List<DownloadRecord>> _read() async {
    try {
      return decodeDownloads(await _store.getSetting(_kKey)).toList();
    } catch (_) {
      return <DownloadRecord>[];
    }
  }
}
