import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/config/service_credentials.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/player/player_glass.dart';
import '../../widgets/settings/settings_app_bar.dart';
import 'tmdb_settings_page.dart';

/// Bring-your-own keys for the third-party services ZPlay talks to. A saved
/// value is never read back into its field: only the fact that one exists is
/// shown, so a credential cannot be recovered from this screen.
class ServiceKeysSettingsPage extends StatefulWidget {
  const ServiceKeysSettingsPage({super.key});

  @override
  State<ServiceKeysSettingsPage> createState() =>
      _ServiceKeysSettingsPageState();
}

class _ServiceKeysSettingsPageState extends State<ServiceKeysSettingsPage> {
  final Map<ServiceCredential, TextEditingController> _controllers = {
    for (final credential in ServiceCredential.values)
      credential: TextEditingController(),
  };
  final Map<ServiceCredential, bool> _obscured = {
    for (final credential in ServiceCredential.values) credential: true,
  };
  final Map<ServiceCredential, bool> _busy = {
    for (final credential in ServiceCredential.values) credential: false,
  };

  @override
  void initState() {
    super.initState();
    ServiceCredentials.initialize();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
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

  /// What the credential unlocks, read as a plain sentence in the row.
  String _purposeOf(ServiceCredential credential) {
    switch (credential) {
      case ServiceCredential.wyzie:
        return 'Searches the Wyzie subtitle catalogue for movies and episodes.';
      case ServiceCredential.audiobookSearch:
        return 'Mints the anonymous token the Audionest audiobook search API requires.';
      case ServiceCredential.audiobookService:
        return 'Bearer for the Audionest audiobook search endpoint.';
      case ServiceCredential.paper2audio:
        return 'Firebase key for the paper2audio PDF to audiobook backend.';
      case ServiceCredential.vidgod:
        return 'Bearer for the VidGod cloud cache behind ZPlayHTTP streams.';
      case ServiceCredential.xdownloader:
        return 'Bearer for the Films365 direct stream API.';
      case ServiceCredential.trakt:
        return 'Identifies the Trakt application the pairing flow asks for a '
            'device code on, and stamps every Trakt API call.';
      case ServiceCredential.traktSecret:
        return 'Exchanges the device code for a Trakt access token.';
    }
  }

  /// Which rung of the ladder is currently supplying the credential.
  String _sourceText(CredentialSource source) {
    switch (source) {
      case CredentialSource.user:
        return 'Your key is in use.';
      case CredentialSource.buildTime:
        return 'Supplied at build time for this build.';
      case CredentialSource.inherited:
        return 'Running on the value this app ships with.';
      case CredentialSource.none:
        return 'No key available, so this source stays off.';
    }
  }

  IconData _sourceIcon(CredentialSource source) {
    switch (source) {
      case CredentialSource.user:
        return Icons.check_circle_rounded;
      case CredentialSource.buildTime:
        return Icons.construction_rounded;
      case CredentialSource.inherited:
        return Icons.history_rounded;
      case CredentialSource.none:
        return Icons.block_rounded;
    }
  }

  Future<void> _save(ServiceCredential credential) async {
    final controller = _controllers[credential]!;
    final label = ServiceCredentials.labelFor(credential);
    final key = _sanitizeKey(controller.text);
    if (key.isEmpty) {
      _showSnack('Paste a key for $label first.', isError: true);
      return;
    }

    setState(() => _busy[credential] = true);
    await ServiceCredentials.save(credential, key);
    if (!mounted) return;
    controller.clear();
    setState(() {
      _busy[credential] = false;
      _obscured[credential] = true;
    });
    _showSnack('$label key saved and now in use.');
  }

  Future<void> _clear(ServiceCredential credential) async {
    final label = ServiceCredentials.labelFor(credential);
    _controllers[credential]!.clear();
    await ServiceCredentials.clear(credential);
    if (!mounted) return;
    setState(() => _obscured[credential] = true);
    _showSnack('$label key cleared.');
  }

  Future<void> _paste(ServiceCredential credential) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    if (!mounted) return;
    _controllers[credential]!.text = _sanitizeKey(text);
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final userObtainable = [
      for (final credential in ServiceCredential.values)
        if (ServiceCredentials.isUserObtainable(credential)) credential,
    ];
    final borrowed = [
      for (final credential in ServiceCredential.values)
        if (!ServiceCredentials.isUserObtainable(credential)) credential,
    ];

    return AnimatedAmbientBackground(child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SettingsAppBar(
        title: 'Service API Keys',
      ),
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
                  'ZPlay talks to several third-party services. Any key you save '
                  'here replaces the one this build uses and takes effect '
                  'immediately, with no restart.',
                  style: ZplayType.body.toStyle(color: tokens.textSecondary),
                ),
              ),

