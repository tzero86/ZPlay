import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/service_credentials.dart';
import '../storage/json_document_store.dart';

/// Voice option exposed in the picker. IDs match paper2audio.com (kokoro voices).
class Paper2AudioVoice {
  final String id;
  final String label;
  final String group;
  final String description;

  const Paper2AudioVoice(
    this.id,
    this.label,
    this.group, [
    this.description = '',
  ]);
}

const List<Paper2AudioVoice> kPaper2AudioVoices = [
  // US Female
  Paper2AudioVoice(
    'af_heart',
    'Narrator (Heart)',
    'US Female',
    'Bright, engaging, natural rhythm (Recommended)',
  ),
  Paper2AudioVoice(
    'af_bella',
    'Librarian (Bella)',
    'US Female',
    'Calm, warm, soothing storytelling',
  ),
  Paper2AudioVoice(
    'af_sarah',
    'Reporter (Sarah)',
    'US Female',
    'Crisp, articulate, dynamic pacing',
  ),
  Paper2AudioVoice(
    'af_alloy',
    'Professor (Alloy)',
    'US Female',
    'Polished, controlled, educational',
  ),
  // US Male
  Paper2AudioVoice(
    'am_echo',
    'Orator (Echo)',
    'US Male',
    'Resonant, clear, cinematic presence',
  ),
  Paper2AudioVoice(
    'am_liam',
    'Interviewer (Liam)',
    'US Male',
    'Engaging, conversational, friendly',
  ),
  Paper2AudioVoice(
    'am_puck',
    'Teacher (Puck)',
    'US Male',
    'Natural, lively, spirited character',
  ),
  Paper2AudioVoice(
    'am_michael',
    'News Anchor (Michael)',
    'US Male',
    'Polished, deliberate, deep tone',
  ),
  // UK
  Paper2AudioVoice(
    'bf_isabella',
    'Adviser (Isabella)',
    'UK Female',
    'Centred, harmonised, British accent',
  ),
  Paper2AudioVoice(
    'bm_daniel',
    'Counsellor (Daniel)',
    'UK Male',
    'Warm, articulate British voice',
  ),
  Paper2AudioVoice(
    'bf_emma',
    'Emma',
    'UK Female',
    'Classic British storytelling',
  ),
  Paper2AudioVoice(
    'bm_george',
    'George',
    'UK Male',
    'Distinguished British narrator',
  ),
  // Legacy / Character
  Paper2AudioVoice('am_fenrir', 'Fenrir', 'Character', 'Gritty, dramatic tone'),
];

/// Persistent record of a generation job.
class GeneratedAudiobookJob {
  final String runId;
  final String fileName;
  final String voiceId;
  final int createdAt;
  String status; // "pending" / "processing" / "completed" / "failed"
  double progress; // 0..1 (normalized)
  String? downloadUrl;
  String? error;
  String? coverPath; // local path to extracted EPUB cover image
  String? localAudioPath; // local path if downloaded
  int? durationSec;

  GeneratedAudiobookJob({
    required this.runId,
    required this.fileName,
    required this.voiceId,
    required this.createdAt,
    this.status = 'pending',
    this.progress = 0,
    this.downloadUrl,
    this.error,
    this.coverPath,
    this.localAudioPath,
    this.durationSec,
  });

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'fileName': fileName,
    'voiceId': voiceId,
    'createdAt': createdAt,
    'status': status,
    'progress': progress,
    'downloadUrl': downloadUrl,
    'error': error,
    'coverPath': coverPath,
    'localAudioPath': localAudioPath,
    'durationSec': durationSec,
  };

  factory GeneratedAudiobookJob.fromJson(Map<String, dynamic> j) =>
      GeneratedAudiobookJob(
        runId: j['runId'] as String,
        fileName: j['fileName'] as String? ?? 'Untitled.epub',
        voiceId: j['voiceId'] as String? ?? 'af_heart',
        createdAt: j['createdAt'] as int? ?? 0,
        status: j['status'] as String? ?? 'pending',
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        downloadUrl: j['downloadUrl'] as String?,
        error: j['error'] as String?,
        coverPath: j['coverPath'] as String?,
        localAudioPath: j['localAudioPath'] as String?,
        durationSec: j['durationSec'] as int?,
      );

  bool get isDone =>
      (downloadUrl != null && downloadUrl!.isNotEmpty) ||
      (localAudioPath != null && localAudioPath!.isNotEmpty);
  bool get isFailed =>
      status.toLowerCase() == 'failed' || (error != null && error!.isNotEmpty);
}

