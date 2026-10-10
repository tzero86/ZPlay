import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/book/book_result.dart';
import '../../services/books/book_download_service.dart';
import '../../services/books/continue_reading_service.dart';
import '../audiobooks/generate_audiobook_screen.dart';
import 'epub_reader_page.dart';
import 'pdf_reader_page.dart';
import '../../services/storage/app_image_cache.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/focusable_card.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/common/section_header.dart';

class BookDetailSheet extends StatefulWidget {
  final BookResult book;

  const BookDetailSheet({
    super.key,
    required this.book,
  });

  static Future<void> show(BuildContext context, BookResult book) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BookDetailSheet(book: book),
    );
  }

  @override
  State<BookDetailSheet> createState() => _BookDetailSheetState();
}

class _BookDetailSheetState extends State<BookDetailSheet> {
  bool _isDownloaded = false;
  File? _downloadedFile;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _checkingStatus = true;

  @override
  void initState() {
    super.initState();
    _checkDownloadStatus();
  }

  Future<void> _checkDownloadStatus() async {
    final downloaded = await BookDownloadService.instance.getDownloadedBook(
      widget.book.md5,
      widget.book.bookFiletype,
    );
    if (!mounted) return;
    setState(() {
      _isDownloaded = downloaded != null;
      _downloadedFile = downloaded;
      _checkingStatus = false;
    });
  }

