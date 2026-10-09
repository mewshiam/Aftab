/// User-facing app settings (theme, language, TV mode, auto-resume),
/// persisted through the core store's settings map.

library aftab_app_settings;

import 'package:flutter/material.dart';

import 'sources.dart';

/// Which language the UI uses.
enum AppLocale { fa, en }

/// The app's presentation preferences.
class SettingsController extends ChangeNotifier {
  SettingsController({required StoreSource store}) : _store = store;

  final StoreSource _store;

  static const _kThemeMode = 'ui.theme_mode';
  static const _kDynamic = 'ui.dynamic_color';
  static const _kLocale = 'ui.locale';
  static const _kTvMode = 'tv_mode';
  static const _kAutoResume = 'playback.auto_resume';

  ThemeMode _themeMode = ThemeMode.dark;
  bool _useDynamicColor = false;
  AppLocale _locale = AppLocale.fa;
  bool _tvMode = false;
  bool _autoResume = true;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => _useDynamicColor;
  AppLocale get locale => _locale;
  bool get tvMode => _tvMode;
  bool get autoResume => _autoResume;
  bool get loaded => _loaded;

  /// Locale as a [Locale] object for [MaterialApp].
  Locale get materialLocale =>
      _locale == AppLocale.fa ? const Locale('fa') : const Locale('en');

  /// Reads persisted values; falls back to defaults when unset.
  Future<void> load() async {
    try {
      final theme = await _store.getSetting(_kThemeMode);
      final dynamic = await _store.getSetting(_kDynamic);
      final locale = await _store.getSetting(_kLocale);
      final tv = await _store.getSetting(_kTvMode);
      final resume = await _store.getSetting(_kAutoResume);
      _themeMode = switch (theme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
      _useDynamicColor = dynamic == '1';
      _locale = locale == 'en' ? AppLocale.en : AppLocale.fa;
      _tvMode = tv == '1';
      _autoResume = resume != '0';
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Best-effort: defaults are already in place.
      _loaded = true;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _persist(_kThemeMode, mode.name);
  }

  Future<void> setUseDynamicColor(bool value) async {
    if (_useDynamicColor == value) return;
    _useDynamicColor = value;
    notifyListeners();
    await _persist(_kDynamic, value ? '1' : '0');
  }

  Future<void> setLocale(AppLocale value) async {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
    await _persist(_kLocale, value.name);
  }

  /// Changing this hot-swaps the phone/TV shell — no restart needed.
  Future<void> setTvMode(bool value) async {
    if (_tvMode == value) return;
    _tvMode = value;
    notifyListeners();
    await _persist(_kTvMode, value ? '1' : '0');
  }

  Future<void> setAutoResume(bool value) async {
    if (_autoResume == value) return;
    _autoResume = value;
    notifyListeners();
    await _persist(_kAutoResume, value ? '1' : '0');
  }

  Future<void> _persist(String key, String value) async {
    try {
      await _store.setSetting(key, value);
    } catch (_) {
      // Settings are best-effort; the in-memory value still applies.
    }
  }
}
