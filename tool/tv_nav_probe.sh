#!/bin/sh
# Walk the app with a D-pad and report where focus actually goes.
#
# The problem this exists for: navigation was only ever checked by reading the
# code, and four separate defects shipped that way. The player swallowed every
# arrow key with `KeyEventResult.handled`; the rail used a reading-order policy
# on a vertical column; the chrome was sized in logical pixels while the panel
# multiplied by two; and the P2P dialog had no focus scope, so a remote could
# not operate it at all. None was visible in a screenshot and none was caught by
# a widget test, because a widget test presses Tab rather than an arrow.
#
# How it decides whether a key did anything
# ----------------------------------------
# Screenshot diffing alone is not enough, and this harness was written twice
# because of it. The home screen auto-rotates its hero every few seconds, so
# consecutive frames differ whether or not focus moved: the first pass reported
# "changed" for every key on a screen where the D-pad did nothing at all.
#
# So the baseline is captured twice, a second apart, and only the *residual* of a
# key's change against that measured idle rate is treated as movement. A key is
# reported NO CHANGE when its frame is as close to the pre-key frame as the two
# idle frames are to each other. The threshold is therefore the app's own noise
# floor, measured at run time, rather than a constant that goes stale when the
# rotation interval changes.
#
# Motion is not feedback: a rotating poster behind a focused control reads to a
# user as a control that is not responding.
#
# Usage
#   sh tool/tv_nav_probe.sh [outdir]
#   TV_KEYS=19,20,21,22 sh tool/tv_nav_probe.sh out     # only some keys
#   TV_SLOTS=home,search sh tool/tv_nav_probe.sh out   # only some slots
#
# KEYCODES
#   19 up   20 down   21 left   22 right   23 centre   4 BACK
#
# BACK is never sent. It leaves the app to the Google TV launcher, which ends the
# walk, and a probe that destroys its own subject is worse than no probe.
#
# Requires the debug build: a release APK cannot be walked because there is no
# way to read its state, and the debug performance overlay is the one region of
# the frame that changes on every tick and would otherwise dominate the diff.
set -e

SERIAL="${TV_SERIAL:-192.168.1.48:40373}"
PKG="${TV_PKG:-io.github.tzero86.zplay.debug}"
ACTIVITY="io.github.tzero86.zplay.MainActivity"
OUT="${1:-tv_nav_out}"
KEYS="${TV_KEYS:-20,22,19,21}"
SLOTS="${TV_SLOTS:-home,browse,search,library,settings}"
WAIT="${TV_KEY_WAIT:-2}"
BOOT="${TV_BOOT_WAIT:-65}"

mkdir -p "$OUT"

shot() { adb -s "$SERIAL" exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }

keyname() {
  case "$1" in
    19) echo up ;;    20) echo down ;;  21) echo left ;;
    22) echo right ;; 23) echo centre ;;
    *)  echo "k$1" ;;
  esac
}

# Mean absolute pixel difference between two PNGs, as a percentage of the frame.
# A dependency-free stand-in for ImageMagick, which is not installed here.
noise() {
  "$TV_PY" - "$1" "$2" <<'PY'
import sys, zlib, struct

def read_png(path):
    data = open(path, 'rb').read()
    pos, idat, w, h, bd, ct = 8, b'', 0, 0, 0, 0
    while pos < len(data):
        ln = int.from_bytes(data[pos:pos + 4], 'big')
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b'IHDR':
            w, h, bd, ct = (*struct.unpack('>II', body[:8]), body[8], body[9])
        elif typ == b'IDAT':
            idat += body
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = {0: 1, 2: 3, 4: 2, 6: 4}[ct]
    stride = w * ch
    # Undo the PNG scanline filters. Only the None/Sub/Up/Average/Paeth set the
    # encoder ever emits for a screenshot.
    out = bytearray()
    prev = bytearray(stride)
    p = 0
    for _ in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(ch, stride): line[i] = (line[i] + line[i - ch]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out += line
        prev = line
    return w, h, ch, bytes(out)

w1, h1, c1, a = read_png(sys.argv[1])
w2, h2, c2, b = read_png(sys.argv[2])
if (w1, h1, c1) != (w2, h2, c2):
    print('100.0'); raise SystemExit
# Sample every 4th pixel: fast, and the answer only needs to beat a noise floor.
step = 4
total = 0; n = 0
for y in range(0, h1, step):
    base = y * w1 * c1
    for x in range(0, w1, step):
        i = base + x * c1
        total += abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2])
        n += 3