  Future<void> _startReadOrDownload() async {
    if (_isDownloaded && _downloadedFile != null) {
      _openReader(_downloadedFile!);
      return;
    }

    // Start download and open upon completion
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.01;
    });

    try {
      final file = await BookDownloadService.instance.downloadBook(
        widget.book,
        onProgress: (p) {
          if (mounted) {
            setState(() => _downloadProgress = p);
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _isDownloaded = file != null;
        _downloadedFile = file;
      });

      if (file != null) {
        _openReader(file);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download book: $e'),
          backgroundColor: context.tokens.danger,
        ),
      );
    }
  }

  void _openReader(File file) {
    Navigator.of(context).pop(); // Close sheet

    final progress = ContinueReadingService.getProgress(widget.book.md5);

    if (widget.book.isPdf) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => PdfReaderPage(
            file: file,
            book: widget.book,
            initialPage: progress?.currentPage ?? 1,
          ),
        ),
      );
    } else {
      // EPUB, FB2, MOBI, AZW3, TXT, CBZ, LIT, LRF all open in universal reader
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => EpubReaderPage(
            file: file,
            book: widget.book,
            initialChapterIndex: progress?.chapterIndex ?? 0,
            initialScrollOffset: progress?.scrollOffset ?? 0.0,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final book = widget.book;
    final progress = ContinueReadingService.getProgress(book.md5);
    final hasProgress = progress != null && progress.progressPercent > 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: ZplayRadius.sheetTop,
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 36,
            offset: Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(
                top: ZplaySpacing.s12,
                bottom: ZplaySpacing.s8,
              ),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: tokens.textDisabled,
                borderRadius: ZplayRadius.xsAll,
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                ZplaySpacing.s24,
                ZplaySpacing.s8,
                ZplaySpacing.s24,
                ZplaySpacing.s32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Cover + Metadata info
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Book Cover Card
                      Hero(
                        tag: 'book_cover_${book.md5}',
                        child: Container(
                          width: 124,
                          height: 180,
                          decoration: BoxDecoration(
                            borderRadius: ZplayRadius.mdAll,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: ZplayRadius.mdAll,
                            child: book.coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: book.coverUrl,
                                    cacheManager: AppImageCache.manager,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: tokens.surface,
                                      child: Center(
                                        child: Icon(Icons.menu_book_rounded, color: tokens.textDisabled, size: 36),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: tokens.surface,
                                      child: Center(
                                        child: Icon(Icons.menu_book_rounded, color: tokens.textDisabled, size: 36),
                                      ),
                                    ))
                                : Container(
                                    color: tokens.surface,
                                    child: Center(
                                      child: Icon(Icons.menu_book_rounded, color: tokens.textDisabled, size: 36),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s16),

                      // Title & Metadata
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              book.displayTitle,
                              style: ZplayType.title.toStyle(color: tokens.textPrimary),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: ZplaySpacing.s8),
                            Text(
                              book.displayAuthor,
                              style: ZplayType.body
                                  .copyWith(size: 13)
                                  .toStyle(color: tokens.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: ZplaySpacing.s12),

                            // One metadata line, not a row of filled chips.
                            // The sheet used to wear four badges whose only job
                            // was to name the format, the size, the year and the
                            // language; type weight and the interpunct carry
                            // that structure without four boxes competing with
                            // the cover for the eye.
                            Text(
                              [
                                book.bookFiletype.toUpperCase(),
                                if (book.bookSize.isNotEmpty) book.bookSize,
                                if (book.year.isNotEmpty) book.year,
                                if (book.bookLang.isNotEmpty) book.bookLang,
                              ].join(' · '),
                              style: ZplayType.label
                                  .toStyle(color: tokens.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZplaySpacing.s24),

                  // Reading progress, as a label and a bar. It used to be a
                  // bordered `tokens.surface` box; the numbers and the bar are
                  // the content, so the box around them was a second frame for
                  // no information.
                  if (hasProgress) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          progress.fileType == 'pdf'
                              ? 'Page ${progress.currentPage} of ${progress.totalPages}'
                              : 'Chapter ${progress.chapterIndex + 1} of ${progress.totalChapters}',
                          style: ZplayType.bodySmall
                              .copyWith(weight: FontWeight.w600)
                              .toStyle(color: tokens.textEmphasis),
                        ),
                        Text(
                          '${(progress.progressPercent * 100).round()}% Completed',
                          style: ZplayType.bodySmall
                              .copyWith(weight: FontWeight.bold)
                              .toStyle(color: tokens.accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: ZplaySpacing.s8),
                    ClipRRect(
                      borderRadius: ZplayRadius.xsAll,
                      child: LinearProgressIndicator(
                        value: progress.progressPercent,
                        backgroundColor: tokens.borderStrong,
                        color: tokens.accent,
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: ZplaySpacing.s20),
                  ],

                  // Actions. The primary is the app's one call-to-action shape
                  // (`PillButton`), which carries the single focus ring; the
                  // download percentage is in its label, so the spinner that
                  // used to sit inside the old Material button is gone with the
                  // accent-filled rectangle it lived in. The two glyph actions
                  // beside it are circular, ringed targets - a labelled pill for
                  // each would crowd a row that already carries the CTA.
                  Row(
                    children: [
                      Expanded(
                        child: PillButton(
                          label: _isDownloading
                              ? 'Downloading ${(_downloadProgress * 100).round()}%...'
                              : hasProgress
                                  ? 'Resume Reading'
                                  : 'Read Now',
                          icon: hasProgress
                              ? Icons.play_arrow_rounded
                              : Icons.auto_stories_rounded,
                          onPressed: _checkingStatus || _isDownloading
                              ? null
                              : _startReadOrDownload,
                          expand: true,
                        ),
                      ),

                      if (book.isEpub) ...[
                        const SizedBox(width: ZplaySpacing.s12),
                        _SheetIconAction(
                          icon: Icons.record_voice_over_rounded,
                          tooltip: 'Generate AI Audiobook (TTS)',
                          onTap: () async {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const GenerateAudiobookScreen()),
                            );
                          },
                        ),
                      ],

                      if (_isDownloaded) ...[
                        const SizedBox(width: ZplaySpacing.s12),
                        _SheetIconAction(
                          icon: Icons.delete_outline_rounded,
                          tooltip: 'Delete downloaded file',
                          danger: true,
                          onTap: () async {
                            await BookDownloadService.instance.deleteBook(
                              book.md5,
                              book.bookFiletype,
                            );
                            _checkDownloadStatus();
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: ZplaySpacing.s24),

                  // Metadata list. The rows were inside a bordered surface
                  // card; a definition list's rows are its content, so the box
                  // is gone and the shared section header names the group. The
                  // header bakes a 16 dp inset of its own - the translate
                  // cancels it, the same way the details pages do, so the
                  // heading lines up with the cover above it.
                  if (book.publisher.isNotEmpty || book.isbn.isNotEmpty || book.series.isNotEmpty) ...[
                    Transform.translate(
                      offset: const Offset(-ZplaySpacing.s16, 0),
                      child: const SectionHeader(title: 'Information'),
                    ),
                    const SizedBox(height: ZplaySpacing.s4),
                    if (book.publisher.isNotEmpty)
                      _buildInfoRow('Publisher', book.publisher),
                    if (book.series.isNotEmpty)
                      _buildInfoRow('Series', book.series),
                    if (book.isbn.isNotEmpty)
                      _buildInfoRow('ISBN', book.isbn),
                    if (book.bookLang.isNotEmpty)
                      _buildInfoRow('Language', book.bookLang),
                    _buildInfoRow('File Format', book.bookFiletype.toUpperCase()),
                    if (book.bookSize.isNotEmpty)
                      _buildInfoRow('Size', book.bookSize),
                    const SizedBox(height: ZplaySpacing.s16),
                  ],

                  // Description
                  if (book.description.isNotEmpty) ...[
                    Transform.translate(
                      offset: const Offset(-ZplaySpacing.s16, 0),
                      child: const SectionHeader(title: 'Overview'),
                    ),
                    const SizedBox(height: ZplaySpacing.s4),
                    Text(
                      book.description,
                      style: ZplayType.body
                          .copyWith(size: 13, height: 1.5)
                          .toStyle(color: tokens.textEmphasis),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
          ),
          Flexible(
            child: Text(
              value,
              style: ZplayType.bodySmall
                  .copyWith(weight: FontWeight.w500)
                  .toStyle(color: tokens.textPrimary),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// An icon-only action for the detail sheet: a circular scrim, the app's single
/// focus ring, and a target as tall as a pill, so a remote can land on it.
///
/// `PillButton` is the sheet's primary shape and is a label control by design;
/// these two are glyphs (a listening mode and a destructive tidy-up) beside a
/// CTA that already owns the row, so they keep their own box - a circle whose
/// fill *is* the button - rather than growing labels that would push the pill
/// off a phone.
class _SheetIconAction extends StatelessWidget {
  const _SheetIconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final side = PillButton.heightFor(context);
    final tint = danger ? tokens.danger : tokens.accent;

    return Tooltip(
      message: tooltip,
      child: FocusableCard(
        onTap: onTap,
        builder: (context, state) => SizedBox(
          width: side,
          height: side,
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.fullAll,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: state.highlighted ? tint : tokens.surfaceOverlay,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: state.highlighted ? tokens.onAccent : tint,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
