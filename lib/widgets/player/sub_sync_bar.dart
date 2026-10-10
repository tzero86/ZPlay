import 'package:flutter/material.dart';
import '../../services/theme/design_tokens.dart';
import 'player_glass.dart';
import '../common/focusable_card.dart';

/// Floating glass toolbar for quick live subtitle delay adjustment.
class SubSyncBar extends StatefulWidget {
  final double delaySec;
  final ValueChanged<double> onDelayChanged;
  final VoidCallback? onEnterTextSync;
  final bool isTextSyncAvailable;
  final VoidCallback onClose;
  final VoidCallback? onSave;

  const SubSyncBar({
    super.key,
    required this.delaySec,
    required this.onDelayChanged,
    this.onEnterTextSync,
    this.isTextSyncAvailable = true,
    required this.onClose,
    this.onSave,
  });

  @override
  State<SubSyncBar> createState() => _SubSyncBarState();
}

class _SubSyncBarState extends State<SubSyncBar> {
  late double _localDelay;
  late double _initialDelay;

  @override
  void initState() {
    super.initState();
    _localDelay = widget.delaySec;
    _initialDelay = widget.delaySec;
  }

  @override
  void didUpdateWidget(covariant SubSyncBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delaySec != widget.delaySec) {
      _localDelay = widget.delaySec;
    }
  }

  void _applyDelay(double value) {
    final rounded = (value * 100).round() / 100.0;
    setState(() => _localDelay = rounded);
    widget.onDelayChanged(rounded);
  }

  void _handleDiscard() {
    _applyDelay(_initialDelay);
    widget.onClose();
  }

  void _handleSave() {
    _initialDelay = _localDelay;
    widget.onSave?.call();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDirty = ((_localDelay - _initialDelay).abs() > 0.01);
    final isNonZero = _localDelay.abs() > 0.01;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s12),
        child: PlayerGlassCard(
          borderRadius: ZplayRadius.md,
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: ZplaySpacing.s8,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left: Speech Text Sync button
            if (widget.onEnterTextSync != null) ...[
              FocusableInkWell(
                borderRadius: ZplayRadius.smAll,
                onTap: widget.isTextSyncAvailable ? widget.onEnterTextSync : null,
                enabled: widget.isTextSyncAvailable,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZplaySpacing.s12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isTextSyncAvailable
                        ? PlayerTheme.accent.withValues(alpha: 0.18)
                        : tokens.textPrimary.withValues(alpha: 0.04),
                    borderRadius: ZplayRadius.smAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.text_fields_rounded,
                        size: 15,
                        color: widget.isTextSyncAvailable
                            ? PlayerTheme.accent
                            : PlayerTheme.inkSubtle,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Text Sync',
                        style: ZplayType.label
                            .toStyle(
                              color: widget.isTextSyncAvailable
                                  ? PlayerTheme.ink
                                  : PlayerTheme.inkSubtle,
                            )
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Center: Stepper Buttons & Display Pill
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: tokens.bg.withValues(alpha: 0.4),
                borderRadius: ZplayRadius.smAll,
                border: Border.all(color: PlayerTheme.edgeSoft),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StepButton(
                    label: '−0.5s',
                    onTap: () => _applyDelay(_localDelay - 0.5),
                    isWide: true,
                  ),
                  _StepButton(
                    label: '−0.1s',
                    onTap: () => _applyDelay(_localDelay - 0.1),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: PlayerTheme.raised,
                      borderRadius: ZplayRadius.smAll,
                      border: Border.all(
                        color: isNonZero ? PlayerTheme.edge : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_localDelay >= 0 ? '+' : ''}${_localDelay.toStringAsFixed(2)}s',
                          style: ZplayType.labelNumeric
                              .toStyle(
                                color: isNonZero ? PlayerTheme.accent : PlayerTheme.inkMuted,
                              )
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (isNonZero) ...[
                          const SizedBox(width: 6),
                          FocusableCard(
                            onTap: () => _applyDelay(0.0),
                            builder: (context, _) => Container(
                              padding: const EdgeInsets.all(ZplaySpacing.s2),
                              decoration: BoxDecoration(
                                color: tokens.textPrimary
                                    .withValues(alpha: ZplayOpacity.overlayHover),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.replay_rounded,
                                color: tokens.textPrimary,
                                size: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _StepButton(
                    label: '+0.1s',
                    onTap: () => _applyDelay(_localDelay + 0.1),
                  ),
                  _StepButton(
                    label: '+0.5s',
                    onTap: () => _applyDelay(_localDelay + 0.5),
                    isWide: true,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Right: Discard & Save Done & Close
            if (isDirty) ...[
              PlayerIconButton(
                size: 32,
                iconSize: 15,
                icon: const Icon(Icons.undo_rounded),
                tooltip: 'Discard changes',
                onPressed: _handleDiscard,
              ),
              const SizedBox(width: 4),
            ],

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: PlayerTheme.accent,
                foregroundColor: tokens.onAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: ZplaySpacing.s12,
                  vertical: 7,
                ),
                shape: const RoundedRectangleBorder(borderRadius: ZplayRadius.smAll),
                minimumSize: const Size(0, 32),
              ),
              icon: const Icon(Icons.check_rounded, size: 15),
              label: Text(
                'Done',
                style: ZplayType.label.toStyle().copyWith(fontWeight: FontWeight.w600),
              ),
              onPressed: _handleSave,
            ),
            const SizedBox(width: 4),

            PlayerIconButton(
              size: 32,
              iconSize: 15,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close',
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    ),
  ),
);
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isWide;

  const _StepButton({
    required this.label,
    required this.onTap,
    this.isWide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: FocusableInkWell(
        borderRadius: ZplayRadius.xsAll,
        onTap: onTap,
        child: Container(
          width: isWide ? 44 : 38,
          height: 28,
          alignment: Alignment.center,
          child: Text(
            label,
            style: ZplayType.caption
                .toStyle(color: PlayerTheme.inkMuted, tabular: true)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
