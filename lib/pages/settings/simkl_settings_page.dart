import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/settings/settings_app_bar.dart';

/// Simkl's brand blue. It identifies the external service, so it stays outside
/// the palette-derived token layer.
const Color _simklBrand = Color(0xFF00ADFF);

class SimklSettingsPage extends StatefulWidget {
  const SimklSettingsPage({super.key});

  @override
  State<SimklSettingsPage> createState() => _SimklSettingsPageState();
}

class _SimklSettingsPageState extends State<SimklSettingsPage> {
  bool _isAuthed = false;
  bool _isLoading = true;
  String? _username;

  // PIN Flow Pairing
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
    final authed = await SimklService.instance.isAuthenticated();
    String? user;
    if (authed) {
      user = await SimklService.instance.getUsername();
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
    setState(() {
      _pairing = true;
      _userCode = null;
    });

    final res = await SimklService.instance.requestPin();
    if (!mounted) return;
    if (res == null) {
      setState(() => _pairing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to request Simkl PIN code.')),
      );
      return;
    }

    final userCode = res['user_code'] as String? ?? '';
    final verifyUrl = res['verification_url'] as String? ?? 'https://simkl.com/pin';
    final interval = (res['interval'] as int? ?? 5).clamp(2, 30);

    setState(() {
      _userCode = userCode;
    });

    // Auto-launch URL
    _openBrowser(verifyUrl);

    // Start Polling
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: interval), (t) async {
      final status = await SimklService.instance.pollPin(userCode);
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
        debugPrint('[Simkl] Browser launch error: $e');
      }
    }
  }

  Future<void> _logout() async {
    _pollTimer?.cancel();
    await SimklService.instance.logout();
    await _checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const SettingsAppBar(title: 'Simkl Synchronization'),
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
                  'Connect your Simkl account to synchronize Movies, TV Shows, and Anime watchlists, continue watching progress, and custom lists.',
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
                        ? _simklBrand.withValues(alpha: ZplayOpacity.textMuted)
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
                            color: _simklBrand.withValues(alpha: ZplayOpacity.borderStrong),
                            borderRadius: ZplayRadius.smAll,
                          ),
                          child: const Icon(Icons.tv_rounded, color: _simklBrand, size: 24),
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
                                    'Simkl',
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
                                        ? 'Logged in as ${_username ?? 'Simkl User'}'
                                        : 'Sign in with PIN to activate Simkl cloud sync',
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
                          backgroundColor: _simklBrand,
                          foregroundColor: tokens.textPrimary,
                          shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                          padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s16, vertical: 10),
                        ),
                        onPressed: _startPairing,
                        icon: const Icon(Icons.pin_rounded, size: 18),
                        label: Text('Connect Simkl', style: ZplayType.label.toStyle()),
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
                                  'Enter this PIN code at simkl.com/pin:',
                                  style: ZplayType.label.toStyle(color: tokens.textEmphasis),
                                ),
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: _userCode!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('PIN copied to clipboard!')),
                                    );
                                  },
                                  borderRadius: ZplayRadius.smAll,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s24, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: tokens.bg,
                                      borderRadius: ZplayRadius.smAll,
                                      border: Border.all(color: _simklBrand.withValues(alpha: ZplayOpacity.textSecondary)),
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
                                  onPressed: () => _openBrowser('https://simkl.com/pin'),
                                  icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                                  label: Text('Open simkl.com/pin', style: ZplayType.label.toStyle()),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: _simklBrand),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Waiting for PIN approval on simkl.com...',
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
                  leading: const Icon(Icons.sync_rounded, color: _simklBrand),
                  title: Text('Sync Simkl Watchlist & Continue Watching', style: ZplayType.body.toStyle(color: tokens.textPrimary)),
                  subtitle: Text('Manually triggers an immediate pull from Simkl', style: ZplayType.bodySmall.toStyle(color: tokens.textSecondary)),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: tokens.textMuted),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Syncing with Simkl...')),
                    );
                    await Future.wait([
                      MyListService.syncAll(),
                      ContinueWatchingService.syncCloudSessions(),
                    ]);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Simkl sync complete!')),
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
