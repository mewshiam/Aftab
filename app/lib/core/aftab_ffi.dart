/// Dart bindings for the Aftab core C-ABI (`core/include/aftab.h`).
///
/// Rules of the boundary, mirrored from the header:
///
/// * Strings returned from the core are heap allocations freed with
///   `aftab_free_string` — wrapped here in `_takeString`, which always
///   frees. Callers get plain Dart `String`s.
/// * Failures surface as [`AftabException`] carrying the stable code —
///   never as a bare NULL dereference.
/// * The library is opened per-isolate; all catalog/store calls in this
///   app run inside `Isolate.run` (see `catalog.dart` / `store.dart`),
///   so the UI never blocks on the network.
///
/// The C symbols use snake_case; the analyzer rule is silenced for this
/// file's `analysis_options.yaml`.
library aftab_ffi;

// Raw C bindings intentionally expose C-style function-typedef fields on
// the public AftabRaw surface; the private-type-in-public-API lint does
// not apply to that design.
// ignore_for_file: library_private_types_in_public_api

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ─── Stable error codes (mirror of core/src/error.rs) ──────────────────────

const int aftabOk = 0;
const int aftabNetwork = 1;
const int aftabBadResponse = 2;
const int aftabParse = 3;
const int aftabBadUrl = 4;
const int aftabUnsafeUrl = 5;
const int aftabUnsupportedScheme = 6;
const int aftabIo = 7;
const int aftabInvalidArgument = 8;
const int aftabStorage = 9;
const int aftabNotFound = 10;
const int aftabOutOfMemory = 11;
const int aftabUnknown = 99;

/// An error crossing the FFI boundary, with its stable code.
class AftabException implements Exception {
  const AftabException(this.code, this.message);

  final int code;
  final String message;

  bool get isNetwork =>
      code == aftabNetwork ||
      code == aftabBadResponse ||
      code == aftabBadUrl;

  @override
  String toString() => 'AftabException($code): $message';
}

// ─── Library loading ────────────────────────────────────────────────────────

DynamicLibrary _openCore() {
  if (Platform.isAndroid) return DynamicLibrary.open('libaftab.so');
  if (Platform.isWindows) return DynamicLibrary.open('aftab.dll');
  if (Platform.isLinux) return DynamicLibrary.open('libaftab.so');
  if (Platform.isMacOS) return DynamicLibrary.open('libaftab.dylib');
  throw UnsupportedError('Aftab core is not available on this platform');
}

// ─── Raw symbol bindings ────────────────────────────────────────────────────

typedef _VersionC = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

typedef _LastErrorCodeC = Int32 Function();
typedef _LastErrorCodeDart = int Function();

typedef _LastErrorMessageC = Pointer<Utf8> Function();
typedef _LastErrorMessageDart = Pointer<Utf8> Function();

typedef _FreeStringC = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

typedef _NormalizeC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _NormalizeDart = Pointer<Utf8> Function(Pointer<Utf8>);

typedef _PersianEqualsC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _PersianEqualsDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _SearchScoreC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _SearchScoreDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _UrlIsSafeC = Int32 Function(Pointer<Utf8>);
typedef _UrlIsSafeDart = int Function(Pointer<Utf8>);

typedef _ProviderNewC = Pointer<Void> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _ProviderNewDart = Pointer<Void> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef _ProviderDefaultC = Pointer<Void> Function();
typedef _ProviderDefaultDart = Pointer<Void> Function();

typedef _ProviderFreeC = Void Function(Pointer<Void>);
typedef _ProviderFreeDart = void Function(Pointer<Void>);

typedef _ProviderCallC = Pointer<Utf8> Function(
    Pointer<Void>, Int64, Int32, Uint32);
typedef _ProviderCallDart = Pointer<Utf8> Function(
    Pointer<Void>, int, int, int);

typedef _ProviderStrCallC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _ProviderStrCallDart = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef _ProviderHealthC = Pointer<Utf8> Function(Pointer<Void>);
typedef _ProviderHealthDart = Pointer<Utf8> Function(Pointer<Void>);