              Text(
                'KEYS YOU CAN OBTAIN',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 10),
              for (final credential in userObtainable) ...[
                _buildCredentialCard(credential),
                const SizedBox(height: ZplaySpacing.s12),
              ],

              const SizedBox(height: ZplaySpacing.s12),
              Text(
                'BORROWED CREDENTIALS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                'These cannot be obtained: each is a credential for a '
                'third-party service that did not issue it to ZPlay, so leave '
                'its field blank unless you have your own. A private build can '
                'supply its own with --dart-define, and blanking the registry '
                'entry in the source disables only that one source.',
                style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: 10),
              for (final credential in borrowed) ...[
                _buildCredentialCard(credential),
                const SizedBox(height: ZplaySpacing.s12),
              ],

              Text(
                'Every value is stored only on this device and is never shown '
                'back in these fields.',
                style: ZplayType.bodySmall.toStyle(color: tokens.textDisabled),
              ),

              const SizedBox(height: ZplaySpacing.s24),
              Text(
                'RELATED',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 10),
              _buildTmdbRow(tokens),

              const SizedBox(height: ZplaySpacing.s20),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildCredentialCard(ServiceCredential credential) {
    final tokens = context.tokens;
    final label = ServiceCredentials.labelFor(credential);
    final controller = _controllers[credential]!;
    final obscured = _obscured[credential] ?? true;
    final busy = _busy[credential] == true;

    return ListenableBuilder(
      listenable: ServiceCredentials.notifier(credential),
      builder: (context, _) {
        final isUserProvided = ServiceCredentials.isUserProvided(credential);
        final source = ServiceCredentials.sourceFor(credential);
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    label,
                    style: ZplayType.subtitle.toStyle(
                      color: tokens.textPrimary,
                    ),
                  ),
                  if (isUserProvided)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
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
                _purposeOf(credential),
                style: ZplayType.bodySmall.toStyle(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ServiceCredentials.sourceHintFor(credential),
                style: ZplayType.bodySmall.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      obscureText: obscured,
                      enableSuggestions: false,
                      autocorrect: false,
                      style: ZplayType.label.toStyle(color: tokens.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Paste your $label key',
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
                                obscured
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: tokens.textMuted,
                                size: 16,
                              ),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              tooltip: obscured ? 'Show Key' : 'Hide Key',
                              onPressed: () {
                                setState(() {
                                  _obscured[credential] = !obscured;
                                });
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
                              onPressed: () => _paste(credential),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s8),
                  ElevatedButton(
                    onPressed: busy ? null : () => _save(credential),
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
                    child: busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.onAccent,
                            ),
                          )
                        : Text('Save', style: ZplayType.label.toStyle()),
                  ),
                ],
              ),
              const SizedBox(height: ZplaySpacing.s8),
              Row(
                children: [
                  Icon(
                    _sourceIcon(source),
                    size: 14,
                    color: source == CredentialSource.user
                        ? tokens.success
                        : tokens.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _sourceText(source),
                      style: ZplayType.bodySmall.toStyle(
                        color: source == CredentialSource.user
                            ? tokens.success
                            : tokens.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: ZplaySpacing.s8),
                  TextButton(
                    onPressed: isUserProvided && !busy
                        ? () => _clear(credential)
                        : null,
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
      },
    );
  }

  Widget _buildTmdbRow(ZplayTokens tokens) {
    return FocusableInkWell(
      borderRadius: ZplayRadius.mdAll,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TmdbSettingsPage()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.theaters_rounded, color: tokens.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TMDb API Key',
                    style: ZplayType.subtitle.toStyle(
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Ranks the 1990s rails and covers the scraper metadata lookups.',
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }
}
