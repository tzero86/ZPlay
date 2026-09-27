import 'package:flutter/material.dart';

import '../../services/p2p/p2p_settings_service.dart';
import '../../services/theme/design_tokens.dart';

class P2pWarningDialog extends StatelessWidget {
  const P2pWarningDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isSmallScreen = size.width < 500;
    final tokens = ZplayTokens.of(context);
    final warning = tokens.warning;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: size.height * 0.90,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: ZplayRadius.lgAll,
              border: Border.all(
                color: warning.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: warning.withValues(alpha: 0.15),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.70),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: ZplayRadius.lgAll,
              child: Column(
                // `max`, not `min`.
                //
                // `mainAxisSize.min` sizes the column to its children, so the
                // `Flexible` scroll body below is offered the full height of its
                // content rather than the space actually left by the header and
                // the button bar. On a short viewport the column then overflows
                // instead of shrinking the scroll area, which sliced the third
                // engine row in half and hid it behind the buttons.
                //
                // Verified on a Chromecast with Google TV, which reports
                // 960x540 dp: the dialog has a fixed header, a scrolling middle
                // and a fixed action bar, and only the middle should give way.
                // A desktop window is taller than the content, so nothing there
                // changes.
                mainAxisSize: MainAxisSize.max,
                children: [
                  // 1. Header Banner
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      ZplaySpacing.s20,
                      ZplaySpacing.s20,
                      ZplaySpacing.s16,
                      ZplaySpacing.s20,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          warning.withValues(alpha: 0.22),
                          warning.withValues(alpha: 0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: warning.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(ZplaySpacing.s12),
                          decoration: BoxDecoration(
                            color: warning.withValues(alpha: 0.20),
                            borderRadius: ZplayRadius.mdAll,
                            border: Border.all(
                              color: warning.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Icon(
                            Icons.shield_outlined,
                            color: warning,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: ZplaySpacing.s16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: ZplaySpacing.s8,
                                      vertical: ZplaySpacing.s4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: warning.withValues(alpha: 0.20),
                                      borderRadius: ZplayRadius.xsAll,
                                    ),
                                    child: Text(
                                      'PRIVACY & NETWORK ADVISORY',
                                      style: ZplayType.overline.toStyle(
                                        color: warning,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: ZplaySpacing.s4),
                              Text(
                                'P2P Torrent Streaming Notice',
                                style: ZplayType.title.toStyle(
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: tokens.textSecondary,
                          ),
                          tooltip: 'Exit',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // 2. Scrollable Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZplaySpacing.s24,
                        vertical: ZplaySpacing.s20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Main advisory text
                          Text(
                            'P2P (peer-to-peer torrent) streaming connects directly to public torrent swarms to download and seed video pieces. In certain countries and regions, unencrypted torrent activity may be monitored and could result in warning letters or notices from your Internet Service Provider (ISP).',
                            style: ZplayType.body.toStyle(
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: ZplaySpacing.s16),

                          // Engine Breakdown Box
                          Container(
                            padding: const EdgeInsets.all(ZplaySpacing.s16),
                            decoration: BoxDecoration(
                              color: tokens.bg.withValues(alpha: 0.7),
                              borderRadius: ZplayRadius.mdAll,
                              border: Border.all(
                                color: tokens.borderDefault,
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildSourceInfoRow(
                                  context,
                                  icon: Icons.cloud_done_rounded,
                                  iconColor: tokens.success,
                                  title: 'ZPlayHTTP (Direct Stream)',
                                  subtitle: 'Safe direct HTTPS web streams. No torrenting or peer uploading.',
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: ZplaySpacing.s12,
                                  ),
                                  child: Divider(
                                    height: 1,
                                    color: tokens.borderSubtle,
                                  ),
                                ),
                                _buildSourceInfoRow(
                                  context,
                                  icon: Icons.hub_rounded,
                                  iconColor: warning,
                                  title: 'ZPlay (Torrent Engine)',
                                  subtitle: 'P2P swarms (Knaben, TorrentGalaxy). Involves peer data sharing.',
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: ZplaySpacing.s16),

                          // Prompt question
                          Container(
                            padding: const EdgeInsets.all(ZplaySpacing.s16),
                            decoration: BoxDecoration(
                              color: warning.withValues(alpha: 0.10),
                              borderRadius: ZplayRadius.mdAll,
                              border: Border.all(
                                color: warning.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.help_outline_rounded,
                                  color: warning,
                                  size: 22,
                                ),
                                const SizedBox(width: ZplaySpacing.s12),
                                Expanded(
                                  child: Text(
                                    'Would you like to turn off the built-in ZPlay P2P torrent source and use only direct HTTP streaming?',
                                    style: ZplayType.subtitle.toStyle(
                                      color: tokens.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: ZplaySpacing.s12),
                          Text(
                            'Note: You can easily toggle the built-in P2P source back on or off anytime in Settings.',
                            style: ZplayType.caption
                                .toStyle(color: tokens.textSecondary)
                                .copyWith(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3. Responsive Action Buttons Footer
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      ZplaySpacing.s20,
                      ZplaySpacing.s16,
                      ZplaySpacing.s20,
                      ZplaySpacing.s20,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.bg.withValues(alpha: 0.95),
                      border: Border(
                        top: BorderSide(color: tokens.borderDefault),
                      ),
                    ),
                    child: isSmallScreen
                        ? _buildStackedButtons(context)
                        : _buildHorizontalButtons(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceInfoRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    final tokens = ZplayTokens.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(ZplaySpacing.s8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: ZplayRadius.smAll,
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: ZplaySpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: ZplayType.label.toStyle(color: tokens.textPrimary),
              ),
              const SizedBox(height: ZplaySpacing.s2),
              Text(
                subtitle,
                style: ZplayType.bodySmall.toStyle(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalButtons(BuildContext context) {
    final tokens = ZplayTokens.of(context);

    return Row(
      children: [
        // Exit button
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s12,
            ),
            foregroundColor: tokens.textSecondary,
          ),
          child: Text('Exit', style: ZplayType.label.toStyle()),
        ),
        const Spacer(),

        // Don't show again button (keeps P2P enabled)
        OutlinedButton(
          onPressed: () async {
            await P2pSettingsService.setNeverShowWarning(true);
            if (context.mounted) Navigator.of(context).pop();
          },
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: tokens.borderStrong),
            foregroundColor: tokens.textEmphasis,
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s12,
            ),
            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
          ),
          child: Text("Don't Show Again", style: ZplayType.label.toStyle()),
        ),
        const SizedBox(width: ZplaySpacing.s12),

        // Yes, Turn Off P2P button
        ElevatedButton.icon(
          onPressed: () async {
            await P2pSettingsService.setP2pEnabled(false);
            await P2pSettingsService.setNeverShowWarning(true);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('P2P torrent source turned off. ZPlayHTTP will be used.'),
                  backgroundColor: tokens.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text('Yes, Turn Off P2P', style: ZplayType.label.toStyle()),
          style: ElevatedButton.styleFrom(
            backgroundColor: tokens.warning,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s12,
            ),
            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  Widget _buildStackedButtons(BuildContext context) {
    final tokens = ZplayTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Yes, Turn Off P2P button
        ElevatedButton.icon(
          onPressed: () async {
            await P2pSettingsService.setP2pEnabled(false);
            await P2pSettingsService.setNeverShowWarning(true);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('P2P torrent source turned off. ZPlayHTTP will be used.'),
                  backgroundColor: tokens.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text('Yes, Turn Off P2P', style: ZplayType.label.toStyle()),
          style: ElevatedButton.styleFrom(
            backgroundColor: tokens.warning,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s12),
            shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
            elevation: 0,
          ),
        ),
        const SizedBox(height: ZplaySpacing.s8),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  await P2pSettingsService.setNeverShowWarning(true);
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: tokens.borderStrong),
                  foregroundColor: tokens.textEmphasis,
                  padding: const EdgeInsets.symmetric(
                    vertical: ZplaySpacing.s12,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: ZplayRadius.smAll,
                  ),
                ),
                child: Text(
                  "Don't Show Again",
                  style: ZplayType.label.toStyle(),
                ),
              ),
            ),
            const SizedBox(width: ZplaySpacing.s8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s16,
                  vertical: ZplaySpacing.s12,
                ),
                foregroundColor: tokens.textSecondary,
              ),
              child: Text('Exit', style: ZplayType.label.toStyle()),
            ),
          ],
        ),
      ],
    );
  }
}
