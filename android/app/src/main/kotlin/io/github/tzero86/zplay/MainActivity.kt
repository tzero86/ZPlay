package io.github.tzero86.zplay

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.UiModeManager
import android.content.res.Configuration
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "io.github.tzero86.zplay/power"
    private val DEVICE_CHANNEL = "io.github.tzero86.zplay/device"
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var cloudStreamBridge: CloudStreamNativeBridge? = null
    private var exoPlayerBridge: ExoPlayerBridge? = null
    private var voiceSearchBridge: VoiceSearchBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        cloudStreamBridge = CloudStreamNativeBridge(applicationContext, this).apply {
            register(flutterEngine)
        }

        // The second playback engine. Registered on every platform; the Dart
        // side checks availability and falls back to mpv where it is absent.
        exoPlayerBridge = ExoPlayerBridge(applicationContext).apply { register(flutterEngine) }

        // Voice search. Registered on every platform, like the playback engine;
        // the Dart side asks whether this device has a recognizer and hides the
        // microphone when it does not. The activity is passed because both the
        // recognizer intent and the microphone permission are activity results,
        // and those callbacks land here - see the two forwards below.
        voiceSearchBridge = VoiceSearchBridge(applicationContext, this).apply {
            register(flutterEngine)
        }
        // Television detection.
        //
        // Flutter reports no way to ask this: MediaQueryData.navigationMode
        // reads platformData, which the Android engine never populates (its
        // SettingsChannel sends six keys and none is a navigation mode), so
        // navigationModeOf is permanently traditional and a TV would get the
        // pointer-device chrome. UiModeManager is the platform's own answer.
        //
        // Both checks, not either: a leanback box that also reports a
        // touchscreen is being driven by touch, and leanback without a D-pad
        // would be classified as a TV with no remote to drive it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> {
                        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
                        val type = uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                        val touch = packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
                        result.success(type && !touch)
                    }
                    else -> result.notImplemented()
                }
            }


        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireLocks" -> {
                    try {
                        // 1. High-Performance Low-Latency Wi-Fi Lock
                        if (wifiLock == null) {
                            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                            val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                            } else {
                                WifiManager.WIFI_MODE_FULL_HIGH_PERF
                            }
                            wifiLock = wifiManager?.createWifiLock(lockMode, "zplay:stream_wifi")?.apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (wifiLock?.isHeld == false) {
                            wifiLock?.acquire()
                        }

                        // 2. Partial Wake Lock (prevents CPU sleep during streaming)
                        if (wakeLock == null) {
                            val powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                            wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "zplay:stream_wake")?.apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (wakeLock?.isHeld == false) {
                            wakeLock?.acquire(3 * 60 * 60 * 1000L) // 3 hours timeout safety
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                "releaseLocks" -> {
                    try {
                        if (wifiLock?.isHeld == true) {
                            wifiLock?.release()
                        }
                        if (wakeLock?.isHeld == true) {
                            wakeLock?.release()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Voice search's two activity callbacks.
    //
    // `FlutterActivity` is a plain `android.app.Activity`, so there is no
    // `registerForActivityResult` to register a launcher on; the results arrive
    // at the activity, the same way every channel-based Flutter plugin receives
    // them. Only the bridge's own request codes are claimed - `super` must see
    // everything else, because this app also ships a file picker and a webview
    // that depend on these same callbacks.

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (voiceSearchBridge?.handleActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (voiceSearchBridge?.handlePermissionResult(requestCode, grantResults) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun onDestroy() {
        try {
            cloudStreamBridge?.destroy()
            exoPlayerBridge?.destroy()
            voiceSearchBridge?.destroy()
            if (wifiLock?.isHeld == true) wifiLock?.release()
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}