typedef _ProviderSeasonsC = Pointer<Utf8> Function(Pointer<Void>, Int64);
typedef _ProviderSeasonsDart = Pointer<Utf8> Function(Pointer<Void>, int);

typedef _StoreOpenC = Pointer<Void> Function(Pointer<Utf8>);
typedef _StoreOpenDart = Pointer<Void> Function(Pointer<Utf8>);

typedef _StoreFreeC = Void Function(Pointer<Void>);
typedef _StoreFreeDart = void Function(Pointer<Void>);

typedef _StoreFavoritesC = Pointer<Utf8> Function(Pointer<Void>);
typedef _StoreFavoritesDart = Pointer<Utf8> Function(Pointer<Void>);

typedef _StoreAddFavC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _StoreAddFavDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _StoreRemoveFavC = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int64);
typedef _StoreRemoveFavDart = int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _StoreIsFavC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int64);
typedef _StoreIsFavDart = int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _StoreSetProgressC = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int64, Double, Double);
typedef _StoreSetProgressDart = int Function(
    Pointer<Void>, Pointer<Utf8>, int, double, double);

typedef _StoreProgressC = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Int64);
typedef _StoreProgressDart = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, int);

typedef _StoreClearProgressC = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int64);
typedef _StoreClearProgressDart = int Function(
    Pointer<Void>, Pointer<Utf8>, int);

typedef _StoreSetSettingC = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _StoreSetSettingDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

typedef _StoreGetSettingC = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef _StoreGetSettingDart = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

/// Lazily-bound raw symbols. One instance per isolate.
class AftabRaw {
  AftabRaw._() : _lib = _openCore() {
    aftab_version = _lib
        .lookupFunction<_VersionC, _VersionDart>('aftab_version');
    aftab_last_error_code =
        _lib.lookupFunction<_LastErrorCodeC, _LastErrorCodeDart>(
            'aftab_last_error_code');
    aftab_last_error_message =
        _lib.lookupFunction<_LastErrorMessageC, _LastErrorMessageDart>(
            'aftab_last_error_message');
    aftab_free_string =
        _lib.lookupFunction<_FreeStringC, _FreeStringDart>('aftab_free_string');
    aftab_normalize_persian =
        _lib.lookupFunction<_NormalizeC, _NormalizeDart>('aftab_normalize_persian');
    aftab_compact_key =
        _lib.lookupFunction<_NormalizeC, _NormalizeDart>('aftab_compact_key');
    aftab_persian_equals =
        _lib.lookupFunction<_PersianEqualsC, _PersianEqualsDart>('aftab_persian_equals');
    aftab_search_score =
        _lib.lookupFunction<_SearchScoreC, _SearchScoreDart>('aftab_search_score');
    aftab_url_is_safe =
        _lib.lookupFunction<_UrlIsSafeC, _UrlIsSafeDart>('aftab_url_is_safe');
    aftab_provider_default =
        _lib.lookupFunction<_ProviderDefaultC, _ProviderDefaultDart>('aftab_provider_default');
    aftab_provider_new =
        _lib.lookupFunction<_ProviderNewC, _ProviderNewDart>('aftab_provider_new');
    aftab_provider_free =
        _lib.lookupFunction<_ProviderFreeC, _ProviderFreeDart>('aftab_provider_free');
    aftab_provider_movies =
        _lib.lookupFunction<_ProviderCallC, _ProviderCallDart>('aftab_provider_movies');
    aftab_provider_series =
        _lib.lookupFunction<_ProviderCallC, _ProviderCallDart>('aftab_provider_series');
    aftab_provider_country_posters = _lib.lookupFunction<_ProviderCallC,
        _ProviderCallDart>('aftab_provider_country_posters');
    aftab_provider_search = _lib.lookupFunction<_ProviderStrCallC,
        _ProviderStrCallDart>('aftab_provider_search');
    aftab_provider_genres =
        _lib.lookupFunction<_ProviderHealthC, _ProviderHealthDart>('aftab_provider_genres');
    aftab_provider_countries = _lib.lookupFunction<_ProviderHealthC,
        _ProviderHealthDart>('aftab_provider_countries');
    aftab_provider_seasons = _lib
        .lookupFunction<_ProviderSeasonsC, _ProviderSeasonsDart>('aftab_provider_seasons');
    aftab_provider_health =
        _lib.lookupFunction<_ProviderHealthC, _ProviderHealthDart>('aftab_provider_health');
    aftab_store_open =
        _lib.lookupFunction<_StoreOpenC, _StoreOpenDart>('aftab_store_open');
    aftab_store_free =
        _lib.lookupFunction<_StoreFreeC, _StoreFreeDart>('aftab_store_free');
    aftab_store_favorites_json = _lib.lookupFunction<_StoreFavoritesC,
        _StoreFavoritesDart>('aftab_store_favorites_json');
    aftab_store_add_favorite = _lib.lookupFunction<_StoreAddFavC, _StoreAddFavDart>(
        'aftab_store_add_favorite');
    aftab_store_remove_favorite = _lib.lookupFunction<_StoreRemoveFavC,
        _StoreRemoveFavDart>('aftab_store_remove_favorite');
    aftab_store_is_favorite = _lib.lookupFunction<_StoreIsFavC, _StoreIsFavDart>(
        'aftab_store_is_favorite');
    aftab_store_set_progress = _lib.lookupFunction<_StoreSetProgressC,
        _StoreSetProgressDart>('aftab_store_set_progress');
    aftab_store_progress_json = _lib.lookupFunction<_StoreProgressC,
        _StoreProgressDart>('aftab_store_progress_json');
    aftab_store_clear_progress = _lib.lookupFunction<_StoreClearProgressC,
        _StoreClearProgressDart>('aftab_store_clear_progress');
    aftab_store_set_setting = _lib.lookupFunction<_StoreSetSettingC,
        _StoreSetSettingDart>('aftab_store_set_setting');
    aftab_store_get_setting = _lib.lookupFunction<_StoreGetSettingC,
        _StoreGetSettingDart>('aftab_store_get_setting');
  }

