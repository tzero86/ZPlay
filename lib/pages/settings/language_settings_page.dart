import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/settings/locale_settings.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/settings/settings_app_bar.dart';

/// Language choice. `System` follows the device; the two explicit choices are
/// the locales this build ships translations for.
class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = l10nOf(context);
    return AnimatedAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SettingsAppBar(title: l10n.languageTitle),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ValueListenableBuilder<Locale?>(
              valueListenable: LocaleSettings.locale,
              builder: (context, locale, _) {
                final selected =
                    locale?.languageCode ?? LocaleSettings.systemCode;
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s16,
                    vertical: ZplaySpacing.s20,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: ZplaySpacing.s20),
                      child: Text(
                        l10n.languageSubtitle,
                        style: ZplayType.body.toStyle(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                    _LanguageTile(
                      title: l10n.languageSystem,
                      selected: selected == LocaleSettings.systemCode,
                      onTap: () =>
                          LocaleSettings.setLocale(LocaleSettings.systemCode),
                    ),
                    _LanguageTile(
                      title: l10n.languageEnglish,
                      selected: selected == 'en',
                      onTap: () => LocaleSettings.setLocale('en'),
                    ),
                    _LanguageTile(
                      title: l10n.languageArabic,
                      selected: selected == 'ar',
                      onTap: () => LocaleSettings.setLocale('ar'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: ZplaySpacing.s8),
      child: Material(
        color: selected
            ? tokens.accent.withValues(alpha: ZplayOpacity.overlayHover)
            : tokens.surface,
        borderRadius: ZplayRadius.mdAll,
        child: InkWell(
          borderRadius: ZplayRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZplaySpacing.s16,
              vertical: ZplaySpacing.s12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: ZplayType.subtitle.toStyle(
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? tokens.accent : tokens.textDisabled,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
