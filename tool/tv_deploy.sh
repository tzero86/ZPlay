#!/bin/sh
# Pair, install and launch ZPlay on the Bedroom TV, then prove the ten-foot
# layout actually engaged.
#
# Usage: sh tv_deploy.sh <pairing-code>
#
# Wireless debugging issues a fresh code and port each time it is reopened, and
# the port is not 5555, so both are passed in rather than guessed. The code is
# read from argv because `adb pair` prompts for it on stdin and this script is
# not interactive.

set -e

CODE="${1:?usage: tv_deploy.sh <pairing-code>}"
HOST="${TV_HOST:-192.168.1.48}"
PAIR_PORT="${TV_PAIR_PORT:-40373}"
PKG="io.github.tzero86.zplay"
APK="build/app/outputs/flutter-apk/app-debug.apk"

echo "==> pair $HOST:$PAIR_PORT"
adb pair "$HOST:$PAIR_PORT" "$CODE"

echo "==> connect"
# The debug port is discovered, not derived: it is a second ephemeral port the
# TV allocates alongside the pairing one, and it is not the same number.
CONNECT_PORT="$(adb mdns services | awk '/_adb-tls-connect/{print $NF}' | cut -d: -f2 | head -1)"
if [ -z "$CONNECT_PORT" ]; then
  echo "no mDNS debug port advertised; the TV may have closed wireless debugging" >&2
  exit 1
fi
adb connect "$HOST:$CONNECT_PORT"
adb wait-for-device

echo "==> form factor the TV reports"
adb shell pm list features | grep -i leanback || echo "no leanback feature"

echo "==> install"
adb install -r "$APK"

echo "==> launch"
adb shell monkey -p "$PKG" -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null
sleep 12

echo "==> is the app classifying itself as a television?"
# The probe is a one-shot at startup, so the only reliable read is the layout
# the shell built. The rail is 236px on TV against 88px elsewhere, so its
# width is the observable consequence of DeviceProfile.isTelevision.
adb shell dumpsys window displays | grep -E "init=|cur=" | head -3

echo "==> screenshot"
adb exec-out screencap -p > tv_home.png
echo "wrote tv_home.png"
