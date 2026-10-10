import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../models/audiobook/audiobook_model.dart';
import '../../services/audiobook/custom_audiobook_service.dart';
import '../../services/audiobook/downloaded_epub_detector.dart';
import '../../services/audiobook/epub_cover.dart';
import '../../services/audiobook/epub_splitter.dart';
import '../../services/audiobook/paper2audio_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/segmented_tabs.dart';
import '../../widgets/player/player_glass.dart';
import 'audiobook_player_screen.dart';

/// Worker for running EPUB splitting and word analysis off the UI thread via `compute`.
Future<List<EpubPart>> _splitWorker(String path) {
  return EpubSplitter.splitIfNeeded(File(path));
}

class GenerateAudiobookScreen extends StatefulWidget {
  const GenerateAudiobookScreen({super.key});

  @override
  State<GenerateAudiobookScreen> createState() => _GenerateAudiobookScreenState();
}

class _GenerateAudiobookScreenState extends State<GenerateAudiobookScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Paper2AudioService _paperService = Paper2AudioService.instance;
  final CustomAudiobookService _customService = CustomAudiobookService.instance;

  String _selectedVoiceId = 'af_heart';
  bool _isUploading = false;
  Timer? _pollingTimer;

  List<DetectedEpubBook> _detectedEpubs = [];
  bool _isLoadingEpubs = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _bootstrap();
  }

  /// A swipe moves the [TabController] without going through the segmented
  /// control, so the control has to be rebuilt from the controller's own index.
  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await _paperService.getJobs();
    await _customService.ensureLoaded();
    await _loadDownloadedEpubs();
    if (!mounted) return;
    setState(() {});
    _schedulePolling();
  }

  Future<void> _loadDownloadedEpubs() async {
    setState(() => _isLoadingEpubs = true);
    final epubs = await DownloadedEpubDetector.scanDownloadedEpubs();
    if (mounted) {
      setState(() {
        _detectedEpubs = epubs;
        _isLoadingEpubs = false;
      });
    }
  }

  void _schedulePolling() {
    _pollingTimer?.cancel();
    () async {
      await _paperService.refreshAll();
      if (!mounted) return;
      final hasPending = _paperService.jobs.value.any((j) => !j.isDone && !j.isFailed);
      if (hasPending) {
        _pollingTimer = Timer(const Duration(seconds: 8), _schedulePolling);
      }
    }();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Generation Handlers
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _pickAndUploadEpub() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      withData: false,
    );
    if (result == null || result.files.single.path == null) return;
    await _processAndGenerateFromEpub(File(result.files.single.path!));
  }

  Future<void> _processAndGenerateFromEpub(File file) async {
    final tokens = context.tokens;

    setState(() => _isUploading = true);
    try {
      // Analyze and split if oversized (>250k words) on background thread
      final parts = await compute(_splitWorker, file.path);

      // Extract cover image from the original EPUB
      final originalBytes = await file.readAsBytes();
      final rawName = p.basenameWithoutExtension(file.path);
      final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final coverPath = await EpubCover.extractAndSave(
        epubBytes: originalBytes,
        saveAsName: '${safeName}_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (parts.length > 1) {
        if (!mounted) return;
        final totalWords = parts.fold<int>(0, (a, p) => a + p.wordCount);
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: tokens.surfaceOverlay,
            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
            title: Row(
              children: [
                Icon(Icons.call_split_rounded, color: tokens.accent),
                const SizedBox(width: 10),
                Text('EPUB Exceeds 250k Words',
                    style: ZplayType.title.copyWith(size: 16).toStyle(color: tokens.textPrimary)),
              ],
            ),
            content: Text(
              'This book has ~${_formatWords(totalWords)} words. It will automatically be split into ${parts.length} parts along chapter boundaries and queued:\n\n'
              '${parts.map((p) => '• ${p.suggestedName} (~${_formatWords(p.wordCount)} words)').join('\n')}',
              style: ZplayType.label.toStyle(color: tokens.textEmphasis),
            ),
            actions: [
              PillButton(
                label: 'Cancel',
                variant: PillVariant.secondary,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              PillButton(
                label: 'Split & Generate',
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        );

        if (confirm != true) {
          if (mounted) setState(() => _isUploading = false);
          return;
        }
      }

      for (final part in parts) {
        await _paperService.uploadBytes(
          bytes: part.bytes,
          fileName: part.suggestedName,
          voiceId: _selectedVoiceId,
          coverPath: coverPath,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parts.length == 1
              ? 'Upload complete — AI Audiobook generation started!'
              : 'Uploaded ${parts.length} parts — generation started in background!'),
          backgroundColor: tokens.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _schedulePolling();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Generation failed: $e'), backgroundColor: tokens.danger),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _formatWords(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n >= 100000 ? 0 : 1)}k';
    }
    return n.toString();
  }

  void _playGeneratedAudiobook(GeneratedAudiobookJob job) {
    if (!job.isDone) return;
    final title = job.fileName.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
    final streamOrLocalPath = job.localAudioPath ?? job.downloadUrl!;

    final book = Audiobook(
      uuid: 'p2a_${job.runId}',
      audioBookId: 'p2a_${job.runId}',
      dynamicSlugId: job.runId,
      title: title,
      author: 'AI Generated • Kokoro TTS',
      coverImage: job.coverPath ?? '',
      source: 'Paper2Audio AI',
      pageUrl: streamOrLocalPath,
    );

    final chapters = [
      AudiobookChapter(title: title, url: streamOrLocalPath),
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudiobookPlayerScreen(
          audiobook: book,
          chapters: chapters,
        ),
      ),
    );
  }

  Future<void> _copyStreamUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stream URL copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteGeneratedJob(GeneratedAudiobookJob job) async {
    final tokens = context.tokens;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.surfaceOverlay,
        shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
        title: const Text('Remove Generation Job?'),
        content: Text('Remove "${job.fileName}" from the generation list?'),
        actions: [
          PillButton(
            label: 'Cancel',
            variant: PillVariant.secondary,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          // Destructive: kept as a labelled row rather than a pill, because the
          // pill has no destructive variant and the one it would borrow says
          // nothing about the irreversible action.
          FocusableInkWell(
            onTap: () => Navigator.pop(ctx, true),
            borderRadius: ZplayRadius.smAll,
            hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s12,
                vertical: ZplaySpacing.s8,
              ),
              child: Text('Remove', style: ZplayType.label.toStyle(color: tokens.danger)),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _paperService.removeJob(job.runId);
      if (mounted) setState(() {});
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Custom Upload Handlers
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _openCustomAudiobookUploadDialog() async {
    final tokens = context.tokens;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4b', 'm4a', 'aac', 'flac', 'opus', 'wav', 'ogg'],
      allowMultiple: true,
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final pickedFiles = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

    if (pickedFiles.isEmpty || !mounted) return;

    final titleController = TextEditingController(
      text: p.basenameWithoutExtension(pickedFiles.first.path).replaceAll(RegExp(r'[._]'), ' ').trim(),
    );
    final authorController = TextEditingController(text: 'Unknown Author');
    File? pickedCoverFile;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: tokens.surfaceOverlay,
            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.lgAll),
            title: Row(
              children: [
                Icon(Icons.upload_file_rounded, color: tokens.accent),
                const SizedBox(width: 10),
                Text('Add Personal Audiobook',
                    style: ZplayType.title.copyWith(size: 16.5).toStyle(color: tokens.textPrimary)),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected ${pickedFiles.length} audio file(s):',
                      style: ZplayType.bodySmall
                          .copyWith(size: 12.5, weight: FontWeight.w600)
                          .toStyle(color: tokens.textEmphasis),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 90),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: ZplayRadius.smAll,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: pickedFiles.map((f) => Text(
                          '• ${p.basename(f.path)}',
                          style: ZplayType.caption.copyWith(size: 11.5).toStyle(color: tokens.textSecondary),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      style: ZplayType.body.toStyle(color: tokens.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Audiobook Title',
                        labelStyle: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                        filled: true,
                        fillColor: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
                        border: const OutlineInputBorder(borderRadius: ZplayRadius.smAll),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: authorController,
                      style: ZplayType.body.toStyle(color: tokens.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Author / Narrator',
                        labelStyle: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                        filled: true,
                        fillColor: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
                        border: const OutlineInputBorder(borderRadius: ZplayRadius.smAll),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Cover Picker Button
                    Row(
                      children: [
                        if (pickedCoverFile != null)
                          ClipRRect(
                            borderRadius: ZplayRadius.smAll,
                            child: Image.file(pickedCoverFile!, width: 44, height: 44, fit: BoxFit.cover),
                          )
                        else
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: tokens.borderStrong,
                              borderRadius: ZplayRadius.smAll,
                            ),
                            child: Icon(Icons.image_rounded, color: tokens.textMuted),
                          ),
                        const SizedBox(width: 12),
                        FocusableInkWell(
                          onTap: () async {
                            final imgResult = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              withData: false,
                            );
                            if (imgResult != null && imgResult.files.single.path != null) {
                              setDlgState(() {
                                pickedCoverFile = File(imgResult.files.single.path!);
                              });
                            }
                          },
                          borderRadius: ZplayRadius.smAll,
                          hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ZplaySpacing.s8,
                              vertical: ZplaySpacing.s8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.photo_library_rounded, size: 16, color: tokens.accent),
                                const SizedBox(width: ZplaySpacing.s8),
                                Text(
                                  pickedCoverFile == null ? 'Select Cover Art' : 'Change Cover',
                                  style: ZplayType.label.toStyle(color: tokens.accent),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              PillButton(
                label: 'Cancel',
                variant: PillVariant.secondary,
                onPressed: () => Navigator.pop(ctx),
              ),
              PillButton(
                label: 'Import to Library',
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _customService.importAudiobook(
                    audioFiles: pickedFiles,
                    title: titleController.text,
                    author: authorController.text,
                    coverImageFile: pickedCoverFile,
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _playUploadedAudiobook(UserUploadedAudiobook book) {
    final audiobook = book.toAudiobookModel();
    final chapters = book.toChapters();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudiobookPlayerScreen(
          audiobook: audiobook,
          chapters: chapters,
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI Builder
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: AnimatedAmbientBackground(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneratorTab(),
                  _buildUploadedTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The route's own chrome.
  ///
  /// This is a pushed route, so the shell paints nothing above it and this row
  /// *is* the top chrome: it is transparent, carries no hairline, and spends the
  /// status-bar inset itself — an opaque band with an edge across the top would
  /// re-create the shell seam this design language removed.
  Widget _buildHeader() {
    final tokens = context.tokens;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ZplaySpacing.s16,
        MediaQuery.paddingOf(context).top + ZplaySpacing.s12,
        ZplaySpacing.s16,
        ZplaySpacing.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FocusableInkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: ZplayRadius.fullAll,
                hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.arrow_back_ios_rounded,
                    color: tokens.textEmphasis,
                    size: 20,
                    shadows: const [
                      Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: ZplaySpacing.s12),
              Icon(Icons.auto_stories_rounded, color: tokens.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Audiobook Studio & Generator',
                  style: ZplayType.title.toStyle(color: tokens.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZplaySpacing.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs<int>(
              semanticsLabel: 'Audiobook studio tabs',
              height: 44,
              selected: _tabController.index,
              onSelected: (i) => _tabController.animateTo(i),
              options: const [
                SegmentedTabOption(value: 0, label: 'AI EPUB Generator (TTS)'),
                SegmentedTabOption(value: 1, label: 'My Uploaded Audiobooks'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Tab 1: AI Generator
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildGeneratorTab() {
    final tokens = context.tokens;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ValueListenableBuilder<List<GeneratedAudiobookJob>>(
          valueListenable: _paperService.jobs,
          builder: (context, jobs, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              physics: const BouncingScrollPhysics(),
              children: [
                // ── Voice Selector Card ──
                _buildVoiceSelectorCard(),

                const SizedBox(height: 20),

                // ── Section: Downloaded EPUBs from Books Section ──
                _buildDetectedEpubsSection(),

                const SizedBox(height: 20),

                // ── Upload External EPUB File Banner ──
                _buildUploadExternalCard(),

                const SizedBox(height: 28),

                // ── Section: Active & Completed Generation Jobs ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'GENERATION QUEUE & COMPLETED (${jobs.length})',
                      style: ZplayType.overline
                          .copyWith(size: 12, weight: FontWeight.w700, letterSpacing: 1.1)
                          .toStyle(color: tokens.textMuted),
                    ),
                    Tooltip(
                      message: 'Refresh Status',
                      child: FocusableInkWell(
                        onTap: () => _paperService.refreshAll(),
                        borderRadius: ZplayRadius.fullAll,
                        hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.refresh_rounded, size: 18, color: tokens.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (jobs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.headphones_rounded, size: 40, color: tokens.textDisabled),
                        const SizedBox(height: 12),
                        Text(
                          'No generated audiobooks yet',
                          style: ZplayType.body
                              .copyWith(weight: FontWeight.w600)
                              .toStyle(color: tokens.textEmphasis),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pick an EPUB above to synthesize high-quality voice narrations.',
                          style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  )
                else
                  ...jobs.map((job) => _buildJobCard(job)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildVoiceSelectorCard() {
    final tokens = context.tokens;
    final selectedVoice = kPaper2AudioVoices.firstWhere(
      (v) => v.id == _selectedVoiceId,
      orElse: () => kPaper2AudioVoices.first,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.2),
                  borderRadius: ZplayRadius.smAll,
                ),
                child: Icon(Icons.record_voice_over_rounded, color: tokens.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Narrator Voice (Kokoro Engine)',
                      style: ZplayType.body
                          .copyWith(size: 14.5, weight: FontWeight.w700)
                          .toStyle(color: tokens.textPrimary),
                    ),
                    Text(
                      selectedVoice.description,
                      style: ZplayType.caption.copyWith(size: 11.5).toStyle(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              // A form field keeps a fill even without its hairline — the same
              // faint wash the dialogs' text fields use.
              color: tokens.textPrimary.withValues(alpha: ZplayOpacity.borderFaint),
              borderRadius: ZplayRadius.smAll,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedVoiceId,
                isExpanded: true,
                dropdownColor: tokens.surfaceOverlay,
                icon: Icon(Icons.arrow_drop_down_rounded, color: tokens.textEmphasis),
                items: kPaper2AudioVoices.map((voice) {
                  return DropdownMenuItem<String>(
                    value: voice.id,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          voice.label,
                          style: ZplayType.label.copyWith(weight: FontWeight.w600).toStyle(color: tokens.textPrimary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: tokens.borderDefault,
                            borderRadius: ZplayRadius.xsAll,
                          ),
                          child: Text(
                            voice.group,
                            style: ZplayType.overline
                                .copyWith(weight: FontWeight.w700)
                                .toStyle(color: tokens.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedVoiceId = val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedEpubsSection() {
    final tokens = context.tokens;

    if (_isLoadingEpubs) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    }

    if (_detectedEpubs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DOWNLOADED BOOKS FROM LIBRARY (${_detectedEpubs.length})',
              style: ZplayType.overline
                  .copyWith(size: 12, weight: FontWeight.w700, letterSpacing: 1.1)
                  .toStyle(color: tokens.textMuted),
            ),
            FocusableInkWell(
              onTap: _loadDownloadedEpubs,
              borderRadius: ZplayRadius.smAll,
              hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s8,
                  vertical: ZplaySpacing.s8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 14, color: tokens.accent),
                    const SizedBox(width: ZplaySpacing.s4),
                    Text('Rescan Books', style: ZplayType.caption.toStyle(color: tokens.accent)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 165,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _detectedEpubs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, idx) {
              final epub = _detectedEpubs[idx];
              return Container(
                width: 260,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                ),
                child: Row(
                  children: [
                    // Cover image
                    Container(
                      width: 65,
                      height: 145,
                      decoration: BoxDecoration(
                        color: tokens.borderStrong,
                        borderRadius: ZplayRadius.smAll,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: epub.coverPath != null
                          ? Image.file(File(epub.coverPath!), fit: BoxFit.cover)
                          : Icon(Icons.book_rounded, color: tokens.textDisabled, size: 30),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            epub.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.label.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Size: ${(epub.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                            style: ZplayType.caption.toStyle(color: tokens.textMuted),
                          ),
                          const Spacer(),
                          // Keeps the file's compact accent chip rather than a
                          // pill: [PillButton]'s only fills are the white primary
                          // and the dark scrim, and a white pill on each detected
                          // book would out-shout the section it sits in. The ring
                          // is the shared one, so the chip is still reachable and
                          // marked like every other control.
                          FocusableCard(
                            onTap: _isUploading
                                ? null
                                : () => _processAndGenerateFromEpub(File(epub.filePath)),
                            enabled: !_isUploading,
                            cursor: _isUploading
                                ? SystemMouseCursors.basic
                                : SystemMouseCursors.click,
                            builder: (context, state) => CardFocusRing(
                              focused: state.focused,
                              radius: ZplayRadius.smAll,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: tokens.accent,
                                  borderRadius: ZplayRadius.smAll,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.record_voice_over_rounded, size: 14, color: tokens.onAccent),
                                    const SizedBox(width: ZplaySpacing.s8),
                                    Text(
                                      'Generate',
                                      style: ZplayType.bodySmall
                                          .copyWith(weight: FontWeight.w700)
                                          .toStyle(color: tokens.onAccent),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUploadExternalCard() {
    final tokens = context.tokens;

    return FocusableInkWell(
      onTap: _isUploading ? null : _pickAndUploadEpub,
      enabled: !_isUploading,
      borderRadius: ZplayRadius.mdAll,
      hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              tokens.accent.withValues(alpha: 0.15),
              tokens.info.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: ZplayRadius.mdAll,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.25),
                borderRadius: ZplayRadius.mdAll,
              ),
              child: _isUploading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(color: tokens.onAccent, strokeWidth: 2.5))
                  : Icon(Icons.upload_file_rounded, color: tokens.onAccent, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isUploading ? 'Analyzing & Uploading Book...' : 'Select External EPUB File',
                    style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Pick any .epub file from your device. Large books (>250k words) are auto-split.',
                    style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: tokens.textSecondary, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildJobCard(GeneratedAudiobookJob job) {
    final tokens = context.tokens;
    final isDone = job.isDone;
    final isFailed = job.isFailed;
    final cleanTitle = job.fileName.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');

    Color statusColor;
    String statusLabel;
    if (isDone) {
      statusColor = tokens.success;
      statusLabel = 'Completed';
    } else if (isFailed) {
      statusColor = tokens.danger;
      statusLabel = 'Failed';
    } else {
      statusColor = tokens.warning;
      statusLabel = 'Synthesizing ${(job.progress * 100).round()}%';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Cover
              Container(
                width: 48,
                height: 64,
                decoration: BoxDecoration(
                  color: tokens.borderStrong,
                  borderRadius: ZplayRadius.smAll,
                ),
                clipBehavior: Clip.antiAlias,
                child: job.coverPath != null && File(job.coverPath!).existsSync()
                    ? Image.file(File(job.coverPath!), fit: BoxFit.cover)
                    : Icon(Icons.headphones_rounded, color: tokens.textDisabled, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cleanTitle,
                      style: ZplayType.body.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: ZplayRadius.xsAll,
                          ),
                          child: Text(
                            statusLabel,
                            style: ZplayType.caption
                                .copyWith(size: 10.5, weight: FontWeight.w700)
                                .toStyle(color: statusColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Voice: ${job.voiceId}',
                          style: ZplayType.caption.toStyle(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Delete Button
              FocusableInkWell(
                onTap: () => _deleteGeneratedJob(job),
                borderRadius: ZplayRadius.fullAll,
                hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.delete_outline_rounded, size: 18, color: tokens.textMuted),
                ),
              ),
            ],
          ),

          if (!isDone && !isFailed) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: ZplayRadius.xsAll,
              child: LinearProgressIndicator(
                value: job.progress > 0 ? job.progress : null,
                backgroundColor: tokens.borderStrong,
                color: tokens.accent,
                minHeight: 5,
              ),
            ),
          ],

          if (isDone) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Play in App',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    onPressed: () => _playGeneratedAudiobook(job),
                  ),
                ),
                const SizedBox(width: 8),
                if (job.downloadUrl != null)
                  PillButton(
                    label: 'Copy Stream URL',
                    icon: Icons.link_rounded,
                    variant: PillVariant.secondary,
                    onPressed: () => _copyStreamUrl(job.downloadUrl!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Tab 2: My Uploaded Audiobooks
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildUploadedTab() {
    final tokens = context.tokens;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ValueListenableBuilder<List<UserUploadedAudiobook>>(
          valueListenable: _customService.audiobooks,
          builder: (context, books, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              physics: const BouncingScrollPhysics(),
              children: [
                // Upload Personal Audiobook Banner
                FocusableInkWell(
                  onTap: _openCustomAudiobookUploadDialog,
                  borderRadius: ZplayRadius.mdAll,
                  hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          tokens.success.withValues(alpha: 0.15),
                          tokens.info.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: ZplayRadius.mdAll,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: tokens.success.withValues(alpha: 0.2),
                            borderRadius: ZplayRadius.mdAll,
                          ),
                          child: Icon(Icons.library_add_rounded, color: tokens.success, size: 26),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Upload Personal Audiobook Files',
                                style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Import your own .mp3, .m4b, .m4a, or .flac audiobooks to listen offline.',
                                style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: tokens.textSecondary, size: 24),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'IMPORTED AUDIOBOOKS (${books.length})',
                  style: ZplayType.overline
                      .copyWith(size: 12, weight: FontWeight.w700, letterSpacing: 1.1)
                      .toStyle(color: tokens.textMuted),
                ),
                const SizedBox(height: 10),

                if (books.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: ZplayRadius.mdAll,
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.library_music_rounded, size: 40, color: tokens.textDisabled),
                        const SizedBox(height: 12),
                        Text(
                          'No personal audiobooks added yet',
                          style: ZplayType.body
                              .copyWith(weight: FontWeight.w600)
                              .toStyle(color: tokens.textEmphasis),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap the banner above to import audio files from your device.',
                          style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  )
                else
                  ...books.map((b) => _buildUploadedBookCard(b)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildUploadedBookCard(UserUploadedAudiobook book) {
    final tokens = context.tokens;
    final sizeMb = (book.totalBytes / (1024 * 1024)).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
      ),
      child: Row(
        children: [
          // Cover
          Container(
            width: 48,
            height: 64,
            decoration: BoxDecoration(
              color: tokens.borderStrong,
              borderRadius: ZplayRadius.smAll,
            ),
            clipBehavior: Clip.antiAlias,
            child: book.coverPath != null && File(book.coverPath!).existsSync()
                ? Image.file(File(book.coverPath!), fit: BoxFit.cover)
                : Icon(Icons.music_note_rounded, color: tokens.textDisabled, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: ZplayType.body.copyWith(weight: FontWeight.w700).toStyle(color: tokens.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${book.author} • ${book.audioFilePaths.length} part(s) ($sizeMb MB)',
                  style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          PillButton(
            label: 'Play',
            icon: Icons.play_arrow_rounded,
            onPressed: () => _playUploadedAudiobook(book),
          ),
          const SizedBox(width: 6),
          FocusableInkWell(
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: tokens.surfaceOverlay,
                  shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.mdAll),
                  title: const Text('Delete Audiobook?'),
                  content: Text('Delete "${book.title}" from your library?'),
                  actions: [
                    PillButton(
                      label: 'Cancel',
                      variant: PillVariant.secondary,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    FocusableInkWell(
                      onTap: () => Navigator.pop(ctx, true),
                      borderRadius: ZplayRadius.smAll,
                      hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZplaySpacing.s12,
                          vertical: ZplaySpacing.s8,
                        ),
                        child: Text('Delete', style: ZplayType.label.toStyle(color: tokens.danger)),
                      ),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await _customService.deleteAudiobook(book.id);
                if (mounted) setState(() {});
              }
            },
            borderRadius: ZplayRadius.fullAll,
            hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.delete_outline_rounded, size: 18, color: tokens.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
