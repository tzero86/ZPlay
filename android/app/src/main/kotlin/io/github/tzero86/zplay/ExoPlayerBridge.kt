package io.github.tzero86.zplay

import android.content.Context
import android.net.Uri
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * ExoPlayer/Media3 as a second playback engine.
 *
 * ZPlay's first engine is mpv, and mpv is why 4K stuttered on small Android TVs.
 * The libmpv we bundle only ships `mediacodec-copy` hardware decoding - every
 * hwdec mode in the binary is a copy mode - so every 4K frame is copied out of
 * the hardware decoder into system memory and then composited into a Flutter
 * texture. On a 2 GB Chromecast with Google TV that measured 1,389-1,917 ms of
 * decoder latency and roughly 1.5 dropped frames a second.
 *
 * Media3 hands MediaCodec a SurfaceView instead, so frames reach the display
 * without a copy. The same file measured 904 ms with zero dropped frames, at a
 * third of the CPU and about a third of the memory.
 *
 * mpv is not going away: it still plays torrent streams and containers Media3
 * refuses. This is the fast path, not a replacement.
 */
@UnstableApi
class ExoPlayerBridge(private val context: Context) {

    private companion object {
        const val TAG = "ExoPlayer"
        const val METHOD_CHANNEL = "io.github.tzero86.zplay/exo_player"
        const val EVENT_CHANNEL = "io.github.tzero86.zplay/exo_player/events"
        const val VIEW_ID = "io.github.tzero86.zplay/exo_surface"
    }

    private var player: ExoPlayer? = null

    /**
     * Held independently of the player, because the platform view can be created
     * or destroyed at any time relative to a load - the Flutter view tree owns the
     * surface, this class owns playback. Whichever half arrives second triggers
     * the join. Getting this ordering wrong decodes video and renders nothing,
     * which is exactly what the first spike did.
     */
    private var surfaceHolder: SurfaceHolder? = null

    private var eventSink: EventChannel.EventSink? = null
    private var volume: Float = 1f
    private var playWhenReady: Boolean = true
    private var subtitlesVisible: Boolean = true
    private var lastError: String? = null

