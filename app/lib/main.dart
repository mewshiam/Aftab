/// آفتاب مدیا — application entry point.
///
/// Persian-first: the default locale is `fa` (RTL), with `en` one tap
/// away in Settings. libmpv is initialized before any player exists, the
/// Vazirmatn OFL license is registered, and persisted settings decide
/// theme / language / TV mode before the first frame.

library aftab_media_app;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show DeviceOrientation, rootBundle, SystemChrome;
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/store.dart';
import 'data/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // libmpv backend init — required before any Player is created.
  MediaKit.ensureInitialized();
  // Persian-first: keep all three orientations available; the player
  // locks to landscape itself when entering fullscreen.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  unawaited(_registerFontLicense());
  final controller = SettingsController(store: AftabStore.instance);
  await controller.load();
  runApp(AftabApp(controller: controller));
}

/// Registers the Vazirmatn OFL so it appears in the About → Licenses
/// page alongside the automatically-collected package licenses.
Future<void> _registerFontLicense() async {
  try {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(<String>['Vazirmatn'], ofl);
    });
  } catch (_) {
    // The license page still works without the font license text.
  }
}
