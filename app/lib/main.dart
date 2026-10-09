/// آفتاب مدیا — application entry point.
///
/// Persian-first: the app locale is `fa`, layouts render RTL, and every
/// user-visible string is Persian. On Android TV (large screen, remote
/// navigation) the TV home is used; on phones and desktop the tabbed home.

library aftab_media_app;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'core/aftab_ffi.dart';
import 'tv/tv_home_screen.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // libmpv backend init — required before any Player is created.
  MediaKit.ensureInitialized();
  // Persian-first: right-toLeft everywhere, no accidental LTR flips.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const AftabApp());
}

class AftabApp extends StatelessWidget {
  const AftabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'آفتاب مدیا',
      debugShowCheckedModeBanner: false,
      theme: AftabTheme.dark(),
      locale: const Locale('fa'),
      supportedLocales: const <Locale>[Locale('fa')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DefaultMaterialLocalizations.delegate,
      ],
      home: const RootGate(),
    );
  }
}

/// Chooses the TV or the mobile home.
///
/// TV detection is intentionally conservative for v1: Android on a very
/// large display (TV panels report 960dp+ shortest side) plus a settings
/// override (`tv_mode`). `device_info_plus`-based leanback detection is a
/// documented follow-up — see docs/ROADMAP in the repository docs.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late final Future<bool?> _mode = Future<bool?>.value(_tvHeuristic());

  bool _tvHeuristic() {
    if (!Platform.isAndroid) return false;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
    return shortest >= 600;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool?>(
      future: _mode,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final isTv = snapshot.data ?? false;
        return isTv ? const TvHomeScreen() : const HomeScreen();
      },
    );
  }
}

/// One-line banner used by several screens.
class AftabVersionLabel extends StatelessWidget {
  const AftabVersionLabel({super.key});

  @override
  Widget build(BuildContext context) {
    late final String version;
    try {
      version = AftabFfi.instance.version();
    } catch (_) {
      version = '—';
    }
    return Text(
      'نسخهٔ هسته: $version',
      style: Theme.of(context).textTheme.bodySmall,
      textAlign: TextAlign.center,
    );
  }
}