    fun register(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        flutterEngine.platformViewsController.registry.registerViewFactory(
            VIEW_ID,
            ExoPlayerViewFactory(::onSurfaceReady, ::onSurfaceGone)
        )

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "load" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("INVALID_ARG", "url is required", null)
                            return@setMethodCallHandler
                        }
                        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                        val start = call.argument<Number>("startMs")?.toLong() ?: 0L
                        val isLive = call.argument<Boolean>("isLive") ?: false
                        load(url, headers, start, isLive)
                        result.success(true)
                    }
                    "attachSurface" -> {
                        attachSurfaceIfPossible()
                        result.success(true)
                    }
                    "play" -> {
                        playWhenReady = true
                        player?.play()
                        result.success(true)
                    }
                    "pause" -> {
                        playWhenReady = false
                        player?.pause()
                        result.success(true)
                    }
                    "playOrPause" -> {
                        playWhenReady = !playWhenReady
                        if (playWhenReady) player?.play() else player?.pause()
                        result.success(true)
                    }
                    "stop" -> {
                        player?.stop()
                        result.success(true)
                    }
                    "seek" -> {
                        val position = call.argument<Number>("positionMs")?.toLong() ?: 0L
                        player?.seekTo(position)
                        result.success(true)
                    }
                    "setRate" -> {
                        val rate = call.argument<Number>("rate")?.toFloat() ?: 1f
                        player?.setPlaybackSpeed(rate)
                        result.success(true)
                    }
                    "setVolume" -> {
                        volume = call.argument<Number>("volume")?.toFloat() ?: 1f
                        player?.volume = volume
                        result.success(true)
                    }
                    "selectAudioTrack" -> {
                        selectTrack(C.TRACK_TYPE_AUDIO, call.argument<Number>("trackId"))
                        result.success(true)
                    }
                    "selectSubtitleTrack" -> {
                        val id = call.argument<Number>("trackId")
                        // A null id means "no subtitles". Media3 expresses that as
                        // the text track type being disabled rather than as a
                        // sentinel track, which is why this is a parameter change
                        // and not a setTrack call.
                        applyTrackParameters(
                            player?.trackSelectionParameters?.buildUpon()
                                ?.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, id == null)
                                ?.build()
                        )
                        result.success(true)
                    }
                    "setSubtitlesVisible" -> {
                        subtitlesVisible = call.argument<Boolean>("visible") ?: true
                        result.success(true)
                    }
                    "release" -> {
                        release()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("ENGINE_ERROR", e.message, Log.getStackTraceString(e))
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun onSurfaceReady(holder: SurfaceHolder) {
        surfaceHolder = holder
        attachSurfaceIfPossible()
    }

    private fun onSurfaceGone() {
        player?.clearVideoSurface()
        surfaceHolder = null
    }

    /**
     * Idempotent, callable from either side: a platform view can be recreated
     * (navigation, resize, engine restart) without a new load, and a load can
     * happen before or after the view exists.
     */
    private fun attachSurfaceIfPossible() {
        val p = player ?: return
        val holder = surfaceHolder ?: return
        if (!holder.surface.isValid) return
        p.setVideoSurface(holder.surface)
        Log.d(TAG, "surface joined to player")
    }

    private fun applyTrackParameters(params: TrackSelectionParameters?) {
        if (params == null) return
        player?.setTrackSelectionParameters(params)
    }

    private fun release() {
        player?.release()
        player = null
    }

    private fun load(
        url: String,
        headers: Map<String, String>,
        startMs: Long,
        isLive: Boolean
    ) {
        release()
        lastError = null

        // HTTP headers go on the data source factory, not on MediaItem:
        // MediaItem has no setHttpRequestHeaders.
        val httpFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(headers)
            .setAllowCrossProtocolRedirects(true)
        val mediaSourceFactory = DefaultMediaSourceFactory(
            DefaultDataSource.Factory(context, httpFactory)
        )

        // Buffer for the device rather than for a flagship. This family of TV has
        // about 2 GB total, and Media3 1.11 already falls back to byte limits when
        // available heap looks tight, so the forward buffer is only what a 4K
        // stream fills in a few seconds.
        val loadControl: LoadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                /* minBufferMs = */ 10_000,
                /* maxBufferMs = */ 30_000,
                /* bufferForPlaybackMs = */ 2_500,
                /* bufferForPlaybackAfterRebufferMs = */ 5_000
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val trackSelector = DefaultTrackSelector(context)

        // Not chained: Kotlin refuses to continue a builder chain across a Java
        // method that returns a widened type, and the intermediate steps read
        // no worse this way.
        val renderersFactory = DefaultRenderersFactory(context)
        // The load control is set on the ExoPlayer builder, not here:
        // DefaultRenderersFactory has no such setter in Media3 1.11.
        renderersFactory.setExtensionRendererMode(
            DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF
        )

        val builder = ExoPlayer.Builder(context, renderersFactory)
        builder.setMediaSourceFactory(mediaSourceFactory)
        builder.setLoadControl(loadControl)
        builder.setTrackSelector(trackSelector)
        val exo = builder.build()

        exo.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            /* handleAudioFocus = */ false
        )
        exo.volume = volume

        val itemBuilder = MediaItem.Builder().setUri(Uri.parse(url))
        if (isLive) {
            itemBuilder.setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(C.TIME_UNSET)
                    .build()
            )
        }
        exo.setMediaItem(itemBuilder.build())

        // A TV panel is 1080p, so letting adaptive selection pick a 2160p
        // rendition is the fastest route back to the OOM kill this engine exists
        // to avoid. Capped by pixels rather than a guessed bitrate.
        exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
            .setMaxVideoSize(Int.MAX_VALUE, 1080)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !subtitlesVisible)
            .build()

        exo.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                emit(mapOf("type" to "state", "state" to stateName(state)))
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                emit(mapOf("type" to "isPlaying", "value" to isPlaying))
            }

            override fun onPlayerError(error: PlaybackException) {
                lastError = error.errorCodeName + ": " + error.message
                emit(mapOf("type" to "error", "message" to (lastError ?: "")))
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                emit(
                    mapOf(
                        "type" to "videoSize",
                        "width" to videoSize.width,
                        "height" to videoSize.height
                    )
                )
            }

            override fun onTracksChanged(tracks: Tracks) {
                emitTracks(tracks)
            }
        })

        if (startMs > 0) exo.seekTo(startMs)
        exo.playWhenReady = playWhenReady
        exo.prepare()

        player = exo
        attachSurfaceIfPossible()
    }

    /**
     * Selects a track by the id the Dart side reported, or disables the track
     * type when [id] is null. Ids are hashed on the way out of Kotlin, so the
     * match is by identity against the groups currently on offer rather than by
     * a format id Dart never sees.
     */
    private fun selectTrack(type: Int, id: Number?) {
        val p = player ?: return
        if (id == null) {
            applyTrackParameters(
                p.trackSelectionParameters.buildUpon()
                    .setTrackTypeDisabled(type, true)
                    .build()
            )
            return
        }

        val target = id.toInt()
        for (group in p.currentTracks.groups) {
            if (group.type != type) continue
            for (trackIndex in 0 until group.length) {
                if (group.getTrackFormat(trackIndex).id.hashCode() != target) continue
                applyTrackParameters(
                    p.trackSelectionParameters.buildUpon()
                        .setOverrideForType(
                            TrackSelectionOverride(
                                group.mediaTrackGroup,
                                listOf(trackIndex)
                            )
                        )
                        .build()
                )
                return
            }
        }
    }

    private fun emitTracks(tracks: Tracks) {
        fun groups(type: Int, label: String): List<Map<String, Any?>> =
            tracks.groups.filter { it.type == type }.map { group ->
                val format = if (group.length > 0) group.getTrackFormat(0) else null
                mapOf(
                    "id" to (format?.id?.hashCode() ?: 0),
                    "title" to (format?.label ?: "$label track"),
                    "language" to format?.language,
                    "codec" to format?.sampleMimeType
                )
            }

        emit(
            mapOf(
                "type" to "tracks",
                "audio" to groups(C.TRACK_TYPE_AUDIO, "Audio"),
                "video" to groups(C.TRACK_TYPE_VIDEO, "Video"),
                "subtitle" to groups(C.TRACK_TYPE_TEXT, "Subtitle")
            )
        )
    }

    private fun emit(event: Map<String, Any?>) {
        eventSink?.success(event)
    }

    private fun stateName(state: Int): String = when (state) {
        Player.STATE_IDLE -> "idle"
        Player.STATE_BUFFERING -> "buffering"
        Player.STATE_READY -> "ready"
        Player.STATE_ENDED -> "ended"
        else -> "unknown"
    }

    fun destroy() {
        release()
        eventSink = null
    }
}

/**
 * Hosts Media3 on a real SurfaceView.
 *
 * `SurfaceView` rather than `TextureView` because SurfaceView gets its own
 * compositor layer, which is what lets a Surface-owned decoder hand frames to
 * the display without the copy mpv is forced into.
 */
@UnstableApi
class ExoPlayerView(private val surfaceView: SurfaceView) : PlatformView {
    override fun getView(): View = surfaceView

    override fun dispose() = Unit
}

@UnstableApi
class ExoPlayerViewFactory(
    private val onSurface: (SurfaceHolder) -> Unit,
    private val onGone: () -> Unit
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val surfaceView = SurfaceView(context)
        surfaceView.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) = onSurface(holder)

            override fun surfaceChanged(
                holder: SurfaceHolder,
                format: Int,
                width: Int,
                height: Int
            ) = Unit

            override fun surfaceDestroyed(holder: SurfaceHolder) = onGone()
        })
        return ExoPlayerView(surfaceView)
    }
}
