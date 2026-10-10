import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/updater/app_updater_service.dart';
import '../../widgets/updater/update_dialog.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/settings/settings_app_bar.dart';

class UpdatesSettingsPage extends StatefulWidget {
  const UpdatesSettingsPage({super.key});

  @override
  State<UpdatesSettingsPage> createState() => _UpdatesSettingsPageState();
}

class _UpdatesSettingsPageState extends State<UpdatesSettingsPage> {
  bool _isCheckingForUpdates = false;

  Future<void> _checkForUpdates(BuildContext context) async {
    setState(() {
      _isCheckingForUpdates = true;
    });

    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates(ignoreDismissed: true);

      if (!context.mounted) return;

      if (updateInfo != null) {
        showDialog(
          context: context,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('ZPlay is up to date!'),
            backgroundColor: context.tokens.accent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking updates: $e'),
            backgroundColor: context.tokens.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AnimatedAmbientBackground(child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SettingsAppBar(title: 'App Updates & System'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s20,
            ),
            children: [
              // Header description
              Padding(
                padding: const EdgeInsets.only(bottom: ZplaySpacing.s20),
                child: Text(
                  'Keep ZPlay up to date with the latest features, security patches, and performance improvements.',
                  style: ZplayType.body.toStyle(color: tokens.textSecondary),
                ),
              ),

              // Version & check update
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.hasData ? snapshot.data!.version : '1.1.6';
                  final buildNumber = snapshot.hasData ? snapshot.data!.buildNumber : '2019';
                  // Deliberately not PackageInfo.appName: on Windows that reads
                  // the executable's ProductName, which is a lowercase path
                  // segment ("zplay") because path_provider derives
                  // %APPDATA%\Roaming\<CompanyName>\<ProductName> from it —
                  // see windows/runner/Runner.rc. The display name is the brand,
                  // so it is written out here instead of taken from the
                  // platform string.
                  const appName = 'ZPlay';

                  return Padding(
                    padding: const EdgeInsets.all(ZplaySpacing.s20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: tokens.accentSubtle,
                                borderRadius: ZplayRadius.smAll,
                              ),
                              child: Icon(
                                Icons.system_update_rounded,
                                color: tokens.accent,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appName,
                                    style: ZplayType.title.toStyle(
                                      color: tokens.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Installed Version: v$version (Build $buildNumber)',
                                    style: ZplayType.bodySmall.toStyle(
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isCheckingForUpdates
                                ? null
                                : () => _checkForUpdates(context),
                            icon: _isCheckingForUpdates
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.onAccent,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(
                              _isCheckingForUpdates ? 'Checking for updates...' : 'Check for Updates',
                              style: ZplayType.label.toStyle(),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tokens.accent,
                              foregroundColor: tokens.onAccent,
                              shape: const RoundedRectangleBorder(
                                borderRadius: ZplayRadius.smAll,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Release Channel Info
              Text(
                'RELEASE CHANNELS',
                style: ZplayType.overline.toStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: 12),

              _buildInfoTile(
                context: context,
                icon: Icons.verified_rounded,
                title: 'Official Stable Channel',
                subtitle: 'Direct GitHub release distribution with automated checksum verification.',
              ),
              const SizedBox(height: 10),
              _buildInfoTile(
                context: context,
                icon: Icons.security_rounded,
                title: 'Seamless In-App Patching',
                subtitle: 'Downloads and applies executable updates directly without manual file downloads.',
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildInfoTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.borderSubtle,
              borderRadius: ZplayRadius.smAll,
            ),
            child: Icon(icon, color: tokens.textEmphasis, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ZplayType.subtitle.toStyle(
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
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
      ),
    );
  }
}
