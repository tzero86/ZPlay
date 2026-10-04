import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/trakt/trakt_constants.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/settings/settings_app_bar.dart';

/// Trakt's brand red. It identifies the external service, so it stays outside
/// the palette-derived token layer.
const Color _traktBrand = Color(0xFFED1C24);

class TraktSettingsPage extends StatefulWidget {
  const TraktSettingsPage({super.key});

  @override
  State<TraktSettingsPage> createState() => _TraktSettingsPageState();
}

class _TraktSettingsPageState extends State<TraktSettingsPage> {
  bool _isAuthed = false;
  bool _isLoading = true;
  String? _username;

  // Device Code Pairing
  bool _pairing = false;
  String? _userCode;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);
    final authed = await TraktService.instance.isAuthenticated();
    String? user;
    if (authed) {
      user = await TraktService.instance.getUsername();
    }
    if (mounted) {
      setState(() {
        _isAuthed = authed;
        _username = user;
        _isLoading = false;
      });
    }
  }

  Future<void> _startPairing() async {
    // Trakt answers `POST /oauth/device/code` with a 400 when `client_id` is
    // empty, so without this the flow cannot even start and the page can only
    // report that it failed - which is exactly what "it errors out and does not
    // even start the process" was. Trakt issues an application id per app and no
    // shared one can be committed, so the id is the user's to supply; this says
    // so and says where.
    if (kTraktClientId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Trakt needs a Client ID before it can pair. Create a free app at '
            'trakt.tv/oauth/applications, then paste its Client ID and Client '
            'Secret in Settings > Service API Keys.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _pairing = true;
      _userCode = null;
    });

    final res = await TraktService.instance.requestDeviceCode();
    if (!mounted) return;
    if (res == null) {
      setState(() => _pairing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Trakt rejected the pairing request. Check the Client ID and Client '
            'Secret in Settings > Service API Keys.',
          ),
        ),
      );
      return;
    }

    final userCode = res['user_code'] as String? ?? '';
    final deviceCode = res['device_code'] as String? ?? '';
    final verifyUrl = res['verification_url'] as String? ?? 'https://trakt.tv/activate';
    final interval = (res['interval'] as int? ?? 5).clamp(2, 30);

    setState(() {
      _userCode = userCode;
    });

    // Auto-launch URL
    _openBrowser(verifyUrl);

    // Start Polling
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: interval), (t) async {
      final status = await TraktService.instance.pollDeviceToken(deviceCode);
      if (status == null) {
        // Success!
        t.cancel();
        if (mounted) {
          setState(() {
            _pairing = false;
            _isAuthed = true;
          });
          _checkStatus();
          MyListService.syncAll();
          ContinueWatchingService.syncCloudSessions();
        }
      } else if (status == 'expired_token' || status == 'access_denied') {
        t.cancel();
        if (mounted) {
          setState(() => _pairing = false);
        }
      }
    });
  }

  Future<void> _openBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        final uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (e) {
        debugPrint('[Trakt] Browser launch error: $e');
      }
    }
  }

  Future<void> _logout() async {
    _pollTimer?.cancel();
    await TraktService.instance.logout();
    await _checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const SettingsAppBar(title: 'Trakt.tv Synchronization'),
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
                  'Connect your Trakt.tv account to seamlessly synchronize your watch history, watchlist, continue watching progress, and ratings across all your devices.',
                  style: ZplayType.body.toStyle(color: tokens.textSecondary),
                ),
              ),

              // Status Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: ZplayRadius.mdAll,
                  border: Border.all(
                    color: _isAuthed
                        ? _traktBrand.withValues(alpha: ZplayOpacity.textMuted)
                        : tokens.borderDefault,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 460;

                    final infoWidget = Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _traktBrand.withValues(alpha: ZplayOpacity.borderStrong),
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: const Icon(Icons.movie_filter_rounded, color: _traktBrand, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'Trakt.tv',
                                    style: ZplayType.subtitle.toStyle(color: tokens.textPrimary),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s8, vertical: ZplaySpacing.s2),
                                    decoration: BoxDecoration(
                                      color: (_isAuthed ? tokens.success : tokens.borderDefault).withValues(alpha: ZplayOpacity.overlayHover),
                                      borderRadius: ZplayRadius.xsAll,
                                    ),
                                    child: Text(
                                      _isAuthed ? 'CONNECTED' : 'DISCONNECTED',
                                      style: ZplayType.overline.toStyle(
                                        color: _isAuthed ? tokens.success : tokens.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                                Text(
                                  _isLoading
                                      ? 'Checking credentials...'
                                      : _isAuthed
                                          ? 'Logged in as ${_username ?? 'Trakt User'}'
                                          : 'Sign in to activate two-way cloud sync',
                                  style: ZplayType.body.toStyle(color: tokens.textSecondary),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );

                      Widget? actionWidget;
                      if (_isAuthed) {
                        actionWidget = OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tokens.danger,
                            side: BorderSide(
                              color: tokens.danger.withValues(alpha: ZplayOpacity.textMuted),
                            ),
                            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: _logout,
                          child: Text('Disconnect', style: ZplayType.label.toStyle()),
                        );
                      } else if (!_pairing) {
                        actionWidget = ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _traktBrand,
                            foregroundColor: tokens.textPrimary,
                            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                            padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16, vertical: 10),
                          ),
                          onPressed: _startPairing,
                          icon: const Icon(Icons.qr_code_rounded, size: 18),
                          label: Text('Pair Account', style: ZplayType.label.toStyle()),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isNarrow) ...[
                            infoWidget,
                            if (actionWidget != null) ...[
                              const SizedBox(height: 14),
                              SizedBox(width: double.infinity, child: actionWidget),
                            ],
                          ] else ...[
                            Row(
                              children: [
                                Expanded(child: infoWidget),
                                if (actionWidget != null) ...[
                                  const SizedBox(width: 14),
                                  actionWidget,
                                ],
                              ],
                            ),
                          ],
                          if (_pairing && _userCode != null) ...[
                            const SizedBox(height: 20),
                            Divider(color: tokens.borderStrong),
                            const SizedBox(height: 16),
                            Center(
                              child: Column(
                                children: [
                                  Text(
                                    'Enter this activation code at trakt.tv/activate:',
                                    style: ZplayType.label.toStyle(color: tokens.textEmphasis),
                                  ),
                                  const SizedBox(height: 12),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: _userCode!));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Code copied to clipboard!')),
                                      );
                                    },
                                    borderRadius: ZplayRadius.smAll,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: tokens.bg,
                                        borderRadius: ZplayRadius.smAll,
                                        border: Border.all(color: _traktBrand.withValues(alpha: ZplayOpacity.textSecondary)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _userCode!,
                                            // The code keeps its wide tracking; only the
                                            // role's metrics come from the type scale.
                                            style: ZplayType.titleLarge
                                                .toStyle(color: tokens.textPrimary)
                                                .copyWith(letterSpacing: 4),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(Icons.copy_rounded, color: tokens.textEmphasis, size: 20),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: tokens.borderStrong,
                                      foregroundColor: tokens.textPrimary,
                                      elevation: 0,
                                      shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                                      padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16, vertical: ZplaySpacing.s8),
                                    ),
                                    onPressed: () => _openBrowser('https://trakt.tv/activate'),
                                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                                    label: Text('Open trakt.tv/activate', style: ZplayType.label.toStyle()),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: _traktBrand),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Waiting for authorization on trakt.tv...',
                                        style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),

              const SizedBox(height: 24),

              // Cloud Sync Actions
              if (_isAuthed) ...[
                Text(
                  'Cloud Sync Controls',
                  style: ZplayType.subtitle.toStyle(color: tokens.textEmphasis),
                ),
                const SizedBox(height: 12),
                ListTile(
                  tileColor: tokens.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: ZplayRadius.smAll,
                    side: BorderSide(color: tokens.borderSubtle),
                  ),
                  leading: Icon(Icons.sync_rounded, color: tokens.accent),
                  title: Text('Sync Watchlist & Continue Watching Now', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                  subtitle: Text('Manually triggers an immediate pull from Trakt', style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary)),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: tokens.textMuted),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Syncing with Trakt.tv...')),
                    );
                    await Future.wait([
                      MyListService.syncAll(),
                      ContinueWatchingService.syncCloudSessions(),
                    ]);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Trakt sync complete!')),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
