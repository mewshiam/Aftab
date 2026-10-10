/// In-memory fakes for widget tests — no FFI, no network, no isolates.

library aftab_test_fakes;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:aftab_media/core/models.dart';
import 'package:aftab_media/core/store.dart';
import 'package:aftab_media/data/app_settings.dart';
import 'package:aftab_media/data/downloads.dart';
import 'package:aftab_media/data/player_settings.dart';
import 'package:aftab_media/data/sources.dart';
import 'package:aftab_media/data/watch_index.dart';
import 'package:aftab_media/l10n/app_localizations.dart';
import 'package:aftab_media/navigation/app_scope.dart';

class FakeCatalogSource implements CatalogSource {
  FakeCatalogSource({
    List<CatalogItem> movies = const <CatalogItem>[],
    List<CatalogItem> series = const <CatalogItem>[],
    List<Genre> genres = const <Genre>[],
    List<Season> seasons = const <Season>[],
    Map<String, List<CatalogItem>> searchResults =
        const <String, List<CatalogItem>>{},
    List<CatalogItem> resolveResults = const <CatalogItem>[],
  })  : _movies = movies,
        _series = series,
        _genres = genres,
        _seasons = seasons,
        _searchResults = searchResults,
        _resolveResults = resolveResults;

  final List<CatalogItem> _movies;
  final List<CatalogItem> _series;
  final List<Genre> _genres;
  final List<Season> _seasons;
  final Map<String, List<CatalogItem>> _searchResults;
  final List<CatalogItem> _resolveResults;

  int movieCalls = 0;
  int seriesCalls = 0;

  @override
  Future<List<CatalogItem>> movies({
    int genre = 0,
    CatalogSort sort = CatalogSort.newest,
    int page = 0,
  }) async {
    movieCalls += 1;
    return page == 0 ? _movies : const <CatalogItem>[];
  }

  @override
  Future<List<CatalogItem>> series({
    int genre = 0,
    CatalogSort sort = CatalogSort.newest,
    int page = 0,
  }) async {
    seriesCalls += 1;
    return page == 0 ? _series : const <CatalogItem>[];
  }

  @override
  Future<List<CatalogItem>> search(String query) async =>
      _searchResults[query] ?? const <CatalogItem>[];

  @override
  Future<List<Genre>> genres() async => _genres;

  @override
  Future<List<Season>> seasons(int seriesId) async => _seasons;

  @override
  Future<CatalogItem?> resolveItem(CatalogItem partial) async {
    for (final r in _resolveResults) {
      if (r.kind == partial.kind && r.id == partial.id) return r;
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> health() async => <Map<String, dynamic>>[
        <String, dynamic>{'server': 'base.example', 'ok': true},
        <String, dynamic>{'server': 'helper.example', 'ok': false},
      ];

  @override
  Future<List<CatalogItem>> rank(
      String query, List<CatalogItem> items) async {
    // Identity ranking keeps the fakes predictable.
    return items;
  }
}

class FakeStoreSource implements StoreSource {
  final Map<String, Favorite> _favorites = <String, Favorite>{};
  final Map<String, WatchProgress> _progress = <String, WatchProgress>{};
  final Map<String, String> _settings = <String, String>{};

  @override
  Future<List<Favorite>> favorites() async {
    final list = _favorites.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  @override
  Future<bool> addFavorite(CatalogItem item) async {
    _favorites['${item.kind}:${item.id}'] = Favorite(
      id: item.id,
      kind: item.kind,
      title: item.title,
      image: item.image,
      year: item.year,
      addedAt: 1000,
    );
    return true;
  }

  @override
  Future<bool> removeFavorite(CatalogItem item) async =>
      _favorites.remove('${item.kind}:${item.id}') != null;

  @override
  Future<bool> isFavorite(CatalogItem item) async =>
      _favorites.containsKey('${item.kind}:${item.id}');

  @override
  Future<bool> setProgress(
      CatalogItem item, double positionSeconds, double durationSeconds) async {
    _progress['${item.kind}:${item.id}'] = WatchProgress(
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      updatedAt: 2000,
    );
    return true;
  }

  @override
  Future<WatchProgress?> progress(CatalogItem item) async =>
      _progress['${item.kind}:${item.id}'];

  @override
  Future<List<WatchEntry>> progressAll() async => <WatchEntry>[
        for (final e in _progress.entries)
          WatchEntry(
            kind: e.key.split(':').first,
            id: int.parse(e.key.split(':').last),
            progress: e.value,
          ),
      ];

  @override
  Future<bool> clearProgress(CatalogItem item) async =>
      _progress.remove('${item.kind}:${item.id}') != null;

  @override
  Future<bool> setSetting(String name, String value) async {
    _settings[name] = value;
    return true;
  }

  @override
  Future<String?> getSetting(String name) async => _settings[name];
}

/// Builds a fully wired fake app for pumping screens.
Widget testApp({
  required Widget child,
  FakeCatalogSource? catalog,
  FakeStoreSource? store,
  SettingsController? settings,
  PlayerSettingsController? playerSettings,
  WatchIndex? watchIndex,
  DownloadManager? downloads,
}) {
  final fakeStore = store ?? FakeStoreSource();
  final controller = settings ?? SettingsController(store: fakeStore);
  final playerPrefs =
      playerSettings ?? PlayerSettingsController(store: fakeStore);
  return MaterialApp(
    locale: controller.materialLocale,
    supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: AppScope(
      catalog: catalog ?? FakeCatalogSource(),
      store: fakeStore,
      settings: controller,
      playerSettings: playerPrefs,
      watchIndex: watchIndex ?? WatchIndex(store: fakeStore),
      downloads: downloads ?? DownloadManager(store: fakeStore),
      child: child,
    ),
  );
}

/// Small helper: a movie or series with sensible defaults.
CatalogItem fakeItem({
  int id = 1,
  String kind = 'movie',
  String title = 'گوشه',
  String image = '',
  double imdb = 7.4,
  int year = 2023,
}) {
  return CatalogItem(
    id: id,
    kind: kind,
    title: title,
    description: 'توضیح آزمایشی',
    year: year,
    imdb: imdb,
    rating: 0,
    duration: '1h 52m',
    image: image,
    cover: '',
    genres: <Genre>[const Genre(id: 1, title: 'اکشن')],
    sources: <Source>[
      const Source(id: 9, quality: '1080p', type: 'mp4', url: 'https://cdn.example/v.mp4'),
    ],
    countries: const <Country>[],
  );
}