  final DynamicLibrary _lib;

  static final AftabRaw instance = AftabRaw._();

  late final _VersionDart aftab_version;
  late final _LastErrorCodeDart aftab_last_error_code;
  late final _LastErrorMessageDart aftab_last_error_message;
  late final _FreeStringDart aftab_free_string;
  late final _NormalizeDart aftab_normalize_persian;
  late final _NormalizeDart aftab_compact_key;
  late final _PersianEqualsDart aftab_persian_equals;
  late final _SearchScoreDart aftab_search_score;
  late final _UrlIsSafeDart aftab_url_is_safe;
  late final _ProviderDefaultDart aftab_provider_default;
  late final _ProviderNewDart aftab_provider_new;
  late final _ProviderFreeDart aftab_provider_free;
  late final _ProviderCallDart aftab_provider_movies;
  late final _ProviderCallDart aftab_provider_series;
  late final _ProviderCallDart aftab_provider_country_posters;
  late final _ProviderStrCallDart aftab_provider_search;
  late final _ProviderHealthDart aftab_provider_genres;
  late final _ProviderHealthDart aftab_provider_countries;
  late final _ProviderSeasonsDart aftab_provider_seasons;
  late final _ProviderHealthDart aftab_provider_health;
  late final _StoreOpenDart aftab_store_open;
  late final _StoreFreeDart aftab_store_free;
  late final _StoreFavoritesDart aftab_store_favorites_json;
  late final _StoreAddFavDart aftab_store_add_favorite;
  late final _StoreRemoveFavDart aftab_store_remove_favorite;
  late final _StoreIsFavDart aftab_store_is_favorite;
  late final _StoreSetProgressDart aftab_store_set_progress;
  late final _StoreProgressDart aftab_store_progress_json;
  late final _StoreClearProgressDart aftab_store_clear_progress;
  late final _StoreSetSettingDart aftab_store_set_setting;
  late final _StoreGetSettingDart aftab_store_get_setting;
}

// ─── Typed facade ───────────────────────────────────────────────────────────

/// High-level, string-safe access to the core.
class AftabFfi {
  AftabFfi._();

