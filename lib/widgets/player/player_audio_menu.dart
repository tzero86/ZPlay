import 'package:flutter/material.dart';
import 'player_glass.dart';
import '../../services/theme/design_tokens.dart';
import '../common/focusable_card.dart';

class PlayerAudioTrack {
  final int index;
  final String title;
  final String? language;
  final String? codec;
  final int? channels;
  final bool isDefault;

  const PlayerAudioTrack({
    required this.index,
    required this.title,
    this.language,
    this.codec,
    this.channels,
    this.isDefault = false,
  });
}

/// Audio tracks selector and audio sync offset adjuster.
class PlayerAudioMenu extends StatelessWidget {
  final List<PlayerAudioTrack> audioTracks;
  final int selectedIndex;
  final double delaySec;
  final ValueChanged<int> onTrackSelected;
  final ValueChanged<double> onDelayChanged;
  final VoidCallback onClose;

  const PlayerAudioMenu({
    super.key,
    required this.audioTracks,
    required this.selectedIndex,
    required this.delaySec,
    required this.onTrackSelected,
    required this.onDelayChanged,
    required this.onClose,
  });

  String _getLanguageEmoji(String? lang) {
    if (lang == null || lang.isEmpty) return '🔊';
    final l = lang.toLowerCase();
    if (l.contains('en') || l.contains('eng')) return '🇺🇸';
    if (l.contains('ar') || l.contains('ara')) return '🇸🇦';
    if (l.contains('es') || l.contains('spa')) return '🇪🇸';
    if (l.contains('fr') || l.contains('fre') || l.contains('fra')) return '🇫🇷';
    if (l.contains('de') || l.contains('ger') || l.contains('deu')) return '🇩🇪';
    if (l.contains('it') || l.contains('ita')) return '🇮🇹';
    if (l.contains('ja') || l.contains('jpn')) return '🇯🇵';
    if (l.contains('ko') || l.contains('kor')) return '🇰🇷';
    if (l.contains('zh') || l.contains('chi') || l.contains('zho')) return '🇨🇳';
    if (l.contains('ru') || l.contains('rus')) return '🇷🇺';
    if (l.contains('pt') || l.contains('por')) return '🇧🇷';
    if (l.contains('hi') || l.contains('hin')) return '🇮🇳';
    if (l.contains('tr') || l.contains('tur')) return '🇹🇷';
    return '🌐';
  }