print('%.3f' % (total / n if n else 0.0))
PY
}

TV_PY="${TV_PY:-$HOME/.claude/skills/../../.venv/Scripts/python.exe}"
if [ ! -x "$TV_PY" ]; then TV_PY="$(command -v python || command -v python3)"; fi
if [ -z "$TV_PY" ]; then echo "no python for the diff; set TV_PY" >&2; exit 1; fi

launch() {
  adb -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1 || true
  adb -s "$SERIAL" shell am start -n "$PKG/$ACTIVITY" >/dev/null 2>&1
  # About a minute: the torrent engine boots and the home feed requests before
  # the shell draws. A shorter wait screenshots a blank frame, which reads as
  # "focus never moved" for every key at once.
  sleep "$BOOT"
}

# Walk the rail to the named slot. The rail is the only chrome present on every
# slot, so its rows are the reliable way in; the order is the enum's.
rail_to() {
  target="$1"
  adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1   # dismiss any dialog focus
  sleep 1
  case "$target" in
    home)     : ;;                                        # already there
    browse)   adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1; sleep 1 ;;
    search)   adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1
              adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1; sleep 1 ;;
    library)  adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1
              adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1
              adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1; sleep 1 ;;
    settings) adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1
              adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1
              adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1
              adb -s "$SERIAL" shell input keyevent 20 >/dev/null 2>&1; sleep 1 ;;
  esac
  adb -s "$SERIAL" shell input keyevent 23 >/dev/null 2>&1   # centre
  sleep 4
}

probe() {
  slot="$1"
  echo ""
  echo "=== $slot ==="
  shot "${slot}_idle1"
  sleep 2
  shot "${slot}_idle2"
  floor="$(noise "$OUT/${slot}_idle1.png" "$OUT/${slot}_idle2.png")"
  # A key must beat the idle rate to count. Some headroom, because the carousel
  # can rotate twice inside one key wait.
  thresh="$(awk -v f="$floor" 'BEGIN { printf "%.3f", f * 3 + 0.15 }')"
  echo "  idle noise ${floor}%  threshold ${thresh}%"

  prev="${slot}_idle2"
  step=1
  IFS=,
  for k in $KEYS; do
    adb -s "$SERIAL" shell input keyevent "$k" >/dev/null 2>&1
    sleep "$WAIT"
    cur="$(printf '%s_%02d_%s' "$slot" "$step" "$(keyname "$k")")"
    shot "$cur"
    d="$(noise "$OUT/$prev.png" "$OUT/$cur.png")"
    if awk -v d="$d" -v t="$thresh" 'BEGIN { exit !(d < t) }'; then
      echo "  $(keyname "$k"): NO CHANGE (${d}%)"
    else
      echo "  $(keyname "$k"): moved (${d}%)"
    fi
    prev="$cur"
    step=$((step + 1))
  done
  IFS=
}

launch
# Dismiss the P2P advisory once, on the first launch, so the rest of the walk
# is not all "focus is trapped in a modal". Centring lands on Exit, which is
# harmless and reversible.
if [ "${TV_DISMISS_P2P:-1}" = "1" ]; then
  adb -s "$SERIAL" shell input keyevent 23 >/dev/null 2>&1
  sleep 3
fi

IFS=,
for slot in $SLOTS; do
  IFS=
  rail_to "$slot"
  probe "$slot"
  IFS=,
done
IFS=

echo ""
echo "frames in $OUT"

# ── Reading the focus seam ────────────────────────────────────────────────────
# `lib/services/layout/focus_debug.dart` dumps the focus tree to logcat on every
# key. This reads it back, so the diagnosis is a command rather than a manual
# scroll: each key's block names the scope chain, and any `edge=stop` in that
# chain is a wall focus cannot cross.
#
#   sh tool/tv_nav_probe.sh --focus
focus_dump() {
  echo ""
  echo "=== focus tree per key ==="
  adb -s "$SERIAL" logcat -c 2>/dev/null
  IFS=,
  for k in $KEYS; do
    adb -s "$SERIAL" shell input keyevent "$k" >/dev/null 2>&1
    sleep 1
  done
  IFS=
  sleep 2
  adb -s "$SERIAL" logcat -d -s flutter 2>/dev/null \
    | sed -n '/──── FOCUS/,/──── end/p' \
    | head -"${FOCUS_LINES:-120}"
}
