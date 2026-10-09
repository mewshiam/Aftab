/// A small, dependency-free disk cache for artwork.
///
/// Posters are small but numerous; re-downloading them on every scroll
/// would be both slow and rude to the provider. Files are stored under
/// the app-support directory, keyed by a stable FNV-1a hash of the URL,
/// with a bounded file count and oldest-first eviction. In-memory
/// deduplication and decode caching are handled by Flutter's own
/// [ImageCache] on top of the decoded [Image.file] providers.

library aftab_image_cache;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AftabImageCache {
  AftabImageCache._();

  static final AftabImageCache instance = AftabImageCache._();

  /// Test seam: replaces the network fetch entirely.
  static Future<File?> Function(String url)? debugFetcher;

  static const int _maxFiles = 4096;
  static const int _evictBatch = 512;

  final http.Client _client = http.Client();
  Future<Directory>? _dirFuture;

  /// Returns the cached file for [url], fetching and storing it if
  /// needed; null when the artwork is unavailable.
  Future<File?> load(String url) {
    if (url.isEmpty) return Future<File?>.value(null);
    return _load(url);
  }

  Future<File?> _load(String url) async {
    final dir = await _directory();
    final file = File(p.join(dir.path, _hash(url)));
    if (file.existsSync()) {
      // Fire-and-forget touch so eviction sees recent use.
      unawaited(_touch(file));
      return file;
    }
    try {
      final fetched = debugFetcher?.call(url);
      if (fetched != null) return await fetched;
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      await file.writeAsBytes(response.bodyBytes, flush: true);
      unawaited(_evict(dir));
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _directory() {
    return _dirFuture ??= () async {
      try {
        final base = await getApplicationSupportDirectory();
        final dir = Directory(p.join(base.path, 'image-cache'));
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return dir;
      } catch (_) {
        return Directory.systemTemp;
      }
    }();
  }

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {
      // Touching is best-effort.
    }
  }

  Future<void> _evict(Directory dir) async {
    try {
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File) files.add(entity);
      }
      if (files.length <= _maxFiles) return;
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in files.take(files.length - _maxFiles + _evictBatch)) {
        try {
          f.deleteSync();
        } catch (_) {
          // Another isolate may have won the race; fine.
        }
      }
    } catch (_) {
      // Eviction must never break a fetch.
    }
  }

  /// Stable, filesystem-safe key: FNV-1a 64-bit of the URL.
  String _hash(String url) {
    var h = 0xcbf29ce484222325;
    for (final b in url.codeUnits) {
      h ^= b;
      h *= 0x100000001b3;
      h &= 0x7FFFFFFFFFFFFFFF; // keep it positive on web-safe ints.
    }
    return h.toRadixString(16).padLeft(16, '0');
  }
}
