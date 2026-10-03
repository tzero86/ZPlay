import 'package:flutter/material.dart';

import '../../services/theme/app_theme_service.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/focusable_card.dart';

/// The palette picker, in one place.
///
/// Three settings pages each carried their own copy of this grid, and every one
/// of them was built from a bare `InkWell`. `InkWell` is pointer-only — it is
/// not a `Focus` widget — so on a television the theme picker was a grid of
/// eleven swatches that a remote could see and could not touch.
///
/// [FocusableCard] is what makes it reachable, and its centre-button binding is
/// already handled by `ActivateIntent`, so no key handling is needed here.
class PalettePicker extends StatelessWidget {
  const PalettePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, current, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            // The prototype lays the swatches out four across the ten-foot
            // canvas and lets the count fall on a narrower window, where four
            // cards would each be too narrow for the palette's name.
            final columns = w < 400 ? 2 : (w < 700 ? 3 : 4);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                // A fixed row height rather than an aspect ratio: the swatch is
                // a circle and a label, so its height does not change with the
                // column width, and an aspect ratio made the cards taller the
                // narrower the window got.
                mainAxisExtent: 80,
                crossAxisSpacing: ZplaySpacing.s8,
                mainAxisSpacing: ZplaySpacing.s8,
              ),
              itemCount: AppThemeService.palettes.length,
              itemBuilder: (context, index) {
                final palette = AppThemeService.palettes[index];
                final selected = palette.id == current.id;

                return FocusableCard(
                  onTap: () => AppThemeService.setPalette(palette),
                  builder: (context, state) => CardFocusRing(
                    focused: state.focused,
                    radius: ZplayRadius.smAll,
                    child: Container(
                      padding: const EdgeInsets.all(ZplaySpacing.s8),
                      decoration: BoxDecoration(
                        color: selected ? tokens.accentSubtle : tokens.surface,
                        borderRadius: ZplayRadius.smAll,
                        // Always transparent, never absent: the border is
                        // reserved so that selecting a swatch cannot change the
                        // card's size, and the only ring ever drawn is
                        // [CardFocusRing]'s. A second edge on the active card is
                        // what the rail was reported for.
                        border: Border.all(
                          color: Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  palette.primaryColor,
                                  palette.accentColor,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: tokens.textPrimary.withValues(
                                  alpha: ZplayOpacity.borderMedium,
                                ),
                              ),
                            ),
                            child: selected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: tokens.onAccent,
                                    size: 15,
                                  )
                                : null,
                          ),
                          const SizedBox(height: ZplaySpacing.s4),
                          Text(
                            palette.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZplayType.caption
                                .copyWith(
                                  weight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                )
                                .toStyle(
                                  color: selected
                                      ? tokens.textPrimary
                                      : tokens.textEmphasis,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}