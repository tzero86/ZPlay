# Flutter engine + embedding: reached only through JNI/reflection from the AOT runtime.
-keep class io.flutter.** { *; }

# The engine's deferred-components manager references Play Core classes that only
# exist when an app opts into deferred components. R8 full mode treats the missing
# references as a build failure, so they are suppressed rather than kept.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Plugin method channels are invoked reflectively by name from Dart.
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.common.EventChannel$StreamHandler { *; }
-keep class * implements io.flutter.plugin.common.MessageCodec { *; }

# media_kit / video surface providers are instantiated by class name.
-keep class com.alexmercerind.** { *; }

# Kotlin metadata + coroutines are used reflectively by several plugins.
-dontwarn kotlin.**

# Media3/ExoPlayer is instantiated through ExoPlayer.Builder and reached by
# name from ExoPlayerBridge, so R8 sees no static entry point and strips the
# whole library. Without these rules the release APK builds cleanly, launches,
# and has no ExoPlayer in it at all - the engine then fails at playback time
# with a NoClassDefFoundError and no test catches it.
#
# Media3 does not ship consumer ProGuard rules for the core player, so the
# classes are kept by name. It is more than the entry point: extractors and
# default renderers are resolved reflectively by MIME type.
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-dontwarn kotlinx.**
-keepclassmembers class kotlin.Metadata { public <methods>; }

# sqflite / path_provider write into app storage; nothing reflective, but the
# plugin classes are looked up by the generated registrant's name.
-keep class com.tekartik.sqflite.** { *; }