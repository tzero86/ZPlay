#!/bin/sh
# Repeatable TV D-pad sequence: arrow predictability, traps, restoration,
# rail-to-menu reachability, and the expansion/misplacement class.
#
# Why this exists alongside the widget harness (`test/support/tv_nav_harness.dart`,
# `test/tv_nav_traversal_test.dart`, `test/tv_nav_settlement_test.dart`):
# screenshots and widget harnesses mislead. The hero auto-rotates, so frames
# differ whether or not focus moved; `Tab` never runs the directional path;
# a rect read at notification time is pre-layout. On the device, therefore,
# every frame MUST be paired with its identity line from logcat
# (`lib/services/layout/focus_debug.dart` prints label/id plus rect per key).
# A frame without a log line is not evidence.
#
# Discipline:
#   * panel is 1920x1080 physical at density 320 (960x540 dp, DPR 2);
#     captures are `adb exec-out screencap -p` at that size - never resized.
#   * keys are D-pad keyevents only: 19 up, 20 down, 21 left, 22 right,
#     23 centre (select). BACK (4) is never sent: it exits to the launcher.
#
# Usage:
#   sh tool/tv_dpad_sequence.sh [outdir]
#   SERIAL=192.168.1.48:40373 PKG=io.github.tzero86.zplay.debug \
#     sh tool/tv_dpad_sequence.sh tv_seq_out
set -e

SERIAL="${TV_SERIAL:-192.168.1.48:40373}"
PKG="${TV_PKG:-io.github.tzero86.zplay.debug}"
ACTIVITY="io.github.tzero86.zplay.MainActivity"
OUT="${1:-tv_seq_out}"
WAIT="${TV_KEY_WAIT:-2}"
BOOT="${TV_BOOT_WAIT:-65}"

mkdir -p "$OUT"
LOG="$OUT/identity_trace.txt"
: > "$LOG"

key() {
  code="$1"; name="$2"
  adb -s "$SERIAL" shell input keyevent "$code" >/dev/null 2>&1
  sleep "$WAIT"
  n=$(ls "$OUT"/*.png 2>/dev/null | wc -l)
  adb -s "$SERIAL" exec-out screencap -p > "$OUT/step_$(printf '%02d' "$n")_${name}.png" 2>/dev/null
  {
    echo "=== $name (key $code) ==="
    adb -s "$SERIAL" logcat -d -s flutter 2>/dev/null \
      | grep -a 'FOCUS\|primary\|edge=' | tail -6
    echo ""
  } >> "$LOG"
  adb -s "$SERIAL" logcat -c 2>/dev/null || true
}

adb -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb -s "$SERIAL" shell am start -n "$PKG/$ACTIVITY" >/dev/null 2>&1
sleep "$BOOT"
adb -s "$SERIAL" logcat -c 2>/dev/null || true
adb -s "$SERIAL" exec-out screencap -p > "$OUT/step_00_launch.png" 2>/dev/null

# P2P advisory once: centre lands on Exit, harmless and reversible.
if [ "${TV_DISMISS_P2P:-1}" = "1" ]; then
  adb -s "$SERIAL" shell input keyevent 23 >/dev/null 2>&1
  sleep 3
fi

# 1. Arrow predictability: right x2, left x1 (must reverse), down x2, up x1.
key 22 right_1
key 22 right_2
key 21 left_back
key 20 down_1
key 20 down_2
key 19 up_back

# 2. No traps: walk to the far edge; focus must stop, never vanish.
key 22 edge_right_1
key 22 edge_right_2
key 20 edge_down_1
key 20 edge_down_2

# 3. Restoration: return along the same path; identity lines must mirror.
key 19 restore_up_1
key 21 restore_left_1

# 4. Rail-to-menu: up until the top bar, right along it, down back to content.
key 19 to_bar_1
key 19 to_bar_2
key 22 bar_right
key 20 back_to_content

# 5. Centre activates whatever holds focus (logs the activation path).
key 23 centre_activate

echo ""
echo "frames in $OUT"
echo "identity trace in $LOG"
echo "PASS rule: every step_*.png has a matching '=== name ===' block in"
echo "identity_trace.txt with a distinct id; a repeated id across a move step"
echo "or a missing primary-focus line is a failure, even if frames differ."
