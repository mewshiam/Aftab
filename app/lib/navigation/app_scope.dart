/// [AppScope]: the dependency injection point.
///
/// Production wires the real FFI-backed clients; widget tests inject
/// in-memory fakes. Screens never touch the FFI layer directly.

library aftab_app_scope;

import 'package:flutter/widgets.dart';

import '../core/catalog.dart';
import '../core/store.dart';
import '../data/app_settings.dart';
import '../data/downloads.dart';
import '../data/sources.dart';
import '../data/watch_index.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.catalog,
    required this.store,
    required this.settings,
    required this.watchIndex,
    required this.downloads,
    required super.child,
  });

  final CatalogSource catalog;
  final StoreSource store;
  final SettingsController settings;
  final WatchIndex watchIndex;
  final DownloadManager downloads;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  /// Convenience accessors used all over the UI.
  static CatalogSource catalogOf(BuildContext context) =>
      of(context).catalog;
  static StoreSource storeOf(BuildContext context) => of(context).store;
  static SettingsController settingsOf(BuildContext context) =>
      of(context).settings;
  static WatchIndex watchIndexOf(BuildContext context) => of(context).watchIndex;
  static DownloadManager downloadsOf(BuildContext context) =>
      of(context).downloads;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      catalog != oldWidget.catalog ||
      store != oldWidget.store ||
      settings != oldWidget.settings ||
      watchIndex != oldWidget.watchIndex ||
      downloads != oldWidget.downloads;
}

/// The production scope: real FFI-backed implementations.
AppScope buildProductionScope({
  required SettingsController settings,
  required Widget child,
}) {
  return AppScope(
    catalog: CatalogClient.instance,
    store: AftabStore.instance,
    settings: settings,
    watchIndex: WatchIndex(store: AftabStore.instance),
    downloads: DownloadManager(store: AftabStore.instance),
    child: child,
  );
}