  static final AftabFfi instance = AftabFfi._();

  final AftabRaw _r = AftabRaw.instance;

  /// Library version, e.g. `0.1.0`.
  ///
  /// The core returns static storage — borrowed, never freed.
  String version() => _borrowString(_r.aftab_version());

  String? _lastMessage() {
    final p = _r.aftab_last_error_message();
    if (p == nullptr) return null;
    return _borrowString(p);
  }

  AftabException _lastError() {
    final code = _r.aftab_last_error_code();
    final msg = _lastMessage() ?? 'unknown failure';
    return AftabException(code, msg);
  }

  // String helpers ─────────────────────────────────────────────────────────

  String _borrowString(Pointer<Utf8> p) => p.toDartString();

  String _takeString(Pointer<Utf8> p) {
    try {
      return p.toDartString();
    } finally {
      _r.aftab_free_string(p);
    }
  }

  // Text utilities ─────────────────────────────────────────────────────────

  /// Canonical Persian normalization (display/storage form).
  String normalizePersian(String input) {
    final c = input.toNativeUtf8();
    try {
      final out = _r.aftab_normalize_persian(c);
      if (out == nullptr) throw _lastError();
      return _takeString(out);
    } finally {
      calloc.free(c);
    }
  }

  /// Compact matching key.
  String compactKey(String input) {
    final c = input.toNativeUtf8();
    try {
      final out = _r.aftab_compact_key(c);
      if (out == nullptr) throw _lastError();
      return _takeString(out);
    } finally {
      calloc.free(c);
    }
  }

  /// Persian-aware equality.
  bool persianEquals(String a, String b) {
    final ca = a.toNativeUtf8();
    final cb = b.toNativeUtf8();
    try {
      return _r.aftab_persian_equals(ca, cb) == 1;
    } finally {
      calloc.free(ca);
      calloc.free(cb);
    }
  }

  /// Search score (>= 25 matched), -1 no match, -2 bad input.
  int searchScore(String query, String candidate) {
    final cq = query.toNativeUtf8();
    final cc = candidate.toNativeUtf8();
    try {
      return _r.aftab_search_score(cq, cc);
    } finally {
      calloc.free(cq);
      calloc.free(cc);
    }
  }

  /// Strict media-URL safety check (SSRF guard). Returns null when safe,
  /// the failure description when not.
  String? urlSafetyProblem(String url) {
    final c = url.toNativeUtf8();
    try {
      if (_r.aftab_url_is_safe(c) == 1) return null;
      return _lastMessage() ?? 'URL rejected';
    } finally {
      calloc.free(c);
    }
  }

  // Provider ───────────────────────────────────────────────────────────────

  /// Runs `body` with a freshly created default provider handle, freeing it
  /// afterwards. Provider handles are cheap; creating one per call keeps
  /// every call self-contained across isolates.
  T withDefaultProvider<T>(T Function(Pointer<Void> provider) body) {
    final p = _r.aftab_provider_default();
    if (p == nullptr) throw _lastError();
    try {
      return body(p);
    } finally {
      _r.aftab_provider_free(p);
    }
  }

  /// Movies page as raw JSON (see `catalog.dart` for typed parsing).
  String moviesJson(Pointer<Void> provider, int genre, int filter, int page) {
    final out = _r.aftab_provider_movies(provider, genre, filter, page);
    if (out == nullptr) throw _lastError();
    return _takeString(out);
  }

  /// Series page as raw JSON.
  String seriesJson(Pointer<Void> provider, int genre, int filter, int page) {
    final out = _r.aftab_provider_series(provider, genre, filter, page);
    if (out == nullptr) throw _lastError();
    return _takeString(out);
  }

  /// Search results as raw JSON.
  String searchJson(Pointer<Void> provider, String query) {
    final cq = query.toNativeUtf8();
    try {
      final out = _r.aftab_provider_search(provider, cq);
      if (out == nullptr) throw _lastError();
      return _takeString(out);
    } finally {
      calloc.free(cq);
    }
  }

