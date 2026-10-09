package ir.aftab.media

import io.flutter.embedding.android.FlutterActivity

/**
 * The single activity for phones, tablets, and Android TV.
 *
 * TV-specific behavior (focus-first UI) is decided in Dart via the TV gate
 * in `lib/main.dart`; the manifest exposes both LAUNCHER and
 * LEANBACK_LAUNCHER intents, so one APK serves both form factors.
 */
class MainActivity : FlutterActivity()
