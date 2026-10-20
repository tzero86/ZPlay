import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../services/diagnostics/diagnostics_export.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/pill_button.dart';
import '../../widgets/settings/settings_app_bar.dart';

/// The Settings page for the local-only diagnostic report.
///
/// One page, two actions: copy the report, or save it as a timestamped JSON
/// file. Both call [DiagnosticsExport], which is injected here so the page's
/// own test drives the seam rather than the clipboard or the filesystem.
///
/// There is no "Clear breadcrumbs": [CrashBreadcrumbs] exposes its buffer
/// read-only on purpose (the only reset is `@visibleForTesting`), and a
/// diagnostics page that invented a public mutation just to have a third button
/// would be letting the UI dictate a service's contract.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, this.export});

  /// Test seam. Production reads [DiagnosticsExport.instance].
  final DiagnosticsExport? export;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  late final DiagnosticsExport _export =
      widget.export ?? DiagnosticsExport.instance;

  Map<String, Object?>? _report;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, Object?>? report;
    try {
      report = await _export.collect();
    } catch (error) {
      debugPrint('[DiagnosticsPage] could not build report: $error');
    }
    if (!mounted) return;
    setState(() => _report = report);
  }

  Future<void> _copy() async {
    try {
      final text = await _export.copyText();
      await Clipboard.setData(ClipboardData(text: text));
      _notify((l10n) => l10n.diagnosticsCopiedToClipboard);
    } catch (error) {
      debugPrint('[DiagnosticsPage] copy failed: $error');
      _notify((l10n) => l10n.diagnosticsCopyFailed);
    }
  }

  Future<void> _save() async {
    String? path;
    try {
      path = await _export.saveReport();
    } catch (error) {
      debugPrint('[DiagnosticsPage] save failed: $error');
    }
    if (!mounted) return;
    setState(() => _savedPath = path);
    _notify(
      path == null
          ? (l10n) => l10n.diagnosticsSaveFailed
          : (l10n) => l10n.diagnosticsSaved(path!),
    );
  }

  void _notify(String Function(AppLocalizations l10n) message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message(l10nOf(context)))));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = l10nOf(context);
    final report = _report;
    return AnimatedAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SettingsAppBar(title: l10n.diagnosticsTitle),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s16,
                vertical: ZplaySpacing.s20,
              ),
              children: [
                Text(
                  l10n.diagnosticsDescription,
                  style: ZplayType.body.toStyle(color: tokens.textSecondary),
                ),
                const SizedBox(height: ZplaySpacing.s20),
                if (report == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(ZplaySpacing.s32),
                      child: CircularProgressIndicator(color: tokens.accent),
                    ),
                  )
                else ...[
                  _sectionTitle(tokens, l10n.settingsSectionApp),
                  _summary(context, tokens, _rows(report['app'])),
                  const SizedBox(height: ZplaySpacing.s20),
                  _sectionTitle(tokens, l10n.diagnosticsSectionDevice),
                  _summary(context, tokens, _rows(report['device'])),
                  const SizedBox(height: ZplaySpacing.s20),
                  _sectionTitle(tokens, l10n.diagnosticsSectionPlayerEngine),
                  _summary(context, tokens, <({String label, String value})>[
                    ..._rows(report['player']),
                    ..._rows(report['streamEngine']),
                    ..._rows(report['iptv']),
                  ]),
                  const SizedBox(height: ZplaySpacing.s24),
                  Wrap(
                    spacing: ZplaySpacing.s12,
                    runSpacing: ZplaySpacing.s12,
                    children: [
                      PillButton(
                        label: l10n.actionCopyReport,
                        icon: Icons.copy_all_rounded,
                        onPressed: _copy,
                      ),
                      PillButton(
                        label: l10n.actionSaveReport,
                        icon: Icons.save_alt_rounded,
                        variant: PillVariant.secondary,
                        onPressed: _save,
                      ),
                    ],
                  ),
                  if (_savedPath != null) ...[
                    const SizedBox(height: ZplaySpacing.s12),
                    SelectableText(
                      l10n.diagnosticsSaved(_savedPath!),
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: ZplaySpacing.s24),
                  _breadcrumbs(context, tokens, report['breadcrumbs']),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(ZplayTokens tokens, String title) => Padding(
    padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
    child: Text(
      title,
      style: ZplayType.overline.toStyle(color: tokens.textMuted),
    ),
  );

  Widget _summary(
    BuildContext context,
    ZplayTokens tokens,
    List<({String label, String value})> rows,
  ) {
    if (rows.isEmpty) {
      return Text(
        l10nOf(context).diagnosticsNotAvailable,
        style: ZplayType.body.toStyle(color: tokens.textMuted),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s16,
        vertical: ZplaySpacing.s12,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: ZplayRadius.smAll,
        border: Border.fromBorderSide(tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 168,
                    child: Text(
                      row.label,
                      style: ZplayType.bodySmall.toStyle(
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: ZplayType.body.toStyle(color: tokens.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Flattens a report section into labelled rows.
  ///
  /// Nested sections (`streamEngine`) are flattened one level deep; the leaf
  /// values are printed as-is, because the report is already redacted by the
  /// time it reaches the page.
  List<({String label, String value})> _rows(Object? section) {
    if (section is! Map) return const <({String label, String value})>[];
    final rows = <({String label, String value})>[];
    for (final entry in section.entries) {
      final value = entry.value;
      if (value is Map) {
        rows.addAll(_rows(value));
        continue;
      }
      rows.add((
        label: _labelOf('${entry.key}'),
        value: value == null ? '—' : '$value',
      ));
    }
    return rows;
  }

  Widget _breadcrumbs(
    BuildContext context,
    ZplayTokens tokens,
    Object? section,
  ) {
    final l10n = l10nOf(context);
    final map = section is Map ? section : const <Object?, Object?>{};
    final entries = map['entries'] is List
        ? (map['entries']! as List)
        : const <Object?>[];
    final count = map['count'] ?? 0;
    final lines = <String>[
      for (final entry in entries)
        if (entry is Map)
          '[${entry['at']}][${entry['category']}] ${entry['message']}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(tokens, l10n.diagnosticsSectionBreadcrumbs),
        Text(
          l10n.diagnosticsBreadcrumbCount(
            count is int ? count : 0,
            lines.length,
          ),
          style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
        ),
        const SizedBox(height: ZplaySpacing.s8),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(ZplaySpacing.s12),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: ZplayRadius.smAll,
            border: Border.fromBorderSide(tokens.hairline),
          ),
          child: lines.isEmpty
              ? Text(
                  l10n.diagnosticsEmpty,
                  style: ZplayType.body.toStyle(color: tokens.textMuted),
                )
              : SingleChildScrollView(
                  child: SelectableText(
                    lines.join('\n'),
                    style: ZplayType.bodySmall
                        .toStyle(color: tokens.textSecondary)
                        .copyWith(fontFamily: 'monospace'),
                  ),
                ),
        ),
      ],
    );
  }

  /// `operatingSystemVersion` -> `Operating system version`.
  static String _labelOf(String key) {
    if (key.isEmpty) return key;
    final spaced = key.replaceAllMapped(
      RegExp(r'(?<=[a-z0-9])([A-Z])'),
      (match) => ' ${match[1]!.toLowerCase()}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}
