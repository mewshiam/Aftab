/// The catalog client: typed access to the provider FFI, always off the UI
/// thread.
///
/// Every call runs inside `Isolate.run`, where a fresh provider handle is
/// created and freed — the C header's "cheap, self-contained" contract makes
/// this both safe and simple. The UI gets futures and typed results; the
/// blocking Rust calls never touch the platform thread.

library aftab_catalog;

import 'dart:convert';
import 'dart:isolate';

import '../data/sources.dart';
import 'aftab_ffi.dart';
import 'models.dart';

class CatalogClient implements CatalogSource {
  const CatalogClient._();

  static const CatalogClient instance = CatalogClient._();

  List<T> _parseArray<T>(
      String json, T Function(Map<String, dynamic>) fromJson) {
    final raw = jsonDecode(json);
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }

  /// One page of movies.
  @override
  Future<List<CatalogItem>> movies({
    int genre = 0,
    CatalogSort sort = CatalogSort.newest,
    int page = 0,
  }) {
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withDefaultProvider<List<CatalogItem>>((provider) {
        final raw = ffi.moviesJson(provider, genre, sort.wireValue, page);
        return _parseArray(
            raw, (m) => CatalogItem.fromJson(m));
      });
    });
  }

  /// One page of series.
  @override
  Future<List<CatalogItem>> series({
    int genre = 0,
    CatalogSort sort = CatalogSort.newest,
    int page = 0,
  }) {
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withDefaultProvider<List<CatalogItem>>((provider) {
        final raw = ffi.seriesJson(provider, genre, sort.wireValue, page);
        return _parseArray(
            raw, (m) => CatalogItem.fromJson(m));
      });
    });
  }

  /// Full-text search.
  @override
  Future<List<CatalogItem>> search(String query) {
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withDefaultProvider<List<CatalogItem>>((provider) {
        final raw = ffi.searchJson(provider, query);
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) return const <CatalogItem>[];
        final posters = decoded['posters'];
        if (posters is! List) return const <CatalogItem>[];
        return posters
            .whereType<Map<String, dynamic>>()
            .map(CatalogItem.fromJson)
            .toList(growable: false);
      });
    });
  }

  /// All genres, for the Discover filters.
  @override
  Future<List<Genre>> genres() {
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withDefaultProvider<List<Genre>>((provider) {
        final raw = ffi.genresJson(provider);
        return _parseArray(raw, Genre.fromJson);
      });
    });
  }

  /// Resolves a partial item (favorites / continue-watching entries) back
  /// to the full catalog item with sources, via provider search.
  @override
  Future<CatalogItem?> resolveItem(CatalogItem partial) async {
    if (partial.title.isEmpty) return null;
    final results = await search(partial.title);
    for (final r in results) {
      if (r.kind == partial.kind && r.id == partial.id) return r;
    }
    for (final r in results) {
      if (r.kind == partial.kind && r.title == partial.title) return r;
    }
    return null;
  }

  /// Seasons and episodes of one series.
  @override
  Future<List<Season>> seasons(int seriesId) {
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withDefaultProvider<List<Season>>((provider) {
        final raw = ffi.seasonsJson(provider, seriesId);
        return _parseArray(raw, Season.fromJson);
      });
    });
  }

  /// Server health probe (base + helpers), for the settings screen.
  @override
  Future<List<Map<String, dynamic>>> health() {
    return Isolate.run(() {
      final ffi = AftabFfi.instance;
      return ffi.withDefaultProvider<List<Map<String, dynamic>>>((provider) {
        final raw = ffi.healthJson(provider);
        final decoded = jsonDecode(raw);
        if (decoded is! List) return const <Map<String, dynamic>>[];
        return decoded
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      });
    });
  }

  /// Locally rank `items` against `query` with the core's Persian-aware
  /// scoring — used to refine provider search results and to filter
  /// loaded pages instantly while typing.
  @override
  Future<List<CatalogItem>> rank(
      String query, List<CatalogItem> items) {
    return Isolate.run(() {
      if (query.trim().isEmpty) return items;
      final ffi = AftabFfi.instance;
      final scored = <(int, int)>[];
      for (var i = 0; i < items.length; i++) {
        final s = ffi.searchScore(query, items[i].title);
        if (s >= 0) scored.add((i, s));
      }
      scored.sort((a, b) => b.$2.compareTo(a.$2));
      return [for (final (i, _) in scored) items[i]];
    });
  }
}
