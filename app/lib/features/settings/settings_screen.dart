/// Settings: categorized sections (appearance, playback, servers, about)
/// with native-feeling controls and explanatory descriptions.

library aftab_settings_screen;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/aftab_ffi.dart';
import '../../data/app_settings.dart';
import '../../data/sources.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../navigation/app_scope.dart';

/// Keep in sync with `pubspec.yaml` (displayed verbatim in About).
const String kAppVersion = '0.2.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  CatalogSource? _catalog;
  List<Map<String, dynamic>>? _health;
  String? _healthError;
  String? _coreVersion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog ??= AppScope.catalogOf(context);
    if (_health == null && _healthError == null && _coreVersion == null) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      _coreVersion = AftabFfi.instance.version();
    } catch (_) {
      _coreVersion = '—';
    }
    try {
      final health = await _catalog!.health();
      if (!mounted) return;
      setState(() {
        _health = health;
        _healthError = null;
      });
    } on AftabException catch (e) {
      if (mounted) setState(() => _healthError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = AppScope.settingsOf(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.navSettings)),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: AftabSpacing.sm),
          children: <Widget>[
            _section(context, s.settingsAppearance, <Widget>[
              _themeModeTile(context, s, settings),
              SwitchListTile(
                secondary: const Icon(Icons.palette_outlined),
                title: Text(s.dynamicColors),
                subtitle: Text(s.dynamicColorsHint),
                value: settings.useDynamicColor,
                onChanged: (v) => unawaited(settings.setUseDynamicColor(v)),
              ),
              _languageTile(context, s, settings),
            ]),
            _section(context, s.settingsPlayback, <Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.history),
                title: Text(s.autoResume),
                subtitle: Text(s.autoResumeHint),
                value: settings.autoResume,
                onChanged: (v) => unawaited(settings.setAutoResume(v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.tv_outlined),
                title: Text(s.tvMode),
                subtitle: Text(s.tvModeHint),
                value: settings.tvMode,
                onChanged: (v) => unawaited(settings.setTvMode(v)),
              ),
            ]),
            _section(context, s.settingsServers, <Widget>[_healthBody(s)]),
            _section(context, s.settingsAbout, <Widget>[
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(s.appVersion(kAppVersion)),
                dense: true,
              ),
              ListTile(
                leading: const Icon(Icons.memory),
                title: Text(s.coreVersion(_coreVersion ?? '—')),
                dense: true,
              ),
              ListTile(
                leading: const Icon(Icons.copyright),
                title: Text(s.licenseTitle),
                subtitle: const Text('GPL-3.0-or-later'),
                dense: true,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: s.appName,
                  applicationVersion: kAppVersion,
                  applicationIcon: const Padding(
                    padding: EdgeInsets.all(AftabSpacing.md),
                    child: Icon(Icons.wb_sunny_outlined, size: 40),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AftabSpacing.xl,
            top: AftabSpacing.md,
            bottom: AftabSpacing.xs,
          ),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _themeModeTile(BuildContext context, S s, SettingsController settings) {
    return ListTile(
      leading: const Icon(Icons.dark_mode_outlined),
      title: Text(s.themeMode),
      subtitle: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: <ButtonSegment<ThemeMode>>[
          ButtonSegment<ThemeMode>(
            value: ThemeMode.system,
            label: Text(s.themeModeSystem),
          ),
          ButtonSegment<ThemeMode>(
            value: ThemeMode.light,
            label: Text(s.themeModeLight),
          ),
          ButtonSegment<ThemeMode>(
            value: ThemeMode.dark,
            label: Text(s.themeModeDark),
          ),
        ],
        selected: <ThemeMode>{settings.themeMode},
        onSelectionChanged: (selection) =>
            unawaited(settings.setThemeMode(selection.first)),
      ),
      isThreeLine: false,
    );
  }

  Widget _languageTile(BuildContext context, S s, SettingsController settings) {
    return ListTile(
      leading: const Icon(Icons.translate),
      title: Text(s.language),
      subtitle: SegmentedButton<AppLocale>(
        showSelectedIcon: false,
        segments: <ButtonSegment<AppLocale>>[
          ButtonSegment<AppLocale>(
            value: AppLocale.fa,
            label: Text(s.languageFa),
          ),
          ButtonSegment<AppLocale>(
            value: AppLocale.en,
            label: Text(s.languageEn),
          ),
        ],
        selected: <AppLocale>{settings.locale},
        onSelectionChanged: (selection) =>
            unawaited(settings.setLocale(selection.first)),
      ),
    );
  }

  Widget _healthBody(S s) {
    if (_healthError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AftabSpacing.xl,
          vertical: AftabSpacing.sm,
        ),
        child: Text(
          '${s.serversCheckFailed}: $_healthError',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (_health == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AftabSpacing.xl,
          vertical: AftabSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AftabSpacing.md),
            Text(s.serversChecking),
          ],
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final server in _health!)
          ListTile(
            dense: true,
            leading: Icon(
              server['ok'] == true
                  ? Icons.check_circle
                  : Icons.cancel_outlined,
              color: server['ok'] == true
                  ? Colors.lightGreen
                  : Theme.of(context).colorScheme.error,
            ),
            title: Text('${server['server']}'),
            subtitle: Text(
                server['ok'] == true ? s.serverReachable : s.serverUnreachable),
          ),
      ],
    );
  }
}
