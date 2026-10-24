import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/download/download_task_model.dart';
import '../../models/stream/stream_model.dart';
import '../../utils/download/download_path_helper.dart';
import '../../utils/platform/storage_space_helper.dart';
import '../../utils/security/safe_paths.dart';
import '../debrid/debrid_service.dart';
import '../stream/torrent_stream_service.dart';
import 'hls_download_engine.dart';

/// Comprehensive Background & In-App Download Manager.
///
/// Features:
/// - Native TorrServer disk downloading with rarest-first piece swarm throughput for P2P.
/// - Resilient Dart HTTP Range downloading for Cloud Debrid and direct HTTP/Addon streams.
/// - Full HLS (.m3u8) multi-chunk parsing, AES-128 decryption, and seamless concatenation.
/// - Task persistence across app launches with seamless pause and resume.
/// - Background Wakelock protection while downloads are active.
class DownloadService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final DownloadService instance = DownloadService._internal();
  factory DownloadService() => instance;
  DownloadService._internal();

  // ── State & Notifiers ─────────────────────────────────────────────────────
  final ValueNotifier<List<DownloadTask>> tasksNotifier =
      ValueNotifier<List<DownloadTask>>([]);
  bool _isInitialized = false;

  // Active HTTP download clients/subscriptions keyed by taskId
  final Map<String, HttpClientRequest> _httpRequests = {};
  final Map<String, StreamSubscription<List<int>>> _httpSubscriptions = {};
  final Map<String, IOSink> _httpFileSinks = {};

  // Flag for coordinated pause/cancellation
  final Set<String> _canceledOrPausedTaskIds = {};

  // ── Initialization ────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadPersistedTasks();
    _isInitialized = true;
  }

  // ── Task Persistence ───────────────────────────────────────────────────────
  static const String _storageFilename = 'zplay_download_tasks.json';

  Future<File> _getStorageFile() async {
    final docDir = await getApplicationDocumentsDirectory();
    return File(p.join(docDir.path, _storageFilename));
  }

  Future<void> _loadPersistedTasks() async {
    try {
      final file = await _getStorageFile();
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.isEmpty) return;

      final List<dynamic> jsonList = jsonDecode(content);
      final tasks = <DownloadTask>[];
      final downloadRoots =
          await DownloadPathHelper.getTrustedDownloadDirectories();

      for (final item in jsonList) {
        if (item is Map<String, dynamic>) {
          var task = DownloadTask.fromJson(item);
          if (!downloadRoots.any(
            (root) => isWithinDirectory(root, task.targetFilePath),
          )) {
            debugPrint(
              '[DownloadService] Rejected download path outside configured roots',
            );
            task = task.copyWith(
              status: DownloadStatus.failed,
              error: 'Invalid download path',
            );
            tasks.add(task);
            continue;
          }
          // If app was terminated while downloading, set state to paused
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.queued) {
            task = task.copyWith(status: DownloadStatus.paused);
          }
          // Verify completed file still exists on disk
          if (task.status == DownloadStatus.completed) {
            final f = File(task.targetFilePath);
            if (!f.existsSync()) {
              task = task.copyWith(
                status: DownloadStatus.failed,
                error: 'File was moved or deleted from disk',
              );
            }
          }
          tasks.add(task);
        }
      }

      tasksNotifier.value = tasks;
      _updateWakelockState();
    } catch (e) {
      debugPrint('[DownloadService] Failed to load persisted tasks: $e');
    }
  }

  Future<void> _persistTasks() async {
    try {
      final file = await _getStorageFile();
      final jsonList = tasksNotifier.value.map((t) => t.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[DownloadService] Failed to persist tasks: $e');
    }
  }

  void _updateTask(DownloadTask updated) {
    final current = List<DownloadTask>.from(tasksNotifier.value);
    final idx = current.indexWhere((t) => t.id == updated.id);
    if (idx != -1) {
      current[idx] = updated;
      tasksNotifier.value = current;
      _persistTasks();
    }
    _updateWakelockState();
  }

  void _updateWakelockState() {
    final hasActive = tasksNotifier.value.any(
      (t) => t.status == DownloadStatus.downloading,
    );
    if (hasActive) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  // ── Public API: Start Download ─────────────────────────────────────────────

  /// Starts downloading a stream source.
  /// Checks disk space before initiating and manages P2P/Debrid/HTTP routing.
  Future<DownloadTask> startDownload({
    required String title,
    required String mediaId,
    required String type, // 'movie', 'series', 'anime'
    int? season,
    int? episode,
    String? episodeTitle,
    String? posterUrl,
    String? backdropUrl,
    String? year,
    required StreamSource source,
    String? customDownloadDir,
  }) async {
    await initialize();

    final downloadDir =
        customDownloadDir ??
        await DownloadPathHelper.getDownloadsDirectoryPath();
    final now = DateTime.now();
    final taskId =
        'dl_${mediaId}_${season ?? 0}_${episode ?? 0}_${now.millisecondsSinceEpoch}';

    final safeTitle = DownloadPathHelper.sanitizeFilename(title);
    final epSuffix = (season != null && episode != null)
        ? '_S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}'
        : '';
    final baseFilename = '$safeTitle$epSuffix';

    final rawUrl = source.url;
    var infoHash = source.infoHash;
    final isMagnetUrl = rawUrl != null && rawUrl.startsWith('magnet:');
    if ((infoHash == null || infoHash.isEmpty) && isMagnetUrl) {
      final match = RegExp(r'[0-9a-fA-F]{40}').firstMatch(rawUrl);
      if (match != null) {
        infoHash = match.group(0);
      }
    }

    String? fullMagnet;
    if (isMagnetUrl) {
      fullMagnet = rawUrl;
    } else if (infoHash != null && infoHash.isNotEmpty) {
      fullMagnet = 'magnet:?xt=urn:btih:$infoHash';
      if (source.sources != null) {
        for (final s in source.sources!) {
          if (s.startsWith('tracker:')) {
            final tr = s.replaceFirst('tracker:', '');
            fullMagnet = '$fullMagnet&tr=${Uri.encodeComponent(tr)}';
          }
        }
      }
    }

    final isTorrent = (infoHash != null && infoHash.isNotEmpty) || isMagnetUrl;
    final useDebrid =
        isTorrent && await DebridService().isDebridActiveForStreams();

    DownloadSourceType sourceType;
    String targetExt = '.mp4';

    if (isTorrent && !useDebrid) {
      sourceType = DownloadSourceType.p2p;
      targetExt = '.mkv'; // Standard container for torrent video
    } else if (useDebrid) {
      sourceType = DownloadSourceType.debrid;
    } else {
      sourceType = DownloadSourceType.http;
      if (rawUrl != null && rawUrl.toLowerCase().contains('.mkv')) {
        targetExt = '.mkv';
      }
    }

    final targetPath = p.join(downloadDir, '$baseFilename$targetExt');

    final task = DownloadTask(
      id: taskId,
      title: (season != null && episode != null)
          ? '$title - S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}'
          : title,
      mediaId: mediaId,
      type: type,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      year: year,
      sourceType: sourceType,
      sourceName: source.name ?? source.addonName,
      addonName: source.addonName,
      rawUrl: source.url,
      magnet: fullMagnet,
      infoHash: infoHash,
      fileIdx: source.fileIdx,
      headers: source.headers,
      targetFilePath: targetPath,
      status: DownloadStatus.queued,
      createdAt: now,
    );

    // Deduplicate against existing tasks
    final current = List<DownloadTask>.from(tasksNotifier.value);
    final existingIdx = current.indexWhere(
      (t) =>
          t.id == taskId ||
          (t.mediaId == mediaId && t.season == season && t.episode == episode),
    );

    if (existingIdx != -1) {
      final existing = current[existingIdx];
      if (existing.isDownloading) return existing;
      if (existing.isCompleted) return existing;
      current.removeAt(existingIdx);
    }

    current.insert(0, task);
    tasksNotifier.value = current;
    await _persistTasks();

    // Begin download in background without blocking caller/player
    _executeDownload(task);
    return task;
  }

  Future<void> _executeDownload(DownloadTask task) async {
    if (!await _isTargetPathAllowed(task.targetFilePath)) {
      debugPrint(
        '[DownloadService] Refused to execute download outside configured roots',
      );
      _updateTask(
        task.copyWith(
          status: DownloadStatus.failed,
          error: 'Invalid download path',
        ),
      );
      return;
    }

    _canceledOrPausedTaskIds.remove(task.id);
    _updateTask(task.copyWith(status: DownloadStatus.downloading, error: null));

    switch (task.sourceType) {
      case DownloadSourceType.p2p:
        await _executeP2PDownload(task);
        break;
      case DownloadSourceType.debrid:
        await _executeDebridDownload(task);
        break;
      case DownloadSourceType.http:
        if (HlsDownloadEngine.isHlsUrl(task.rawUrl)) {
          await _executeHlsDownload(task);
        } else {
          await _executeHttpDownload(task);
        }
        break;
    }
  }

  Future<bool> _isTargetPathAllowed(String targetPath) async {
    final roots = await DownloadPathHelper.getTrustedDownloadDirectories();
    return roots.any((root) => isWithinDirectory(root, targetPath));
  }

  // ── Engine 1: TorrServer P2P Swarm Download ───────────────────────────────

  Future<void> _executeP2PDownload(DownloadTask task) async {
    try {
      final tss = TorrentStreamService();
      if (!tss.controller.isRunning || tss.state != EngineState.ready) {
        final started = await tss.start();
        if (!started) {
          throw Exception('Failed to initialize TorrServer background engine');
        }
      }

      final magnet =
          task.magnet ??
          (task.infoHash != null ? 'magnet:?xt=urn:btih:${task.infoHash}' : '');
      if (magnet.isEmpty) {
        throw Exception('No valid magnet link for torrent download');
      }

      // Resolve stream URL from TorrentStreamService
      final streamUrl = await tss.streamTorrent(
        magnet,
        season: task.season,
        episode: task.episode,
        fileIdx: task.fileIdx,
      );

      if (streamUrl == null || streamUrl.isEmpty) {
        throw Exception('TorrServer could not resolve media stream URL');
      }

      final match = RegExp(r'[0-9a-fA-F]{40}').firstMatch(streamUrl);
      final hash = match?.group(0) ?? task.infoHash;

      // Stream torrent from TorrServer over loopback directly to destination file
      final p2pTask = task.copyWith(rawUrl: streamUrl, infoHash: hash);
      _updateTask(p2pTask);
      await _executeHttpDownload(p2pTask);
    } catch (e) {
      if (!_canceledOrPausedTaskIds.contains(task.id)) {
        _updateTask(
          task.copyWith(status: DownloadStatus.failed, error: e.toString()),
        );
      }
    }
  }

  // ── Engine 2: Cloud Debrid Resolve + Dart HTTP Download ────────────────────

  Future<void> _executeDebridDownload(DownloadTask task) async {
    try {
      final debrid = DebridService();
      final magnet =
          task.magnet ??
          (task.infoHash != null ? 'magnet:?xt=urn:btih:${task.infoHash}' : '');

      final debridFiles = await debrid.resolveMagnet(
        magnet: magnet,
        fileIndex: task.fileIdx,
        filename: task.title,
        season: task.season,
        episode: task.episode,
      );

      if (debridFiles.isEmpty || debridFiles.first.downloadUrl.isEmpty) {
        throw Exception('Debrid cloud returned no direct download links');
      }

      final directDownloadUrl = debridFiles.first.downloadUrl;
      final debridTask = task.copyWith(rawUrl: directDownloadUrl);
      if (HlsDownloadEngine.isHlsUrl(directDownloadUrl)) {
        await _executeHlsDownload(debridTask);
      } else {
        await _executeHttpDownload(debridTask);
      }
    } catch (e) {
      _updateTask(
        task.copyWith(status: DownloadStatus.failed, error: e.toString()),
      );
    }
  }

  // ── Engine 3: Full HLS Multi-Segment Downloader ────────────────────────────

  Future<void> _executeHlsDownload(DownloadTask task) async {
    try {
      await HlsDownloadEngine.downloadHlsStream(
        task: task,
        onProgress: (updated) => _updateTask(updated),
        isPausedOrCanceled: () => _canceledOrPausedTaskIds.contains(task.id),
      );
    } catch (e) {
      if (!_canceledOrPausedTaskIds.contains(task.id)) {
        _updateTask(
          task.copyWith(status: DownloadStatus.failed, error: e.toString()),
        );
      }
    }
  }

  // ── Engine 4: Dart HTTP Client with Range-based Resumption ─────────────────

  Future<void> _executeHttpDownload(
    DownloadTask task, {
    int attempt = 1,
  }) async {
    final urlStr = task.rawUrl;
    if (urlStr == null || urlStr.isEmpty) {
      _updateTask(
        task.copyWith(
          status: DownloadStatus.failed,
          error: 'Empty download URL',
        ),
      );
      return;
    }

    final partFilePath = '${task.targetFilePath}.part';
    final partFile = File(partFilePath);
    if (!await partFile.parent.exists()) {
      await partFile.parent.create(recursive: true);
    }

    int existingBytes = 0;
    if (await partFile.exists()) {
      existingBytes = await partFile.length();
    }

    // Check if task was already fully downloaded but not yet finalized
    if (task.totalBytes > 0 && existingBytes >= task.totalBytes) {
      await _finalizeDownloadedFile(task, partFile);
      return;
    }

    try {
      final uri = Uri.parse(urlStr);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 25);

      final request = await client.getUrl(uri);
      _httpRequests[task.id] = request;

      // Add custom headers & user agent
      if (task.headers != null) {
        task.headers!.forEach((k, v) => request.headers.set(k, v));
      }
      if (task.headers == null || !task.headers!.containsKey('User-Agent')) {
        request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        );
      }

      // Range header for seamless resumption
      if (existingBytes > 0) {
        request.headers.set('Range', 'bytes=$existingBytes-');
      }

      final response = await request.close();
      final isPartial = response.statusCode == HttpStatus.partialContent;
      final isOk = response.statusCode == HttpStatus.ok;

      if (!isPartial && !isOk) {
        // If range was unsatisfiable (416), file is probably already fully downloaded
        if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
            existingBytes > 0) {
          await _finalizeDownloadedFile(task, partFile);
          return;
        }
        throw Exception(
          'Server returned HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      int totalContentLength = response.contentLength;
      int totalBytes = task.totalBytes;

      if (isPartial) {
        totalBytes =
            existingBytes + (totalContentLength > 0 ? totalContentLength : 0);
      } else if (isOk) {
        existingBytes = 0; // Server did not accept Range, restarting from 0
        totalBytes = totalContentLength > 0 ? totalContentLength : 0;
      }

      // Check available disk space
      final enoughSpace = await StorageSpaceHelper.hasEnoughSpace(
        partFile.parent.path,
        totalBytes > 0 ? (totalBytes - existingBytes) : 1024 * 1024 * 500,
      );
      if (!enoughSpace) {
        throw Exception('Insufficient free disk space on target partition');
      }

      final mode = (existingBytes > 0 && isPartial)
          ? FileMode.append
          : FileMode.write;
      final sink = partFile.openWrite(mode: mode);
      _httpFileSinks[task.id] = sink;

      int receivedSoFar = existingBytes;
      int bytesInLastSecond = 0;
      DateTime lastSpeedCalc = DateTime.now();

      final subscription = response.listen(
        (chunk) {
          sink.add(chunk);
          receivedSoFar += chunk.length;
          bytesInLastSecond += chunk.length;

          final now = DateTime.now();
          final elapsed = now.difference(lastSpeedCalc).inMilliseconds;

          if (elapsed >= 1000) {
            final speed = (bytesInLastSecond / (elapsed / 1000.0));
            bytesInLastSecond = 0;
            lastSpeedCalc = now;

            int? eta;
            if (speed > 0 && totalBytes > receivedSoFar) {
              eta = ((totalBytes - receivedSoFar) / speed).ceil();
            }

            _updateTask(
              task.copyWith(
                status: DownloadStatus.downloading,
                receivedBytes: receivedSoFar,
                totalBytes: totalBytes > 0 ? totalBytes : receivedSoFar,
                speedBytesPerSec: speed,
                etaSeconds: eta,
                error: null,
              ),
            );
          }
        },
        onDone: () async {
          try {
            await sink.flush();
            await sink.close();
          } catch (_) {}
          _httpFileSinks.remove(task.id);
          _httpSubscriptions.remove(task.id);
          _httpRequests.remove(task.id);

          if (_canceledOrPausedTaskIds.contains(task.id)) return;

          // Check if stream closed prematurely before reaching total bytes (common 99% hiccup)
          if (totalBytes > 0 &&
              receivedSoFar < (totalBytes - 2048) &&
              attempt < 5) {
            debugPrint(
              '[DownloadService] Stream closed prematurely ($receivedSoFar / $totalBytes bytes). Auto-reconnecting attempt ${attempt + 1}...',
            );
            _updateTask(
              task.copyWith(
                status: DownloadStatus.downloading,
                error: 'Reconnecting remaining data (attempt $attempt)...',
                speedBytesPerSec: 0.0,
              ),
            );
            await Future.delayed(Duration(seconds: attempt));
            if (!_canceledOrPausedTaskIds.contains(task.id)) {
              await _executeHttpDownload(
                task.copyWith(
                  receivedBytes: receivedSoFar,
                  totalBytes: totalBytes,
                ),
                attempt: attempt + 1,
              );
            }
            return;
          }

          await _finalizeDownloadedFile(
            task.copyWith(
              receivedBytes: receivedSoFar,
              totalBytes: totalBytes > 0 ? totalBytes : receivedSoFar,
            ),
            partFile,
          );
        },
        onError: (err) async {
          try {
            await sink.flush();
            await sink.close();
          } catch (_) {}
          _httpFileSinks.remove(task.id);
          _httpSubscriptions.remove(task.id);
          _httpRequests.remove(task.id);

          if (_canceledOrPausedTaskIds.contains(task.id)) return;

          // Auto-reconnect up to 4 attempts on network error
          if (attempt < 5) {
            debugPrint(
              '[DownloadService] Download network error: $err. Auto-reconnecting attempt ${attempt + 1}...',
            );
            _updateTask(
              task.copyWith(
                status: DownloadStatus.downloading,
                error: 'Reconnecting (attempt $attempt)...',
                speedBytesPerSec: 0.0,
              ),
            );
            await Future.delayed(Duration(seconds: attempt * 2));
            if (!_canceledOrPausedTaskIds.contains(task.id)) {
              await _executeHttpDownload(
                task.copyWith(
                  receivedBytes: receivedSoFar,
                  totalBytes: totalBytes,
                ),
                attempt: attempt + 1,
              );
            }
            return;
          }

          _updateTask(
            task.copyWith(
              status: DownloadStatus.failed,
              error: err.toString(),
              speedBytesPerSec: 0.0,
            ),
          );
        },
        cancelOnError: true,
      );

      _httpSubscriptions[task.id] = subscription;
    } catch (e) {
      _cleanupHttpTask(task.id);
      if (!_canceledOrPausedTaskIds.contains(task.id)) {
        if (attempt < 5) {
          debugPrint(
            '[DownloadService] Exception in HTTP download: $e. Auto-reconnecting attempt ${attempt + 1}...',
          );
          _updateTask(
            task.copyWith(
              status: DownloadStatus.downloading,
              error: 'Reconnecting (attempt $attempt)...',
              speedBytesPerSec: 0.0,
            ),
          );
          await Future.delayed(Duration(seconds: attempt * 2));
          if (!_canceledOrPausedTaskIds.contains(task.id)) {
            await _executeHttpDownload(task, attempt: attempt + 1);
            return;
          }
        }
        _updateTask(
          task.copyWith(
            status: DownloadStatus.failed,
            error: e.toString(),
            speedBytesPerSec: 0.0,
          ),
        );
      }
    }
  }

  Future<void> _finalizeDownloadedFile(DownloadTask task, File partFile) async {
    try {
      // Small delay on Windows to ensure OS releases any file handles
      await Future.delayed(const Duration(milliseconds: 200));

      final finalFile = File(task.targetFilePath);
      if (await finalFile.exists()) {
        try {
          await finalFile.delete();
        } catch (_) {}
      }

      // Try atomic rename first, fallback to copy + delete if locked or cross-device
      try {
        await partFile.rename(task.targetFilePath);
      } catch (e) {
        debugPrint('[DownloadService] Rename failed, using fallback copy: $e');
        await partFile.copy(task.targetFilePath);
        try {
          await partFile.delete();
        } catch (_) {}
      }

      final completedBytes = await File(task.targetFilePath).length();

      _updateTask(
        task.copyWith(
          status: DownloadStatus.completed,
          receivedBytes: completedBytes,
          totalBytes: completedBytes,
          speedBytesPerSec: 0.0,
          etaSeconds: 0,
          completedAt: DateTime.now(),
          error: null,
        ),
      );
    } catch (e) {
      debugPrint('[DownloadService] Error finalizing downloaded file: $e');
      _updateTask(
        task.copyWith(
          status: DownloadStatus.failed,
          error: 'Failed to save final file: $e',
        ),
      );
    }
  }

  void _cleanupHttpTask(String taskId) {
    _httpSubscriptions[taskId]?.cancel();
    _httpSubscriptions.remove(taskId);
    _httpRequests[taskId]?.abort();
    _httpRequests.remove(taskId);
    try {
      _httpFileSinks[taskId]?.close();
    } catch (_) {}
    _httpFileSinks.remove(taskId);
  }

  // ── Public API: Pause, Resume, Cancel, Delete ──────────────────────────────

  /// Pauses an active download.
  Future<void> pauseDownload(String taskId) async {
    _canceledOrPausedTaskIds.add(taskId);
    final task = tasksNotifier.value.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;

    _cleanupHttpTask(taskId);

    _updateTask(
      task.copyWith(
        status: DownloadStatus.paused,
        speedBytesPerSec: 0.0,
        etaSeconds: null,
      ),
    );
  }

  /// Resumes or retries a paused/failed download.
  Future<void> resumeDownload(String taskId) async {
    _canceledOrPausedTaskIds.remove(taskId);
    final task = tasksNotifier.value.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;

    _updateTask(task.copyWith(status: DownloadStatus.queued, error: null));
    _executeDownload(task);
  }

  /// Cancels an active download and cleans up temporary .part files.
  Future<void> cancelDownload(String taskId) async {
    final task = tasksNotifier.value.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;

    await pauseDownload(taskId);

    if (task.sourceType == DownloadSourceType.p2p && task.infoHash != null) {
      try {
        await TorrentStreamService().removeTorrent(task.infoHash!);
      } catch (_) {}
    } else {
      final partFile = File('${task.targetFilePath}.part');
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      final metaFile = File('${task.targetFilePath}.hls_meta.json');
      if (await metaFile.exists()) {
        try {
          await metaFile.delete();
        } catch (_) {}
      }
    }

    _updateTask(task.copyWith(status: DownloadStatus.canceled));
  }

  /// Deletes a download task and its associated local file from disk.
  Future<void> deleteDownload(String taskId) async {
    final task = tasksNotifier.value.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;

    await cancelDownload(taskId);

    final targetFile = File(task.targetFilePath);
    if (await targetFile.exists()) {
      try {
        await targetFile.delete();
      } catch (_) {}
    }

    final current = List<DownloadTask>.from(tasksNotifier.value)
      ..removeWhere((t) => t.id == taskId);
    tasksNotifier.value = current;
    await _persistTasks();
    _updateWakelockState();
  }
}