  /// Genres as raw JSON.
  String genresJson(Pointer<Void> provider) {
    final out = _r.aftab_provider_genres(provider);
    if (out == nullptr) throw _lastError();
    return _takeString(out);
  }

  /// Seasons of one series as raw JSON.
  String seasonsJson(Pointer<Void> provider, int seriesId) {
    final out = _r.aftab_provider_seasons(provider, seriesId);
    if (out == nullptr) throw _lastError();
    return _takeString(out);
  }

  /// Server health probe as raw JSON.
  String healthJson(Pointer<Void> provider) {
    final out = _r.aftab_provider_health(provider);
    if (out == nullptr) throw _lastError();
    return _takeString(out);
  }

  // Store ──────────────────────────────────────────────────────────────────

  /// Runs `body` with a store handle opened at `path`, freeing it after.
  T withStore<T>(String path, T Function(Pointer<Void> store) body) {
    final c = path.toNativeUtf8();
    final s = _r.aftab_store_open(c);
    calloc.free(c);
    if (s == nullptr) throw _lastError();
    try {
      return body(s);
    } finally {
      _r.aftab_store_free(s);
    }
  }

  /// Favorites JSON, newest first.
  String favoritesJson(Pointer<Void> store) {
    final out = _r.aftab_store_favorites_json(store);
    if (out == nullptr) throw _lastError();
    return _takeString(out);
  }

  /// Add a favorite from a JSON object; returns true on success.
  bool addFavorite(Pointer<Void> store, String favoriteJson) {
    final c = favoriteJson.toNativeUtf8();
    try {
      return _r.aftab_store_add_favorite(store, c) == 1;
    } finally {
      calloc.free(c);
    }
  }

  /// Remove a favorite; returns true if it existed.
  bool removeFavorite(Pointer<Void> store, String kind, int id) {
    final ck = kind.toNativeUtf8();
    try {
      return _r.aftab_store_remove_favorite(store, ck, id) == 1;
    } finally {
      calloc.free(ck);
    }
  }

  /// Is this content favorited?
  bool isFavorite(Pointer<Void> store, String kind, int id) {
    final ck = kind.toNativeUtf8();
    try {
      return _r.aftab_store_is_favorite(store, ck, id) == 1;
    } finally {
      calloc.free(ck);
    }
  }

  /// Record playback progress; returns true on success.
  bool setProgress(
      Pointer<Void> store, String kind, int id, double position, double duration) {
    final ck = kind.toNativeUtf8();
    try {
      return _r.aftab_store_set_progress(store, ck, id, position, duration) == 1;
    } finally {
      calloc.free(ck);
    }
  }

  /// Progress JSON for one item, or null when absent.
  Map<String, dynamic>? progress(Pointer<Void> store, String kind, int id) {
    final ck = kind.toNativeUtf8();
    try {
      final out = _r.aftab_store_progress_json(store, ck, id);
      if (out == nullptr) throw _lastError();
      final text = _takeString(out);
      if (text == 'null') return null;
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      calloc.free(ck);
    }
  }

  /// Clear progress; returns true if it existed.
  bool clearProgress(Pointer<Void> store, String kind, int id) {
    final ck = kind.toNativeUtf8();
    try {
      return _r.aftab_store_clear_progress(store, ck, id) == 1;
    } finally {
      calloc.free(ck);
    }
  }

  /// Write a setting; returns true on success.
  bool setSetting(Pointer<Void> store, String name, String value) {
    final cn = name.toNativeUtf8();
    final cv = value.toNativeUtf8();
    try {
      return _r.aftab_store_set_setting(store, cn, cv) == 1;
    } finally {
      calloc.free(cn);
      calloc.free(cv);
    }
  }

  /// Read a setting; null when unset.
  String? getSetting(Pointer<Void> store, String name) {
    final cn = name.toNativeUtf8();
    try {
      final out = _r.aftab_store_get_setting(store, cn);
      if (out == nullptr) {
        if (_r.aftab_last_error_code() != aftabOk) throw _lastError();
        return null;
      }
      return _takeString(out);
    } finally {
      calloc.free(cn);
    }
  }
}
