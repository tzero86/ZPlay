import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/audiobook/audiobook_model.dart';
import '../storage/json_document_store.dart';

/// Representation of a user-uploaded local audiobook.
class UserUploadedAudiobook {
  final String id;
  final String title;
  final String author;
  final String? coverPath;
  final List<String> audioFilePaths;
  final int createdAt;
  final int totalBytes;

  UserUploadedAudiobook({
    required this.id,
    required this.title,
    this.author = 'Unknown Author',
    this.coverPath,
    required this.audioFilePaths,
    required this.createdAt,
    this.totalBytes = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'coverPath': coverPath,
    'audioFilePaths': audioFilePaths,
    'createdAt': createdAt,
    'totalBytes': totalBytes,
  };

  factory UserUploadedAudiobook.fromJson(Map<String, dynamic> j) =>
      UserUploadedAudiobook(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Untitled Audiobook',
        author: j['author'] as String? ?? 'Unknown Author',
        coverPath: j['coverPath'] as String?,
        audioFilePaths: (j['audioFilePaths'] as List?)?.cast<String>() ?? [],
        createdAt: j['createdAt'] as int? ?? 0,
        totalBytes: j['totalBytes'] as int? ?? 0,
      );

  /// Converts this uploaded book into the app's standard [Audiobook] model.
  Audiobook toAudiobookModel() {
    return Audiobook(
      uuid: 'custom_$id',
      audioBookId: 'custom_$id',
      dynamicSlugId: id,
      title: title,
      author: author,
      coverImage: coverPath ?? '',
      source: 'Local Upload',
      pageUrl: audioFilePaths.isNotEmpty ? audioFilePaths.first : '',
    );
  }

  /// Converts the audio tracks into [AudiobookChapter] list.
  List<AudiobookChapter> toChapters() {
    if (audioFilePaths.isEmpty) {
      return [AudiobookChapter(title: title, url: '')];
    }
    return audioFilePaths.asMap().entries.map((entry) {
      final idx = entry.key;
      final filePath = entry.value;
      final fileName = p.basenameWithoutExtension(filePath);
      final cleanName = fileName.replaceAll(RegExp(r'^[\d\s._-]+'), '').trim();
      final chapterTitle = cleanName.isNotEmpty ? cleanName : 'Part ${idx + 1}';
      return AudiobookChapter(
        title: audioFilePaths.length == 1 ? title : chapterTitle,
        url: filePath,
      );
    }).toList();
  }
}

/// Service managing user-uploaded personal audiobooks.
class CustomAudiobookService {
  CustomAudiobookService._();
  static final CustomAudiobookService instance = CustomAudiobookService._();

  static const String _prefsKey = 'custom_audiobooks_v1';

  static final JsonDocumentStore<List<UserUploadedAudiobook>> _store =
      JsonDocumentStore<List<UserUploadedAudiobook>>(
        key: _prefsKey,
        version: 1,
        decode: (value) => (value as List)
            .map(
              (entry) =>
                  UserUploadedAudiobook.fromJson(entry as Map<String, dynamic>),
            )
            .toList(),
        encode: (books) => books.map((book) => book.toJson()).toList(),
        migrations: <int, JsonMigration>{0: (value) => value},
      );

  final ValueNotifier<List<UserUploadedAudiobook>> audiobooks = ValueNotifier(
    [],
  );
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final stored = await _store.read();
      if (stored != null) {
        audiobooks.value = stored;
      }
    } catch (e) {
      debugPrint('[CustomAudiobookService] Error decoding: $e');
    }
    _loaded = true;
  }

  Future<List<UserUploadedAudiobook>> getAll() async {
    await ensureLoaded();
    return List.unmodifiable(audiobooks.value);
  }

  Future<void> _persist() async {
    await _store.write(List<UserUploadedAudiobook>.from(audiobooks.value));
  }

  /// Imports audio files selected by user into the local CustomAudiobooks library.
  Future<UserUploadedAudiobook?> importAudiobook({
    required List<File> audioFiles,
    required String title,
    String author = 'Unknown Author',
    File? coverImageFile,
  }) async {
    if (audioFiles.isEmpty) return null;
    await ensureLoaded();

    Directory? targetDir;
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      targetDir = Directory(
        p.join(appDocDir.path, 'ZPlay', 'CustomAudiobooks'),
      );
    } catch (_) {
      final temp = await getTemporaryDirectory();
      targetDir = Directory(p.join(temp.path, 'ZPlay', 'CustomAudiobooks'));
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final bookDir = Directory(p.join(targetDir.path, id));
    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }

    // Copy audio files into local library
    final savedAudioPaths = <String>[];
    int totalBytes = 0;
    for (int i = 0; i < audioFiles.length; i++) {
      final original = audioFiles[i];
      final ext = p.extension(original.path);
      final destFile = File(
        p.join(bookDir.path, 'track_${i.toString().padLeft(3, '0')}$ext'),
      );
      await original.copy(destFile.path);
      savedAudioPaths.add(destFile.path);
      totalBytes += await destFile.length();
    }

    // Copy cover image if provided
    String? savedCoverPath;
    if (coverImageFile != null && await coverImageFile.exists()) {
      final ext = p.extension(coverImageFile.path);
      final destCover = File(p.join(bookDir.path, 'cover$ext'));
      await coverImageFile.copy(destCover.path);
      savedCoverPath = destCover.path;
    }

    final newBook = UserUploadedAudiobook(
      id: id,
      title: title.trim().isEmpty ? 'Uploaded Audiobook' : title.trim(),
      author: author.trim().isEmpty ? 'Unknown Author' : author.trim(),
      coverPath: savedCoverPath,
      audioFilePaths: savedAudioPaths,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      totalBytes: totalBytes,
    );

    audiobooks.value = [newBook, ...audiobooks.value];
    await _persist();
    return newBook;
  }

  /// Prompts file picker for user to select audio files.
  Future<UserUploadedAudiobook?> pickAndImportAudiobook({
    String? titleOverride,
    String? authorOverride,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3',
        'm4b',
        'm4a',
        'aac',
        'flac',
        'opus',
        'wav',
        'ogg',
      ],
      allowMultiple: true,
      withData: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final files = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

    if (files.isEmpty) return null;

    // Default title from the first file name
    final firstFile = files.first;
    final defaultTitle =
        titleOverride ??
        p
            .basenameWithoutExtension(firstFile.path)
            .replaceAll(RegExp(r'[._]'), ' ')
            .trim();

    return importAudiobook(
      audioFiles: files,
      title: defaultTitle,
      author: authorOverride ?? 'Local Upload',
    );
  }

  /// Deletes a custom uploaded audiobook and all associated files on disk.
  Future<void> deleteAudiobook(String id) async {
    await ensureLoaded();
    final idx = audiobooks.value.indexWhere((a) => a.id == id);
    if (idx == -1) return;

    final book = audiobooks.value[idx];
    try {
      if (book.audioFilePaths.isNotEmpty) {
        final parentDir = File(book.audioFilePaths.first).parent;
        if (await parentDir.exists()) {
          await parentDir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('[CustomAudiobookService] Error deleting directory: $e');
    }

    audiobooks.value = audiobooks.value.where((a) => a.id != id).toList();
    await _persist();
  }
}
