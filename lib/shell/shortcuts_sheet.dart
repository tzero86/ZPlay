import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../services/theme/design_tokens.dart';
import '../widgets/common/focusable_card.dart';

/// One row of the keyboard reference.
@immutable
class ShortcutRow {
  const ShortcutRow({required this.keys, required this.description, this.note});

  /// The key labels, in the order they are pressed. More than one means the app
  /// accepts either, which is shown rather than hidden because the alternative -
  /// a list that says `Ctrl` and is wrong on a Mac - is worse than no list.
  final List<String> keys;

  final String description;

  /// Why the binding is what it is, where the obvious choice would have been
  /// wrong. Optional: most rows do not need one, and a reference padded with
  /// explanations is a reference nobody reads.
  final String? note;

  ShortcutRow withNote(String? note) => ShortcutRow(
    keys: keys,
    description: description,
    note: note ?? this.note,
  );
}

/// Groups of shortcuts in the reference sheet.
@immutable
class ShortcutGroup {
  const ShortcutGroup({required this.title, required this.rows});

  final String title;
  final List<ShortcutRow> rows;
}

/// The keyboard reference, on `?`.
///
/// A shortcut nobody can discover is a shortcut nobody uses. Music carried the
/// only copy of this in the app, behind its own `?`, so the map was reachable
/// only from one page of five and described keys that mostly did nothing
/// anywhere else. The map belongs to the shell, because that is where the map
/// it describes is bound.
///
/// Everything here is focusable and escapable like any other dialog, because
/// the app is used on a television as well as a desktop and a reference sheet
/// that only closes with a mouse is not a reference sheet.
class ShortcutsSheet extends StatefulWidget {
  const ShortcutsSheet({super.key, this.onClose});

  final VoidCallback? onClose;

  /// Shows the sheet above [context].
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ShortcutsSheet(),
    );
  }

  @override
  State<ShortcutsSheet> createState() => _ShortcutsSheetState();
}

