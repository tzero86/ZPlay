import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/collections/collections_service.dart';
import '../../services/metadata/tmdb_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/settings/settings_app_bar.dart';

/// Bring-your-own TMDb key page. The key is never echoed back into the field
/// and is only persisted after TMDb accepts it.
class TmdbSettingsPage extends StatefulWidget {
  const TmdbSettingsPage({super.key});

  @override
  State<TmdbSettingsPage> createState() => _TmdbSettingsPageState();
}

class _TmdbSettingsPageState extends State<TmdbSettingsPage> {
  static const String _attributionNotice =
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';

  final _keyCtrl = TextEditingController();
  bool _obscured = true;
  bool _busy = false;
  TmdbKeyResult? _result;

  @override
  void initState() {
    super.initState();
    TmdbService.initialize();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  String _sanitizeKey(String raw) {
    var s = raw.trim();
    if (s.startsWith('Bearer ')) s = s.substring(7).trim();
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  String _statusText(TmdbKeyResult result) {
    switch (result) {
      case TmdbKeyResult.ok:
        return 'Connected';
      case TmdbKeyResult.rejected:
        return 'That key was rejected by TMDb';
      case TmdbKeyResult.unreachable:
        return 'Could not reach TMDb';
    }
  }

  Color _statusColor(TmdbKeyResult result) {
    final tokens = context.tokens;
    switch (result) {
      case TmdbKeyResult.ok:
        return tokens.success;
      case TmdbKeyResult.rejected:
        return tokens.danger;
      case TmdbKeyResult.unreachable:
        return tokens.warning;
    }
  }

  Future<void> _saveAndTest() async {
    final key = _sanitizeKey(_keyCtrl.text);
    if (key.isEmpty) {
      _showSnack('Paste a TMDb API key first.', isError: true);
      return;
    }

    setState(() {
      _busy = true;
      _result = null;
    });

    final result = await TmdbService.validate(key);

    if (!mounted) return;

    if (result == TmdbKeyResult.ok) {
      await TmdbService.save(key);
      // A re-saved identical key does not notify the notifier, so ask the
      // ranked rails to reload; this joins an in-flight load for the same key.
      unawaited(CollectionsService.applyRanked());
      if (!mounted) return;
      _keyCtrl.clear();
      setState(() {
        _busy = false;
        _result = result;
        _obscured = true;
      });
      _showSnack('TMDb key saved. The 1990s rails now use TMDb ranks.');
    } else {
      setState(() {
        _busy = false;
        _result = result;
      });
    }
  }

  Future<void> _clearKey() async {
    await TmdbService.clear();
    if (!mounted) return;
    _keyCtrl.clear();
    setState(() {
      _result = null;
      _obscured = true;
    });
    _showSnack('TMDb key cleared. The built-in 1990s picks are back.');
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    if (!mounted) return;
    _keyCtrl.text = _sanitizeKey(text);
    setState(() {});
    _showSnack('Pasted key from clipboard.');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final tokens = context.tokens;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: ZplayType.subtitle.toStyle()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? tokens.danger : tokens.accent,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: tokens.onAccent,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const SettingsAppBar(title: 'TMDb API Key'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s20,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: ZplaySpacing.s20),
                child: Text(
                  'Add your own free TMDb key to rank the six "The 90s" rails by '
                  'TMDb vote counts, and to cover the TMDb lookups the built-in '
                  'scrapers make. Get a key at themoviedb.org.',
                  style: ZplayType.body.toStyle(color: tokens.textSecondary),
                ),
              ),

              Text(
                'TMDB CREDENTIAL',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 10),

              ListenableBuilder(
                listenable: TmdbService.apiKey,
                builder: (context, _) => _buildCredentialCard(context),
              ),

              const SizedBox(height: ZplaySpacing.s12),

              Text(
                'The key is stored only on this device. This app ships with no '
                'key, and a built-in fallback keeps the scraper lookups working '
                'without one. Clearing your key restores the built-in 1990s picks.',
                style: ZplayType.bodySmall.toStyle(color: tokens.textDisabled),
              ),

              const SizedBox(height: ZplaySpacing.s24),

              Text(
                'CREDITS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: ZplaySpacing.s12),

              _buildAttributionCard(context),

              const SizedBox(height: ZplaySpacing.s20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCredentialCard(BuildContext context) {
    final tokens = context.tokens;
    final hasKey = TmdbService.isConfigured;
    final result = _result;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.all(
          color: hasKey
              ? tokens.accent.withValues(alpha: ZplayOpacity.borderStrong)
              : tokens.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'TMDb API Key',
                style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
              ),
              if (hasKey)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(
                      alpha: ZplayOpacity.borderStrong,
                    ),
                    borderRadius: ZplayRadius.xsAll,
                  ),
                  child: Text(
                    'SAVED',
                    style: ZplayType.caption.toStyle(color: tokens.accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            hasKey
                ? 'Saved on this device. Enter a new key to replace it.'
                : 'Free key from themoviedb.org',
            style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyCtrl,
                  obscureText: _obscured,
                  enableSuggestions: false,
                  autocorrect: false,
                  style: ZplayType.label.toStyle(color: tokens.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Paste your TMDb API key',
                    hintStyle: ZplayType.bodySmall.toStyle(
                      color: tokens.textDisabled,
                    ),
                    filled: true,
                    fillColor: tokens.bg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: ZplayRadius.smAll,
                      borderSide: BorderSide(color: tokens.borderDefault),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: ZplayRadius.smAll,
                      borderSide: BorderSide(color: tokens.borderDefault),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: ZplayRadius.smAll,
                      borderSide: BorderSide(color: tokens.accent),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscured
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: tokens.textMuted,
                            size: 16,
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: _obscured ? 'Show Key' : 'Hide Key',
                          onPressed: () {
                            setState(() => _obscured = !_obscured);
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.content_paste_rounded,
                            color: tokens.accent,
                            size: 16,
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: 'Paste from Clipboard',
                          onPressed: _pasteFromClipboard,
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: ZplaySpacing.s8),
              ElevatedButton(
                onPressed: _busy ? null : _saveAndTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.onAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: ZplayRadius.smAll,
                  ),
                  elevation: 0,
                ),
                child: _busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.onAccent,
                        ),
                      )
                    : Text('Save and test', style: ZplayType.label.toStyle()),
              ),
            ],
          ),
          const SizedBox(height: ZplaySpacing.s8),
          Row(
            children: [
              Expanded(
                child: Text(
                  result == null
                      ? (hasKey
                            ? 'A key is saved. Run a test to confirm it still works.'
                            : 'No key saved yet, so the built-in picks are in use.')
                      : _statusText(result),
                  style: ZplayType.bodySmall.toStyle(
                    color: result == null
                        ? tokens.textMuted
                        : _statusColor(result),
                  ),
                ),
              ),
              const SizedBox(width: ZplaySpacing.s8),
              TextButton(
                onPressed: hasKey && !_busy ? _clearKey : null,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.danger,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: ZplaySpacing.s4,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: ZplayRadius.smAll,
                  ),
                ),
                child: Text('Clear key', style: ZplayType.label.toStyle()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttributionCard(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        border: Border.fromBorderSide(tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/branding/tmdb-logo.png',
            height: 22,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (context, error, stackTrace) => Text(
              'TMDB',
              style: ZplayType.label.toStyle(color: tokens.textPrimary),
            ),
          ),
          const SizedBox(height: ZplaySpacing.s12),
          Text(
            _attributionNotice,
            style: ZplayType.bodySmall
                .toStyle(color: tokens.textSecondary)
                .copyWith(height: 1.35),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _openUrl('https://www.themoviedb.org'),
            borderRadius: ZplayRadius.xsAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s4),
              child: Text(
                'themoviedb.org',
                style: ZplayType.label.toStyle(
                  color: tokens.accent,
                  decoration: TextDecoration.underline,
                  decorationColor: tokens.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