  String? _getTrackSubtitle(PlayerAudioTrack track) {
    final parts = <String>[];
    if (track.language != null && track.language!.isNotEmpty) {
      parts.add(track.language!.toUpperCase());
    }
    if (track.codec != null && track.codec!.isNotEmpty) {
      parts.add(track.codec!.toUpperCase());
    }
    if (track.channels != null && track.channels! > 0) {
      parts.add(track.channels == 6 ? '5.1 Surround' : (track.channels == 8 ? '7.1 Surround' : '${track.channels} ch'));
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final hasTracks = audioTracks.isNotEmpty;
    final size = MediaQuery.sizeOf(context);
    final screenWidth = size.width;
    final screenHeight = size.height;
    final isCompactH = screenHeight < 500;
    final tokens = context.tokens;

    final cardWidth = (370.0).clamp(270.0, screenWidth - 28);
    final maxTrackListHeight = isCompactH
        ? (screenHeight - 170).clamp(70.0, 160.0)
        : (240.0).clamp(110.0, (screenHeight - 240).clamp(110.0, 320.0));

    return PlayerGlassCard(
      width: cardWidth,
      padding: EdgeInsets.all(isCompactH ? ZplaySpacing.s8 : ZplaySpacing.s12),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompactH ? 4 : 8,
                        vertical: isCompactH ? 2 : 4,
                      ),
                      child: Text(
                        'AUDIO TRACKS',
                        style: ZplayType.overline
                            .copyWith(
                              size: isCompactH ? 9.5 : 10.5,
                              weight: FontWeight.w700,
                            )
                            .toStyle(color: tokens.textMuted),
                      ),
                    ),
                    if (hasTracks)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: PlayerTheme.raised,
                          borderRadius: ZplayRadius.fullAll,
                        ),
                        child: Text(
                          '${audioTracks.length}',
                          style: ZplayType.overline
                              .copyWith(
                                size: isCompactH ? 9 : 10,
                                weight: FontWeight.w700,
                              )
                              .toStyle(color: tokens.textMuted),
                        ),
                      ),
                  ],
                ),
                PlayerIconButton(
                  size: isCompactH ? 24 : 28,
                  iconSize: isCompactH ? 12 : 14,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                  onPressed: onClose,
                ),
              ],
            ),

            SizedBox(height: isCompactH ? 4 : 6),

            // Track List
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxTrackListHeight),
              child: hasTracks
                  ? ListView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: audioTracks.length,
                      itemBuilder: (context, i) {
                        final track = audioTracks[i];
                        final isSelected = track.index == selectedIndex;
                        final subtitle = _getTrackSubtitle(track);

                        return FocusableInkWell(
                          borderRadius: ZplayRadius.smAll,
                          onTap: () {
                            onTrackSelected(track.index);
                          },
                          child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: ZplaySpacing.s12,
                            vertical: ZplaySpacing.s8,
                          ),
                          margin: const EdgeInsets.only(bottom: ZplaySpacing.s4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? PlayerTheme.accent.withValues(alpha: 0.18)
                                : tokens.textPrimary.withValues(alpha: 0.03),
                            borderRadius: ZplayRadius.smAll,
                            border: Border.all(
                              color: isSelected
                                  ? PlayerTheme.accent.withValues(alpha: 0.6)
                                  : tokens.borderSubtle,
                              width: isSelected ? 1.4 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? PlayerTheme.accent
                                      : tokens.borderDefault,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? PlayerTheme.accent
                                        : tokens.borderStrong,
                                    width: 1.5,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: isSelected
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 13,
                                        color: tokens.onAccent,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _getLanguageEmoji(track.language),
                                style: ZplayType.subtitle.toStyle(),
                              ),
                              const SizedBox(width: ZplaySpacing.s8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.title,
                                      style: ZplayType.label
                                          .copyWith(
                                            weight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          )
                                          .toStyle(
                                            color: isSelected
                                                ? tokens.textPrimary
                                                : tokens.textEmphasis,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (subtitle != null) ...[
                                      const SizedBox(height: ZplaySpacing.s2),
                                      Text(
                                        subtitle,
                                        style: ZplayType.overline
                                            .copyWith(
                                              size: 10.5,
                                              weight: FontWeight.w600,
                                              letterSpacing: 0.4,
                                            )
                                            .toStyle(
                                              color: isSelected
                                                  ? tokens.info
                                                  : tokens.textMuted,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          ),
                        );
                      },
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZplaySpacing.s12,
                        vertical: ZplaySpacing.s16,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.audiotrack_rounded,
                            size: 16,
                            color: tokens.textMuted,
                          ),
                          const SizedBox(width: ZplaySpacing.s8),
                          Text(
                            'Default audio stream playing.',
                            style: ZplayType.label.toStyle(color: tokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
            ),

            SizedBox(height: isCompactH ? ZplaySpacing.s4 : ZplaySpacing.s8),
            Divider(color: tokens.borderDefault, height: 1),
            SizedBox(height: isCompactH ? ZplaySpacing.s4 : ZplaySpacing.s8),

            // Audio Sync Offset Row
            Container(
              padding: EdgeInsets.all(isCompactH ? 6 : 9),
              decoration: BoxDecoration(
                color: tokens.textPrimary.withValues(alpha: 0.04),
                borderRadius: ZplayRadius.smAll,
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.sync_rounded,
                            size: 14,
                            color: tokens.textEmphasis,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Audio Sync Offset',
                            style: ZplayType.caption
                                .copyWith(
                                  size: isCompactH ? 11 : 12,
                                  weight: FontWeight.w600,
                                )
                                .toStyle(color: tokens.textEmphasis),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: delaySec != 0
                                  ? PlayerTheme.accent.withValues(alpha: 0.25)
                                  : tokens.borderSubtle,
                              borderRadius: ZplayRadius.xsAll,
                              border: Border.all(
                                color: delaySec != 0
                                    ? PlayerTheme.accent.withValues(alpha: 0.5)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              '${delaySec > 0 ? "+" : ""}${delaySec.toStringAsFixed(2)}s',
                              style: ZplayType.label
                                  .copyWith(
                                    size: isCompactH ? 11.5 : 12.5,
                                    weight: FontWeight.w800,
                                  )
                                  .toStyle(
                                    color: delaySec != 0
                                        ? tokens.info
                                        : tokens.textSecondary,
                                    tabular: true,
                                  )
                                  .copyWith(fontFamily: 'monospace'),
                            ),
                          ),
                          if (delaySec != 0) ...[
                            const SizedBox(width: 6),
                            FocusableCard(
                              onTap: () => onDelayChanged(0.0),
                              builder: (context, _) => Icon(
                                Icons.refresh_rounded,
                                size: 16,
                                color: tokens.info,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: isCompactH ? 5 : 8),
                  Row(
                    children: [
                      // -0.5s
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tokens.textPrimary,
                            side: BorderSide(color: tokens.borderStrong),
                            padding: EdgeInsets.symmetric(vertical: isCompactH ? 3 : 6),
                            minimumSize: Size(0, isCompactH ? 26 : 32),
                            shape: const RoundedRectangleBorder(
                              borderRadius: ZplayRadius.xsAll,
                            ),
                          ),
                          onPressed: () => onDelayChanged(((delaySec - 0.5) * 10).round() / 10.0),
                          child: Text(
                            '−0.5s',
                            style: ZplayType.caption
                                .copyWith(
                                  size: isCompactH ? 10 : 11.5,
                                  weight: FontWeight.w600,
                                )
                                .toStyle(),
                          ),
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s4),
                      // -0.1s
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tokens.textPrimary,
                            side: BorderSide(color: tokens.borderStrong),
                            padding: EdgeInsets.symmetric(vertical: isCompactH ? 3 : 6),
                            minimumSize: Size(0, isCompactH ? 26 : 32),
                            shape: const RoundedRectangleBorder(
                              borderRadius: ZplayRadius.xsAll,
                            ),
                          ),
                          onPressed: () => onDelayChanged(((delaySec - 0.1) * 10).round() / 10.0),
                          child: Text(
                            '−0.1s',
                            style: ZplayType.caption
                                .copyWith(
                                  size: isCompactH ? 10 : 11.5,
                                  weight: FontWeight.w600,
                                )
                                .toStyle(),
                          ),
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s4),
                      // +0.1s
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tokens.textPrimary,
                            side: BorderSide(color: tokens.borderStrong),
                            padding: EdgeInsets.symmetric(vertical: isCompactH ? 3 : 6),
                            minimumSize: Size(0, isCompactH ? 26 : 32),
                            shape: const RoundedRectangleBorder(
                              borderRadius: ZplayRadius.xsAll,
                            ),
                          ),
                          onPressed: () => onDelayChanged(((delaySec + 0.1) * 10).round() / 10.0),
                          child: Text(
                            '+0.1s',
                            style: ZplayType.caption
                                .copyWith(
                                  size: isCompactH ? 10 : 11.5,
                                  weight: FontWeight.w600,
                                )
                                .toStyle(),
                          ),
                        ),
                      ),
                      const SizedBox(width: ZplaySpacing.s4),
                      // +0.5s
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tokens.textPrimary,
                            side: BorderSide(color: tokens.borderStrong),
                            padding: EdgeInsets.symmetric(vertical: isCompactH ? 3 : 6),
                            minimumSize: Size(0, isCompactH ? 26 : 32),
                            shape: const RoundedRectangleBorder(
                              borderRadius: ZplayRadius.xsAll,
                            ),
                          ),
                          onPressed: () => onDelayChanged(((delaySec + 0.5) * 10).round() / 10.0),
                          child: Text(
                            '+0.5s',
                            style: ZplayType.caption
                                .copyWith(
                                  size: isCompactH ? 10 : 11.5,
                                  weight: FontWeight.w600,
                                )
                                .toStyle(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
