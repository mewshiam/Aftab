/// The app root: localization, theming (brand or Material You), the
/// production dependency scope, and the TV/phone shell gate.

library aftab_app;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/app_settings.dart';
import 'design/color_schemes.dart';
import 'design/theme.dart';
import 'l10n/app_localizations.dart';
import 'navigation/app_scope.dart';
import 'platform/form_factor.dart';
import 'tv/tv_shell.dart';
import 'core/catalog.dart';
import 'core/store.dart';
import 'data/downloads.dart';
import 'data/watch_index.dart';
import 'navigation/app_shell.dart';

class AftabApp extends StatelessWidget {
  const AftabApp({super.key, required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      catalog: CatalogClient.instance,
      store: AftabStore.instance,
      settings: controller,
      watchIndex: WatchIndex(store: AftabStore.instance),
      downloads: DownloadManager(store: AftabStore.instance),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => controller.useDynamicColor
            ? withDynamicColor(
                builder: (light, dark) => _materialApp(context, light, dark),
              )
            : _materialApp(
                context, aftabColorSchemeLight, aftabColorSchemeDark),
      ),
    );
  }

  Widget _materialApp(
      BuildContext context, ColorScheme light, ColorScheme dark) {
    return MaterialApp(
      onGenerateTitle: (context) => S.of(context).appName,
      debugShowCheckedModeBanner: false,
      themeMode: controller.themeMode,
      theme: aftabTheme(Brightness.light).copyWith(colorScheme: light),
      darkTheme: aftabTheme(Brightness.dark).copyWith(colorScheme: dark),
      locale: controller.materialLocale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RootGate(controller: controller),
    );
  }
}

/// Chooses the TV or the adaptive shell.
///
/// Priority: the user's TV-mode override → the platform channel answer
/// (real Android TV) → a conservative size heuristic. Phone / tablet /
/// desktop distinctions are refined live inside [AppShell] by width.
class RootGate extends StatefulWidget {
  const RootGate({super.key, required this.controller});

  final SettingsController controller;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  FormFactor? _base;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
    final factor =
        await FormFactorResolver(tvOverride: false).resolve(shortest);
    if (mounted) setState(() => _base = factor);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_base == null) {
      return Scaffold(
        backgroundColor: scheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.wb_sunny, size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text(S.of(context).appName,
                  style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final factor = widget.controller.tvMode ? FormFactor.tv : _base!;
        return factor == FormFactor.tv
            ? const TvShell()
            : AppShell(formFactor: factor);
      },
    );
  }
}