/// Talks directly to paper2audio.com (Kokoro TTS backend).
/// All heavy work happens on server, so jobs survive app restarts —
/// we just poll using runId.
class Paper2AudioService {
  Paper2AudioService._();
  static final Paper2AudioService instance = Paper2AudioService._();

  static String get _firebaseKey =>
      ServiceCredentials.value(ServiceCredential.paper2audio);
  static const String _baseUrl = 'https://www.paper2audio.com';
  static const String _prefsKey = 'p2a_jobs_v1';

  static final JsonDocumentStore<List<GeneratedAudiobookJob>> _store =
      JsonDocumentStore<List<GeneratedAudiobookJob>>(
        key: _prefsKey,
        version: 1,
        decode: (value) => (value as List)
            .map(
              (entry) =>
                  GeneratedAudiobookJob.fromJson(entry as Map<String, dynamic>),
            )
            .toList(),
        encode: (jobs) => jobs.map((job) => job.toJson()).toList(),
        migrations: <int, JsonMigration>{0: (value) => value},
      );

  final ValueNotifier<List<GeneratedAudiobookJob>> jobs = ValueNotifier([]);
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final stored = await _store.read();
      if (stored != null) {
        jobs.value = stored;
      }
    } catch (e) {
      debugPrint('[Paper2AudioService] Error decoding jobs: $e');
    }
    _loaded = true;
  }

  Future<List<GeneratedAudiobookJob>> getJobs() async {
    await _ensureLoaded();
    return List.unmodifiable(jobs.value);
  }

  Future<void> _persist() async {
    await _store.write(List<GeneratedAudiobookJob>.from(jobs.value));
  }

  Future<void> removeJob(String runId) async {
    await _ensureLoaded();
    jobs.value = jobs.value.where((j) => j.runId != runId).toList();
    await _persist();
  }

  Future<String> _getAuthToken() async {
    final cleanUid = _uuid().replaceAll('-', '');
    final email = 'user_$cleanUid@gmail.com';
    final resp = await http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_firebaseKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': 'TestPassword123!',
        'returnSecureToken': true,
      }),
    );
    if (resp.statusCode >= 400) {
      throw Exception('Auth failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final token = data['idToken'] as String?;
    if (token == null) throw Exception('Auth: missing idToken');
    return token;
  }

  /// Uploads the given EPUB bytes and queues a job. Returns the new job.
  Future<GeneratedAudiobookJob> upload({
    required File epub,
    required String voiceId,
    String? fileNameOverride,
    String? coverPath,
  }) async {
    final fileName =
        fileNameOverride ?? epub.path.split(Platform.pathSeparator).last;
    final bytes = await epub.readAsBytes();
    return uploadBytes(
      bytes: bytes,
      fileName: fileName,
      voiceId: voiceId,
      coverPath: coverPath,
    );
  }

  /// Uploads raw EPUB bytes (use this after splitting an oversized EPUB).
  Future<GeneratedAudiobookJob> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String voiceId,
    String? coverPath,
  }) async {
    await _ensureLoaded();
    final token = await _getAuthToken();
    final uri = Uri.parse('$_baseUrl/v2/summarize').replace(
      queryParameters: {
        'fileName': fileName,
        'link': '',
        'client': 'web',
        'summarizationMethod': 'ultimate',
        'context': '',
        'sendEmailToUser': 'false',
        'appendix': 'false',
        'primaryVoice': voiceId,
        'secondaryVoice': 'am_echo',
        'tertiaryVoice': 'af_alloy',
      },
    );

    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/epub+zip',
      },
      body: bytes,
    );

    if (resp.statusCode >= 400) {
      throw Exception('Upload failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final runId = data['runId'] as String?;
    if (runId == null) throw Exception('Upload: missing runId');

    final job = GeneratedAudiobookJob(
      runId: runId,
      fileName: fileName,
      voiceId: voiceId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      status: 'pending',
      coverPath: coverPath,
    );
    jobs.value = [job, ...jobs.value];
    await _persist();
    return job;
  }

  /// Polls status for a single runId. Updates the persisted job in place.
  Future<GeneratedAudiobookJob?> refreshStatus(String runId) async {
    await _ensureLoaded();
    final idx = jobs.value.indexWhere((j) => j.runId == runId);
    if (idx == -1) return null;
    final job = jobs.value[idx];

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/batchCheckStatus'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'runIds': [runId],
        }),
      );
      if (resp.statusCode >= 400) {
        return job;
      }
      final body = jsonDecode(resp.body);
      final entry = (body is Map && body[runId] is Map)
          ? body[runId] as Map<String, dynamic>
          : null;
      if (entry == null) return job;

      job.status = (entry['status'] as String?) ?? job.status;
      final p = entry['progress'];
      double? pv;
      if (p is num) {
        pv = p.toDouble();
      } else if (p is String) {
        pv = double.tryParse(p);
      }
      if (pv != null) {
        job.progress = pv > 1 ? pv / 100.0 : pv;
      }
      final url = entry['fullAudioFileUrl'] as String?;
      if (url != null && url.isNotEmpty) {
        job.downloadUrl = url;
      }

      // Replace to trigger ValueNotifier listeners.
      final next = List<GeneratedAudiobookJob>.from(jobs.value);
      next[idx] = job;
      jobs.value = next;
      await _persist();
      return job;
    } catch (_) {
      return job;
    }
  }

  /// Refreshes status for all unfinished jobs.
  Future<void> refreshAll() async {
    await _ensureLoaded();
    final pending = jobs.value.where((j) => !j.isDone && !j.isFailed).toList();
    for (final j in pending) {
      await refreshStatus(j.runId);
    }
  }

  /// Downloads the generated audiobook MP3/M4A file locally for offline listening.
  Future<File?> downloadAudiobook(
    GeneratedAudiobookJob job, {
    void Function(double)? onProgress,
  }) async {
    if (!job.isDone || job.downloadUrl == null) return null;
    try {
      Directory? targetDir;
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        targetDir = Directory(
          p.join(appDocDir.path, 'ZPlay', 'GeneratedAudiobooks'),
        );
      } catch (_) {
        final temp = await getTemporaryDirectory();
        targetDir = Directory(
          p.join(temp.path, 'ZPlay', 'GeneratedAudiobooks'),
        );
      }
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final safeName = job.fileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final targetFile = File(
        p.join(targetDir.path, '${job.runId}_$safeName.mp3'),
      );

      if (await targetFile.exists() && await targetFile.length() > 1000) {
        job.localAudioPath = targetFile.path;
        await _persist();
        return targetFile;
      }

      final client = HttpClient();
      final uri = Uri.parse(job.downloadUrl!);
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        return null;
      }

      final total = resp.contentLength;
      int received = 0;
      final sink = targetFile.openWrite();
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(received / total);
        }
      }
      await sink.flush();
      await sink.close();

      job.localAudioPath = targetFile.path;
      await _persist();
      return targetFile;
    } catch (e) {
      debugPrint('[Paper2AudioService] download error: $e');
      return null;
    }
  }

  // Tiny UUID v4 (no extra dep).
  String _uuid() {
    final r = DateTime.now().microsecondsSinceEpoch;
    final rnd = (r ^ (r >> 16)).toRadixString(16).padLeft(8, '0');
    final tail = (r * 1664525 + 1013904223)
        .toUnsigned(32)
        .toRadixString(16)
        .padLeft(8, '0');
    return '$rnd-${tail.substring(0, 4)}-4${tail.substring(4, 7)}-a${rnd.substring(0, 3)}-$tail$rnd'
        .substring(0, 36);
  }
}
