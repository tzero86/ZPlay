import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:torrserver_flutter/torrserver_flutter.dart';

import '../../models/download/download_task_model.dart';
import '../download/download_service.dart';
import '../debrid/utils/debrid_media_matcher.dart';

/// Rich torrent statistics object.
class TorrentStats {
  final double speedMbps;
  final int activePeers;
  final int totalPeers;
  final double cachePercent;
  final int loadedBytes;
  final int totalBytes;
  final String hash;
  final bool isConnected;

  const TorrentStats({
    required this.speedMbps,
    required this.activePeers,
    required this.totalPeers,
    required this.cachePercent,
    required this.loadedBytes,
    required this.totalBytes,
    required this.hash,
    required this.isConnected,
  });

  double get speedKbps => speedMbps * 1024;
  String get speedLabel => speedMbps >= 1.0
      ? '${speedMbps.toStringAsFixed(2)} MB/s'
      : '${speedKbps.toStringAsFixed(0)} KB/s';
  String get peersLabel => '$activePeers / $totalPeers';
  String get cacheLabel => '${cachePercent.toStringAsFixed(1)}%';
}

/// Engine lifecycle states.
enum EngineState { stopped, starting, ready, error }

/// Production-grade TorrentStreamService powered by torrserver_flutter.
///
/// Provides high performance HTTP streaming with automatic free-port allocation,
/// cross-platform subprocess / FFI management, intelligent file selection
/// (via ParseTorrentTitle), and real-time swarm statistics.
class TorrentStreamService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final TorrentStreamService _instance = TorrentStreamService._internal();
  factory TorrentStreamService() => _instance;
  TorrentStreamService._internal();

  // ── Controller & State ─────────────────────────────────────────────────────
  final TorrServerController _controller = createTorrServerController();
  TorrServerController get controller => _controller;

  EngineState _state = EngineState.stopped;
  EngineState get state => _state;

  void Function(EngineState state)? onStateChanged;
  void Function(String line)? onLogLine;

  /// Active torrent hashes tracked by the service.
  final Set<String> _activeTorrents = {};

  /// Latest torrent update snapshots keyed by infohash.
  final Map<String, TorrentInfo> _latestUpdates = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Engine memory budget
  // ─────────────────────────────────────────────────────────────────────────

  /// Piece-cache budget handed to the TorrServer engine, in bytes.
  ///
  /// TorrServer keeps torrent pieces in RAM — `UseDisk` defaults to `false`, so
  /// `CacheSize` *is* the engine's piece-memory budget, not a per-stream
  /// allowance. A reader's retention window is computed from it directly
  /// (`cache.capacity / readers` split by `ReaderReadAHead`), so this one number
  /// bounds the engine's anonymous memory for a playing torrent.
  ///
  /// The engine default is 64 MiB. Measured on the 2 GB Chromecast with Google
  /// TV this app ships to, a playing torrent put the engine at ~122 MB PSS,
  /// roughly 82 MB of it cache, while the system reported 147-262 MB
  /// `MemAvailable` and a swap file that was already 100% full. The kernel paid
  /// for that cache by evicting the player's own decode buffers to eMMC
  /// (~24 major faults/s), which is the video path stalling while audio — 5 KB
  /// per frame and resident — plays on. The engine cache is the largest single
  /// term of the two processes that Dart can reach, and it is the only one the
  /// engine lets the app size.
  ///
  /// 32 MiB is the floor, and it is a floor rather than a round number:
  ///
  /// - The cache must still hold the pieces in flight. `getRemPieces()` evicts
  ///   by last access outside the readers' ranges, so a budget below the working
  ///   set starts discarding pieces the reader is about to ask for.
  /// - 32 MiB is more than what a 40 Mbit/s 4K stream (~5 MB/s) spends in six
  ///   seconds, and half a minute of a 1080p one, so a reader's window still
  ///   spans ordinary swarm gaps. It is not the whole cushion: mpv holds its own
  ///   64 MiB forward (12.8 s at 40 Mbit/s) and a stalled engine read is absorbed
  ///   there. Halving this again would leave a ~3 s window, below the point where
  ///   the two are still additive rather than redundant.
  ///
  /// The trade is explicit: 32 MiB of engine cache given back to the device, and
  /// the readahead the engine cache was duplicating now lives only in mpv's
  /// demuxer cache — combined readahead across the two processes drops from
  /// ~25 s to ~19 s of a 40 Mbit/s stream.
  static const int engineCacheBytes = 32 * 1024 * 1024;

  /// The engine's own default when nothing overrides it.
  static const int engineDefaultCacheBytes = 64 * 1024 * 1024;

  /// Total RAM below which [engineCacheBytes] is applied.
  ///
  /// Desktop and large-TV boxes get the engine's own default: 32 MiB of cache
  /// would be a regression there, where the memory is free and the swarm gaps are
  /// not.
  static const int lowMemoryTotalBytes = 2560 * 1024 * 1024;

  /// How long an engine HTTP call may take before it is treated as failed.
  ///
  /// The engine's HTTP handler has been observed to stop answering while the
  /// process stays alive and holds its RSS (13 CLOSE-WAIT sockets with unread
  /// requests, 0 CPU). The package's client sets no deadline, so an unresponsive
  /// engine would hang `streamTorrent` forever and leave the player spinning
  /// instead of failing.
  static const Duration engineCallTimeout = Duration(seconds: 8);

  /// Reads `MemTotal` out of a `/proc/meminfo` body, in bytes. Returns null when
  /// the field is missing or not a number.
  static int? parseMemTotalBytes(String meminfo) {
    for (final line in const LineSplitter().convert(meminfo)) {
      if (!line.startsWith('MemTotal:')) continue;
      final match = RegExp(r'(\d+)').firstMatch(line);
      final kb = match == null ? null : int.tryParse(match.group(1)!);
      return kb == null ? null : kb * 1024;
    }
    return null;
  }

  /// The `sets` payload for the engine's `/settings` endpoint, carrying every
  /// field the engine reported with only `CacheSize` replaced.
  ///
  /// Merging rather than sending a typed object is what keeps the engine's
  /// `DefaultTrackers` list — and the trackers it finds — out of the app's
  /// hands. A `set` replaces the whole `BTSets` struct engine-side, so anything
  /// omitted here is written back as a zero value.
  static Map<String, dynamic> budgetedSettings(
    Map<String, dynamic> current, {
    int cacheBytes = engineCacheBytes,
  }) {
    return <String, dynamic>{...current, 'CacheSize': cacheBytes};
  }

  /// Whether a device with [totalBytes] of RAM is small enough that the engine's
  /// own cache default is worth shrinking. An unknown size is treated as large,
  /// so the engine keeps its own default rather than being guessed at.
  static bool isLowMemoryTotal(int? totalBytes) {
    if (totalBytes == null) return false;
    return totalBytes < lowMemoryTotalBytes;
  }

  /// The device's total RAM in bytes, or null where `/proc/meminfo` is absent
  /// (Windows, iOS).
  Future<int?> readDeviceTotalBytes() async {
    if (!Platform.isAndroid && !Platform.isLinux) return null;
    try {
      return parseMemTotalBytes(await File('/proc/meminfo').readAsString());
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Starts the TorrServer engine and sizes its RAM cache for this device.
  ///
  /// Safe to call multiple times.
  Future<bool> start() async {
    if (_controller.isRunning && _state == EngineState.ready) return true;
    if (_state == EngineState.starting) {
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_controller.isRunning && _state == EngineState.ready) return true;
        if (_state == EngineState.error) return false;
      }
      return false;
    }

    _setState(EngineState.starting);
    try {
      _log('Starting TorrServer engine...');
      await _controller.start();
      final version = await _controller.echo().timeout(engineCallTimeout);
      _setState(EngineState.ready);
      _log('TorrServer ready at ${_controller.baseUrl} (version: $version)');
      // Before any torrent is added: the engine's settings handler drops every
      // torrent and rebuilds the BitTorrent client, so this can only run on a
      // fresh engine. See [_applyEngineMemoryBudget].
      await _applyMemoryBudgetForThisDevice();
      return true;
    } catch (e, st) {
      _log('Failed to start TorrServer: $e\n$st');
      _setState(EngineState.error);
      return false;
    }
  }

  /// Sizes the engine's RAM cache for the device it is running on.
  Future<void> _applyMemoryBudgetForThisDevice() async {
    final totalBytes = await readDeviceTotalBytes();
    if (!isLowMemoryTotal(totalBytes)) {
      _log('Device RAM ${totalBytes ?? 'unknown'} bytes: keeping the engine cache default.');
      return;
    }
    _log('Device RAM $totalBytes bytes is under $lowMemoryTotalBytes; trimming the engine cache.');
    await _applyEngineMemoryBudget();
  }

  /// Writes [engineCacheBytes] to the running engine, leaving every other
  /// setting alone.
  ///
  /// This goes over the raw `/settings` API rather than
  /// `TorrServerController.setSettings`, because the package's
  /// `TorrServerSettings.toJson()` omits the engine's `TrackersListURL`,
  /// `DefaultTrackers` and `MergeAllM3U` fields — a typed round-trip would write
  /// an empty tracker list and cost the swarm the peers the trackers find. The
  /// engine's own `action: get` payload is merged instead, so only `CacheSize`
  /// changes.
  ///
  /// Must only run while no torrent is loaded: the engine's `action: set` handler
  /// (`torr.SetSettings`) drops every torrent and tears the client down and back
  /// up, which mid-playback would kill the stream being watched.
  Future<bool> _applyEngineMemoryBudget() async {
    final base = _controller.baseUrl;
    if (base == null) return false;
    final uri = base.replace(path: '/settings');
    try {
      final current = await _postSettings(uri, const {'action': 'get'});
      if (current == null) {
        _log('Engine settings unavailable; leaving the engine cache at its default.');
        return false;
      }
      if (current['CacheSize'] == engineCacheBytes) {
        _log('Engine cache already at $engineCacheBytes bytes.');
        return true;
      }
      await _postSettings(uri, {
        'action': 'set',
        'sets': budgetedSettings(current),
      });
      _log('Engine cache ${current['CacheSize']} -> $engineCacheBytes bytes.');
      return true;
    } catch (e) {
      _log('Could not size the engine cache ($e); the engine keeps its own default.');
      return false;
    }
  }

  /// POSTs a JSON body to an engine endpoint and decodes the reply, or null for
  /// an empty body. Bounded by [engineCallTimeout] so a wedged engine fails
  /// instead of hanging the caller.
  Future<Map<String, dynamic>?> _postSettings(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final res = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(body),
        )
        .timeout(engineCallTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('engine /settings answered ${res.statusCode}');
    }
    if (res.body.isEmpty) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stream a torrent — main entry point
  // ─────────────────────────────────────────────────────────────────────────

  /// Adds a magnet, waits for metadata, selects the right file, starts an
  /// HTTP stream, and returns the stream URL.
  Future<String?> streamTorrent(
    String magnetLink, {
    int? season,
    int? episode,
    String? episodeTitle,
    int? fileIdx,
  }) async {
    if (!_controller.isRunning || _state != EngineState.ready) {
      final started = await start();
      if (!started) {
        _log('Cannot stream: TorrServer engine failed to start.');
        return null;
      }
    }

    final rawHash = _extractHash(magnetLink);
    final formattedMagnet = (rawHash != null && !magnetLink.startsWith('magnet:?'))
        ? 'magnet:?xt=urn:btih:$rawHash'
        : magnetLink;

    final displayName = _extractDisplayName(formattedMagnet);

    try {
      _log('Adding torrent to TorrServer...');
      final added = await _controller
          .addTorrent(
            magnet: formattedMagnet,
            title: displayName.isNotEmpty ? displayName : null,
            saveToDb: false,
          )
          .timeout(engineCallTimeout);

      final hash = added.hash.isNotEmpty
          ? added.hash.toLowerCase()
          : (rawHash ?? '').toLowerCase();

      if (hash.isNotEmpty) {
        _activeTorrents.add(hash);
        _latestUpdates[hash] = added;
      }

      _log('Torrent added: $hash ($displayName). Waiting for metadata...');

      // Wait for torrent metadata / file list
      final files = await _waitForMetadata(hash);
      if (files == null || files.isEmpty) {
        _log('No files found in torrent metadata');
        return null;
      }

      // Auto file picker
      final selectedFileId = _selectFile(
        files,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
        preferredIdx: fileIdx,
      );

      if (selectedFileId == null) {
        _log('No suitable media file found in torrent');
        return null;
      }

      final selectedFile = files.firstWhere(
        (f) => f.id == selectedFileId,
        orElse: () => files.first,
      );
      _log('Selected file #${selectedFile.id}: "${selectedFile.path}" (${_formatBytes(selectedFile.length)})');

      final streamUri = _controller.streamUrl(hash, fileIndex: selectedFile.id);
      _log('HTTP Stream URL generated: $streamUri');

      return streamUri.toString();
    } catch (e, st) {
      _log('streamTorrent error: $e\n$st');
      return null;
    }
  }

  /// Adds a magnet, waits for metadata, and returns full TorrentInfo including all files.
  Future<TorrentInfo?> getTorrentMetadata(String magnetLink) async {
    try {
      final started = await start();
      if (!started) return null;

      final rawHash = _extractHash(magnetLink);
      if (rawHash == null) {
        _log('Invalid magnet link / hash: $magnetLink');
        return null;
      }
      final hash = rawHash.toLowerCase();

      final formattedMagnet = !magnetLink.startsWith('magnet:?')
          ? 'magnet:?xt=urn:btih:$rawHash'
          : magnetLink;

      final title = _extractDisplayName(formattedMagnet);
      _log('Adding torrent for file list inspection: $hash ($title)');
      await _controller
          .addTorrent(
            magnet: formattedMagnet,
            title: title.isNotEmpty ? title : null,
            saveToDb: false,
          )
          .timeout(engineCallTimeout);
      _activeTorrents.add(hash);

      final files = await _waitForMetadata(hash);
      if (files == null || files.isEmpty) return null;

      return await _controller.getTorrent(hash).timeout(engineCallTimeout);
    } catch (e, st) {
      _log('getTorrentMetadata error: $e\n$st');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Metadata polling
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<TorrentFileStat>?> _waitForMetadata(
    String hash, {
    Duration timeout = const Duration(seconds: 45),
    Duration pollInterval = const Duration(milliseconds: 300),
  }) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      try {
        final info =
            await _controller.getTorrent(hash).timeout(engineCallTimeout);
        _latestUpdates[hash] = info;
        if (info.fileStats.isNotEmpty) {
          return info.fileStats;
        }
      } catch (e) {
        _log('Polling metadata error: $e');
      }
      await Future.delayed(pollInterval);
    }

    _log('Metadata timeout after ${timeout.inSeconds}s for hash $hash');
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // File selection — intelligent auto file picker
  // ─────────────────────────────────────────────────────────────────────────
  // File selection — intelligent auto file picker
  // ─────────────────────────────────────────────────────────────────────────

  int? _selectFile(
    List<TorrentFileStat> files, {
    int? season,
    int? episode,
    String? episodeTitle,
    int? preferredIdx,
  }) {
    if (files.isEmpty) return null;

    final picked = DebridMediaMatcher.pickMediaFile<TorrentFileStat>(
      files,
      fileIndex: preferredIdx,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      name: (f) => f.path,
      size: (f) => f.length,
    );

    return picked?.id;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Torrent management & Statistics
  // ─────────────────────────────────────────────────────────────────────────

  /// Removes a torrent from TorrServer.
  Future<void> removeTorrent(String magnetOrHash) async {
    final hash = _extractHash(magnetOrHash) ?? magnetOrHash.toLowerCase();
    _activeTorrents.remove(hash);
    _latestUpdates.remove(hash);
    if (_controller.isRunning) {
      try {
        await _controller.removeTorrent(hash);
        _log('Removed torrent $hash from TorrServer');
      } catch (e) {
        _log('Error removing torrent $hash: $e');
      }
    }
  }

  /// Returns latest cached or live stats for a torrent.
  TorrentStats? getTorrentStats(String magnetOrHash) {
    final hash = _extractHash(magnetOrHash) ?? magnetOrHash.toLowerCase();
    final info = _latestUpdates[hash];
    if (info == null) return null;

    final speedMbps = info.downloadSpeed / 1024 / 1024;
    final total = info.torrentSize;
    final loaded = info.loadedSize;
    final percent = total > 0 ? (loaded / total) * 100 : 0.0;

    return TorrentStats(
      speedMbps: speedMbps,
      activePeers: info.activePeers,
      totalPeers: info.totalPeers,
      cachePercent: percent,
      loadedBytes: loaded,
      totalBytes: total,
      hash: hash,
      isConnected: info.activePeers > 0 || info.downloadSpeed > 0,
    );
  }

  /// Streams stats at [interval] for a torrent.
  Stream<TorrentStats> statsStream(
    String magnetOrHash, {
    Duration interval = const Duration(seconds: 1),
  }) {
    final hash = _extractHash(magnetOrHash) ?? magnetOrHash.toLowerCase();
    final streamController = StreamController<TorrentStats>();
    Timer? timer;

    streamController.onListen = () {
      timer = Timer.periodic(interval, (_) async {
        if (!_controller.isRunning || streamController.isClosed) return;
        try {
          final info =
              await _controller.getTorrent(hash).timeout(engineCallTimeout);
          _latestUpdates[hash] = info;
          final stats = getTorrentStats(hash);
          if (stats != null && !streamController.isClosed) {
            streamController.add(stats);
          }
        } catch (_) {}
      });
    };

    streamController.onCancel = () {
      timer?.cancel();
      streamController.close();
    };

    return streamController.stream;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stop / cleanup
  // ─────────────────────────────────────────────────────────────────────────

  /// Drops active torrents from RAM to free resources when closing player.
  Future<void> cleanup() async {
    final downloadingHashes = <String>{};
    for (final task in DownloadService.instance.tasksNotifier.value) {
      if (task.isDownloading || task.status == DownloadStatus.queued) {
        final h1 = task.infoHash != null ? _extractHash(task.infoHash!) : null;
        final h2 = task.magnet != null ? _extractHash(task.magnet!) : null;
        final h3 = task.rawUrl != null ? _extractHash(task.rawUrl!) : null;
        if (h1 != null) downloadingHashes.add(h1);
        if (h2 != null) downloadingHashes.add(h2);
        if (h3 != null) downloadingHashes.add(h3);
      }
    }

    for (final hash in List<String>.from(_activeTorrents)) {
      if (downloadingHashes.contains(hash.toLowerCase())) {
        continue;
      }
      try {
        if (_controller.isRunning) {
          await _controller.dropTorrent(hash);
        }
      } catch (_) {}
    }
    _activeTorrents.removeWhere((h) => !downloadingHashes.contains(h.toLowerCase()));
    _latestUpdates.removeWhere((k, _) => !downloadingHashes.contains(k.toLowerCase()));
  }

  /// Completely stops the TorrServer engine process.
  Future<void> stop() async {
    if (_controller.isRunning) {
      try {
        await _controller.stop();
        _log('TorrServer stopped.');
      } catch (e) {
        _log('Error stopping TorrServer: $e');
      }
    }
    _activeTorrents.clear();
    _latestUpdates.clear();
    _setState(EngineState.stopped);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static final _hashRegExp = RegExp(r'[0-9a-fA-F]{40}');

  String? _extractHash(String magnetOrHash) {
    final match = _hashRegExp.firstMatch(magnetOrHash);
    return match?.group(0)?.toLowerCase();
  }

  String _extractDisplayName(String magnet) {
    try {
      final match = RegExp(r'[?&]dn=([^&]+)').firstMatch(magnet);
      if (match != null && match.group(1) != null) {
        return Uri.decodeComponent(match.group(1)!.replaceAll('+', ' '));
      }
    } catch (_) {}
    return '';
  }

  String _formatBytes(num bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : 2)} ${suffixes[i]}';
  }

  void _setState(EngineState s) {
    if (_state == s) return;
    _state = s;
    onStateChanged?.call(s);
  }

  void _log(String message) {
    debugPrint('[TorrentStream] $message');
    onLogLine?.call(message);
  }
}