class _ShortcutsSheetState extends State<ShortcutsSheet> {
  /// Escape closes, and so does the close button - the same contract the P2P
  /// notice uses, for the same reason.
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = l10nOf(context);
    final groups = shortcutGroups(l10n);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(ZplaySpacing.s24),
        child: ConstrainedBox(
          // Narrow enough to read as a reference rather than a page, and capped
          // by the viewport so it never overflows on a 540 dp television.
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: ZplayRadius.lgAll,
              border: Border.all(color: tokens.borderDefault),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZplaySpacing.s24,
                    ZplaySpacing.s20,
                    ZplaySpacing.s12,
                    ZplaySpacing.s12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.shortcutsTitle,
                          style: ZplayType.titleLarge.toStyle(
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      _CloseButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.borderDefault),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      ZplaySpacing.s24,
                      ZplaySpacing.s16,
                      ZplaySpacing.s24,
                      ZplaySpacing.s24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final group in groups)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: ZplaySpacing.s16,
                            ),
                            child: _Group(group: group, tokens: tokens),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.group, required this.tokens});

  final ShortcutGroup group;
  final ZplayTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.title.toUpperCase(),
          style: ZplayType.overline.toStyle(color: tokens.textSecondary),
        ),
        const SizedBox(height: ZplaySpacing.s8),
        for (final row in group.rows) _Row(row: row, tokens: tokens),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.tokens});

  final ShortcutRow row;
  final ZplayTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZplaySpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed so the descriptions form a column. Keys are chips, and a chip
          // row is sized by its content, so an unconstrained description would
          // start and stop at a different x for every row.
          SizedBox(
            width: 150,
            child: Wrap(
              spacing: ZplaySpacing.s4,
              runSpacing: ZplaySpacing.s4,
              children: [
                for (final key in row.keys) _KeyCap(label: key, tokens: tokens),
              ],
            ),
          ),
          const SizedBox(width: ZplaySpacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.description,
                  style: ZplayType.body.toStyle(color: tokens.textPrimary),
                ),
                if (row.note != null) ...[
                  const SizedBox(height: ZplaySpacing.s2),
                  Text(
                    row.note!,
                    style: ZplayType.bodySmall.toStyle(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label, required this.tokens});

  final String label;
  final ZplayTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZplaySpacing.s8,
        vertical: ZplaySpacing.s4,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: ZplayRadius.smAll,
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Text(
        label,
        style: ZplayType.label.toStyle(color: tokens.textEmphasis),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: l10nOf(context).shortcutsClose,
      child: FocusableCard(
        onTap: onPressed,
        builder: (context, state) => CardFocusRing(
          focused: state.focused,
          radius: ZplayRadius.smAll,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: state.highlighted
                  ? tokens.surfaceRaised
                  : Colors.transparent,
              borderRadius: ZplayRadius.smAll,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: state.highlighted
                  ? tokens.textPrimary
                  : tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's keyboard map, in the order a user meets it.
///
/// Declared as data rather than read back out of the `Shortcuts` widget so the
/// sheet and the bindings can be checked against each other: a key that is bound
/// but not listed is invisible to the user, and a key that is listed but not
/// bound is worse, because it is a promise the app does not keep.
///
/// Built per locale rather than held in a `const` list, because every
/// description is prose. The keys themselves and their order do not change, so
/// the sheet still describes exactly the bindings `Shortcuts` installs.
List<ShortcutGroup> shortcutGroups(AppLocalizations l10n) => [
  ShortcutGroup(
    title: l10n.shortcutsGroupAnywhere,
    rows: [
      ShortcutRow(
        keys: const ['?'],
        description: l10n.shortcutsShowSheet,
        note: l10n.shortcutsShowSheetNote,
      ),
      ShortcutRow(
        keys: const ['F11'],
        description: l10n.shortcutsToggleFullscreen,
      ),
      ShortcutRow(
        keys: const ['Esc'],
        description: l10n.shortcutsLeaveFullscreen,
        note: l10n.shortcutsLeaveFullscreenNote,
      ),
    ],
  ),
  ShortcutGroup(
    title: l10n.shortcutsGroupMoving,
    rows: [
      ShortcutRow(keys: const ['Alt', '1'], description: l10n.navHome),
      ShortcutRow(keys: const ['Alt', '2'], description: l10n.navBrowse),
      ShortcutRow(keys: const ['Alt', '3'], description: l10n.navSearch),
      ShortcutRow(keys: const ['Alt', '4'], description: l10n.shortcutsMyList),
      ShortcutRow(keys: const ['Alt', '5'], description: l10n.navSettings),
      ShortcutRow(
        keys: const ['Ctrl', 'K'],
        description: l10n.navSearch,
        note: l10n.shortcutsSearchMacNote,
      ),
      ShortcutRow(
        keys: const ['Ctrl', ','],
        description: l10n.navSettings,
        note: l10n.shortcutsSettingsMacNote,
      ),
    ],
  ),
  ShortcutGroup(
    title: l10n.shortcutsGroupPlaying,
    rows: [
      ShortcutRow(
        keys: const ['Space'],
        description: l10n.shortcutsPlayPause,
        note: l10n.shortcutsPlayPauseNote,
      ),
      ShortcutRow(
        keys: const ['J', 'L'],
        description: l10n.shortcutsSeek,
        note: l10n.shortcutsSeekNote,
      ),
      ShortcutRow(keys: const ['M'], description: l10n.shortcutsMute),
      ShortcutRow(keys: const ['C'], description: l10n.shortcutsAspect),
    ],
  ),
  ShortcutGroup(
    title: l10n.shortcutsGroupReading,
    rows: [
      ShortcutRow(keys: const ['←', '→'], description: l10n.shortcutsPage),
      ShortcutRow(keys: const ['J', 'K'], description: l10n.shortcutsLine),
    ],
  ),
];
