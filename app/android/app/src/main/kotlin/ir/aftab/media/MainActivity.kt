package ir.aftab.media

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The single activity for phones, tablets, and Android TV.
 *
 * The manifest exposes both LAUNCHER and LEANBACK_LAUNCHER intents, so one
 * APK serves both form factors. This activity answers one platform
 * question over the `aftab/device` method channel: whether the device
 * advertises the leanback feature (a real Android TV), so the Dart layer
 * can pick the 10-foot UI without size heuristics alone.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "aftab/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTvDevice())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * A device is TV-shaped when it advertises leanback and has no
     * touchscreen (large touchscreens report leanback-capable hybrids as
     * leanback + touchscreen; those are better served by the touch UI).
     */
    private fun isTvDevice(): Boolean {
        val pm: PackageManager = packageManager
        val leanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val touchscreen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
        } else {
            true
        }
        return leanback && !touchscreen
    }
}
