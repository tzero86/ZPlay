import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../services/theme/design_tokens.dart';
import '../../services/updater/app_updater_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  StreamSubscription? _otaSub;

  @override
  void dispose() {
    _otaSub?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Already reduced to the changelog section and stripped of Markdown by the
    // service; this is the last empty-body guard before the box renders.
    final releaseNotes = widget.updateInfo.releaseNotesForDisplay.trim();
    return PopScope(
      canPop: !_isDownloading,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && !_isDownloading) {
          AppUpdaterService.dismissVersion(widget.updateInfo.latestVersion);
        }
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: ZplayRadius.lgAll,
            border: Border.all(
              color: tokens.accent.withValues(alpha: ZplayOpacity.textDisabled),
              width: 1.5,
            ),
          boxShadow: [
            BoxShadow(
              color: tokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
              blurRadius: 40,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with gradient
            Container(
              padding: const EdgeInsets.all(ZplaySpacing.s24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    tokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
                    tokens.accent.withValues(alpha: ZplayOpacity.borderFaint),
                  ],
                ),
                borderRadius: ZplayRadius.sheetTop,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(ZplaySpacing.s12),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: ZplayOpacity.overlayHover),
                      borderRadius: ZplayRadius.smAll,
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      color: tokens.accent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'UPDATE AVAILABLE',
                          style: ZplayType.overline.toStyle(color: tokens.accent),
                        ),
                        const SizedBox(height: ZplaySpacing.s4),
                        Text(
                          'Version ${widget.updateInfo.latestVersion}',
                          style: ZplayType.titleLarge.toStyle(
                            color: tokens.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(ZplaySpacing.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Version details container
                  Container(
                    padding: const EdgeInsets.all(ZplaySpacing.s16),
                    decoration: BoxDecoration(
                      color: tokens.borderSubtle,
                      borderRadius: ZplayRadius.smAll,
                      border: Border.fromBorderSide(tokens.hairline),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current',
                              style: ZplayType.caption.toStyle(
                                color: tokens.textMuted,
                              ),
                            ),
                            const SizedBox(height: ZplaySpacing.s4),
                            Text(
                              widget.updateInfo.currentVersion,
                              style: ZplayType.subtitle.toStyle(
                                color: tokens.textEmphasis,
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: tokens.accent,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Latest',
                              style: ZplayType.caption.toStyle(
                                color: tokens.textMuted,
                              ),
                            ),
                            const SizedBox(height: ZplaySpacing.s4),
                            Text(
                              widget.updateInfo.latestVersion,
                              style: ZplayType.subtitle.toStyle(
                                color: tokens.accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: ZplaySpacing.s20),

                  // Release notes header & box
                  Text(
                    "WHAT'S NEW",
                    style: ZplayType.overline.toStyle(color: tokens.textMuted),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(ZplaySpacing.s16),
                    decoration: BoxDecoration(
                      color: tokens.bg.withValues(alpha: ZplayOpacity.textSecondary),
                      borderRadius: ZplayRadius.smAll,
                      border: Border.fromBorderSide(tokens.hairline),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        releaseNotes.isEmpty
                            ? 'No release notes were published for this version.'
                            : releaseNotes,
                        style: ZplayType.body.toStyle(
                          color: releaseNotes.isEmpty
                              ? tokens.textMuted
                              : tokens.textEmphasis,
                        ),
                      ),
                    ),
                  ),

                  if (widget.updateInfo.isMacOS || widget.updateInfo.isIOS) ...[
                    const SizedBox(height: ZplaySpacing.s16),
                    Container(
                      padding: const EdgeInsets.all(ZplaySpacing.s12),
                      decoration: BoxDecoration(
                        color: tokens.warning.withValues(alpha: ZplayOpacity.borderMedium),
                        borderRadius: ZplayRadius.smAll,
                        border: Border.all(
                          color: tokens.warning.withValues(alpha: ZplayOpacity.textDisabled),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: tokens.warning,
                            size: 20,
                          ),
                          const SizedBox(width: ZplaySpacing.s12),
                          Expanded(
                            child: Text(
                              widget.updateInfo.isIOS
                                  ? "iOS: You'll be redirected to GitHub to download the IPA"
                                  : "macOS: You'll be redirected to GitHub to download",
                              style: ZplayType.bodySmall.toStyle(
                                color: tokens.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_isDownloading) ...[
                    const SizedBox(height: ZplaySpacing.s20),
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Downloading...',
                              style: ZplayType.label.toStyle(color: tokens.accent),
                            ),
                            Text(
                              '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                              style: ZplayType.labelNumeric.toStyle(
                                color: tokens.textEmphasis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: ZplaySpacing.s8),
                        ClipRRect(
                          borderRadius: ZplayRadius.smAll,
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                            backgroundColor: tokens.borderStrong,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              tokens.accent,
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Buttons
            if (!_isDownloading)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZplaySpacing.s24,
                  ZplaySpacing.s0,
                  ZplaySpacing.s24,
                  ZplaySpacing.s24,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          AppUpdaterService.dismissVersion(widget.updateInfo.latestVersion);
                          Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: ZplaySpacing.s16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: ZplayRadius.smAll,
                            side: tokens.hairlineStrong,
                          ),
                        ),
                        child: Text(
                          'Later',
                          style: ZplayType.label.toStyle(
                            color: tokens.textEmphasis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: ZplaySpacing.s12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _handleUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.onAccent,
                          padding: const EdgeInsets.symmetric(
                            vertical: ZplaySpacing.s16,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: ZplayRadius.smAll,
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Update Now',
                              style: ZplayType.label.toStyle(),
                            ),
                            const SizedBox(width: ZplaySpacing.s8),
                            const Icon(Icons.download_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _handleUpdate() async {
    if (kIsWeb) {
      await AppUpdaterService().openDownloadPage(widget.updateInfo.downloadUrl);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (Platform.isAndroid) {
      await _downloadAndInstallAndroid();
    } else if (Platform.isWindows || Platform.isLinux) {
      await _downloadAndInstallDesktop();
    } else {
      // macOS / iOS - open browser
      await AppUpdaterService().openDownloadPage(widget.updateInfo.downloadUrl);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _downloadAndInstallAndroid() async {
    WakelockPlus.enable();
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      _otaSub = OtaUpdate()
          .execute(
            widget.updateInfo.downloadUrl,
            destinationFilename:
                'ZPlay_${widget.updateInfo.latestVersion}.apk',
          )
          .listen(
            (OtaEvent event) {
              if (mounted) {
                setState(() {
                  switch (event.status) {
                    case OtaStatus.DOWNLOADING:
                      final value = event.value;
                      if (value != null) {
                        final numVal = num.tryParse(value.toString()) ?? 0;
                        _downloadProgress = (numVal / 100.0).clamp(0.0, 1.0);
                      }
                      break;
                    case OtaStatus.INSTALLING:
                      _downloadProgress = 1.0;
                      WakelockPlus.disable();
                      break;
                    case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                      _isDownloading = false;
                      WakelockPlus.disable();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Please enable "Install unknown apps" permission for ZPlay in Android settings.',
                          ),
                          duration: const Duration(seconds: 5),
                          backgroundColor: context.tokens.warning,
                        ),
                      );
                      Navigator.of(context).pop();
                      break;
                    case OtaStatus.ALREADY_RUNNING_ERROR:
                    case OtaStatus.INTERNAL_ERROR:
                    case OtaStatus.DOWNLOAD_ERROR:
                    case OtaStatus.CHECKSUM_ERROR:
                      _isDownloading = false;
                      WakelockPlus.disable();
                      _reportAndroidInstallFailure(
                        'Update failed: ${event.status}',
                      );
                      Navigator.of(context).pop();
                      break;
                    default:
                      break;
                  }
                });
              }
            },
            onError: (error) {
              WakelockPlus.disable();
              if (mounted) {
                setState(() => _isDownloading = false);
                _reportAndroidInstallFailure('Download failed: $error');
              }
            },
          );
    } catch (e) {
      WakelockPlus.disable();
      if (mounted) {
        setState(() => _isDownloading = false);
        _reportAndroidInstallFailure('Update failed: $e');
      }
    }
  }

  /// Reports a failed Android install or download exactly once.
  ///
  /// Android refuses to install an APK signed with a different key than the
  /// installed copy, and ota_update surfaces that refusal as a bare status or
  /// platform exception. Without the hint the user reads "Update failed: …" and
  /// has no way to know a one-time uninstall is the fix. The hint lives here
  /// rather than in the dialog so it rides along with every Android failure
  /// path, and the current snackbar is replaced instead of queued so a failure
  /// that trips both the event stream and the error channel cannot stack the
  /// hint twice.
  void _reportAndroidInstallFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$message\n\n'
            'The install can fail with "App not installed as package conflicts '
            'with an existing package" when the previously installed copy was '
            'signed with a different key. Uninstall that copy once and install '
            'again; export your settings first from Settings → Backup & Restore '
            '(JSON) to keep them.',
          ),
          duration: const Duration(seconds: 10),
          backgroundColor: context.tokens.danger,
        ),
      );
  }

  Future<void> _downloadAndInstallDesktop() async {
    WakelockPlus.enable();
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      Directory? downloadsDir;
      try {
        downloadsDir = await getDownloadsDirectory();
      } catch (_) {
        downloadsDir = null;
      }
      final dir = downloadsDir ?? await getTemporaryDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final extension = Platform.isWindows ? '.exe' : '.AppImage';
      final fileName =
          'ZPlay-${widget.updateInfo.latestVersion}$extension';
      final filePath = path.join(dir.path, fileName);
      final file = File(filePath);

      final request = http.Request(
        'GET',
        Uri.parse(widget.updateInfo.downloadUrl),
      );
      final response = await request.send();

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;
      int lastUpdateTime = DateTime.now().millisecondsSinceEpoch;

      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        final now = DateTime.now().millisecondsSinceEpoch;
        if (contentLength > 0 &&
            mounted &&
            (now - lastUpdateTime > 100 || downloadedBytes == contentLength)) {
          lastUpdateTime = now;
          final progress = downloadedBytes / contentLength;
          setState(() {
            _downloadProgress = progress;
          });
        }
      }

      await sink.close();
      final installer = File(filePath);

      if (mounted) {
        WakelockPlus.disable();
        setState(() => _isDownloading = false);

        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: context.tokens.surfaceOverlay,
            title: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: context.tokens.success,
                  size: 32,
                ),
                const SizedBox(width: ZplaySpacing.s12),
                Text(
                  'Download Complete',
                  style: ZplayType.title.toStyle(
                    color: context.tokens.textPrimary,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Platform.isWindows
                      ? 'ZPlay will close and install the update.'
                      : 'Update downloaded to:',
                  style: ZplayType.body.toStyle(
                    color: context.tokens.textEmphasis,
                  ),
                ),
                if (!Platform.isWindows) ...[
                  const SizedBox(height: ZplaySpacing.s8),
                  Container(
                    padding: const EdgeInsets.all(ZplaySpacing.s12),
                    decoration: BoxDecoration(
                      color: context.tokens.bg.withValues(
                        alpha: ZplayOpacity.textSecondary,
                      ),
                      borderRadius: ZplayRadius.smAll,
                    ),
                    child: SelectableText(
                      filePath,
                      style: ZplayType.bodySmall
                          .toStyle(color: context.tokens.accent)
                          .copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(height: ZplaySpacing.s16),
                  Text(
                    'Make the file executable and run it:\nchmod +x "$fileName"\n./$fileName',
                    style: ZplayType.body.toStyle(
                      color: context.tokens.textEmphasis,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!Platform.isWindows)
                TextButton(
                  onPressed: () async {
                    if (Platform.isLinux) {
                      await Process.run('xdg-open', [dir.path]);
                    }
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(
                    'Open Folder',
                    style: ZplayType.label.toStyle(
                      color: context.tokens.textEmphasis,
                    ),
                  ),
                ),
              ElevatedButton(
                onPressed: () async {
                  if (Platform.isWindows) {
                    await Process.start(
                      installer.path,
                      const [],
                      mode: ProcessStartMode.detached,
                    );
                    await Future.delayed(const Duration(seconds: 2));
                    exit(0);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.tokens.accent,
                  foregroundColor: context.tokens.onAccent,
                ),
                child: Text(
                  Platform.isWindows ? 'Close and install now' : 'OK',
                ),
              ),
            ],
          ),
        );

        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      WakelockPlus.disable();
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }
}
