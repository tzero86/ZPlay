import 'package:flutter/material.dart';

import '../../services/theme/design_tokens.dart';

/// One labelled settings section: an overline heading over a group of rows that
/// rest on the page canvas, split by hairline dividers instead of one card per
/// row.
///
/// [title] is already resolved copy - the caller owns translation, because the
/// hub's section ids double as scroll anchors and must stay stable across a
/// language change while the words shown to the user follow it.
///
/// The hub keys this widget per section so a sidebar tap can scroll the content
/// pane to its group; the key belongs here rather than on a bare `Column`
/// because this is the anchor's box either way.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  /// Suppresses the leading gap: the first section on a page sits directly
  /// under the page's own header instead of the space between sections.
  final bool first;

  const SettingsSection({
    super.key,
    required this.title,
    required this.rows,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first) const SizedBox(height: ZplaySpacing.s24),
        Text(title, style: ZplayType.overline.toStyle(color: tokens.textMuted)),
        const SizedBox(height: ZplaySpacing.s12),
        Column(children: _dividerSeparated(rows, tokens.borderSubtle)),
      ],
    );
  }

  /// Returns [rows] with a hairline divider between each pair, so a section's
  /// rows still read as one group without a surface around them.
  static List<Widget> _dividerSeparated(List<Widget> rows, Color dividerColor) {
    final children = <Widget>[];
    for (final row in rows) {
      if (children.isNotEmpty) {
        children.add(Divider(color: dividerColor, height: 1));
      }
      children.add(row);
    }
    return children;
  }
}