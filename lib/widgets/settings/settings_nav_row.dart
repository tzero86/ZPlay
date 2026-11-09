import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';
import '../common/focusable_card.dart';

/// A navigating settings row inside a grouped section: bare 20 px leading icon,
/// title and subtitle, with the row's value right-aligned ahead of the chevron.
///
/// [iconColor] defaults to the accent, which is what a row whose icon says
/// nothing about state wears. Pass a colour only where the icon reports one -
/// brand hues for third-party services, the semantic warning/success for a
/// toggled state.
class SettingsNavRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final String? valueText;
  final VoidCallback onTap;

  const SettingsNavRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    this.valueText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // `FocusableCard`, not a bare `InkWell`.
    //
    // An `InkWell` is pointer-only: it is not a `Focus` widget, so no key, remote
    // or D-pad event can reach it and it draws no focus indicator. Every other
    // surface in the app was converted to `FocusableCard` for exactly this, and
    // Settings was missed - which is why a television could open the page and
    // then not be able to enter anything. The focus tree showed the nodes
    // existing 40-odd in the shell scope while nothing on the page was
    // reachable, because the rows that looked like controls were not focus
    // nodes at all.
    //
    // **The ring is the row's own rect, not the content inside its padding.**
    //
    // A device sweep measured the first content row's ring at 671 x 62 dp and
    // read it as "the widest focus rect in the app, and a different control from
    // every other focus target". The rectangles differ because the targets do,
    // and this target is a full-width list row: a ring drawn around the row's
    // *text* would mark a region a press does not have to land in, because the
    // whole row activates - its 16 dp gutter included. On a television the ring
    // is the only thing that says what a press does, so it draws the edge of
    // what a press hits. Every full-width row surface in the app answers the
    // same way, and says so: `_buildActiveCard` in `downloads_page.dart` - "the
    // row is spacing over the page surface, and the only edge it ever draws is
    // the focus ring" - and the sidebar beside this page, which wraps its own
    // `Padding` in the ring rather than insetting it. So does every settings row,
    // nav or switch.
    //
    // The layout is identical either way: the `Padding` stays inside the ring, so
    // the row's box, its content and the ring's radius all sit where they sat.
    // This is a decision about the mark, not about the box.
    return FocusableCard(
      onTap: onTap,
      builder: (context, state) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: CardFocusRing(
            focused: state.focused,
            radius: ZplayRadius.smAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ZplaySpacing.s16,
                vertical: ZplaySpacing.s12,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: iconColor ?? tokens.accent),
                  const SizedBox(width: ZplaySpacing.s16),

                  // Title and Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: ZplayType.subtitle.toStyle(
                            color: tokens.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: ZplaySpacing.s2),
                        Text(
                          subtitle,
                          style: ZplayType.bodySmall.toStyle(
                            color: tokens.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  if (valueText != null) ...[
                    const SizedBox(width: ZplaySpacing.s12),
                    Text(
                      valueText!,
                      style: ZplayType.caption.toStyle(color: tokens.textMuted),
                      maxLines: 1,
                    ),
                  ],

                  const SizedBox(width: ZplaySpacing.s8),

                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: tokens.textDisabled,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}