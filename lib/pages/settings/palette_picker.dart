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
            // One column on the narrowest windows because a swatch and its label
            // do not both fit side by side below that, and a clipped label is
            // worse than a taller list.
            final columns = w < 400 ? 1 : (w < 700 ? 2 : 3);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: w < 400 ? 4.2 : 2.6,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: AppThemeService.palettes.length,
              itemBuilder: (context, index) {
                final palette = AppThemeService.palettes[index];
                final selected = palette.id == current.id;

                return FocusableCard(
                  onTap: () => AppThemeService.setPalette(palette),
                  builder: (context, state) => CardFocusRing(
                    focused: state.focused,
                    radius: ZplayRadius.mdAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: ZplayRadius.mdAll,
                        // One border, and it is the selection: the focus ring is
                        // [CardFocusRing]'s alone. Painting both is what made the
                        // rail look like it had a second, phantom edge.
                        border: Border.all(
                          color: selected
                              ? palette.primaryColor
                              : tokens.borderDefault,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
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
                            ),
                            child: selected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: tokens.textPrimary,
                                    size: 16,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  palette.name,
                                  style: ZplayType.subtitle.toStyle(
                                    color: selected
                                        ? tokens.textPrimary
                                        : tokens.textEmphasis,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  selected ? 'Active Theme' : 'Select',
                                  style: ZplayType.caption.toStyle(
                                    color: selected
                                        ? palette.primaryColor
                                        : tokens.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
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