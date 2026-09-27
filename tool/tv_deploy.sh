#!/bin/sh
# Pair, install and launch ZPlay on the Bedroom TV, then capture the result.
#
# Usage: sh tool/tv_deploy.sh <pairing-code>
#
# Wireless debugging issues a fresh code and a fresh pair of ports each time it
# is reopened. The code is read from argv because `adb pair` prompts on stdin
# and this script is not interactive. The debug port is discovered from mDNS
# rather than assumed: the television allocates it alongside the pairing port
# and it is a different number, 40373 against 44151 in the session that wrote
# this.

set -e

CODE="${1:?usage: tv_deploy.sh <pairing-code>}"
HOST="${TV_HOST:-192.168.1.48}"
PAIR_PORT="${TV_PAIR_PORT:-40373}"
# The debug build installs with a `.debug` suffix. Every adb command below
# failed with "Activity class does not exist" against the release id, which is
# a confusing way to learn this.
PKG="io.github.tzero86.zplay.debug"
ACTIVITY="io.github.tzero86.zplay.MainActivity"
APK="build/app/outputs/flutter-apk/app-debug.apk"

echo "==> pair $HOST:$PAIR_PORT"
adb pair "$HOST:$PAIR_PORT" "$CODE"

echo "==> connect"
CONNECT_PORT="$(adb mdns services | awk '/_adb-tls-connect/{print $NF}' | cut -d: -f2 | head -1)"
if [ -z "$CONNECT_PORT" ]; then
  echo "no mDNS debug port advertised; wireless debugging may have closed" >&2
  exit 1
fi
adb connect "$HOST:$CONNECT_PORT"
adb wait-for-device

echo "==> what the television reports"
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
# `leanback` plus the ABSENCE of `touchscreen` is the pair MainActivity tests,
# and the absence is load-bearing: this box reports no touchscreen feature at
# all rather than reporting one as false.
adb shell pm list features | grep -iE "leanback|touchscreen" || true
adb shell wm size
adb shell wm density

echo "==> uninstall first, then install"
# The television has 4 GB with under 700 MB free, and the debug APK is ~227 MB.
# Installing over an existing copy needs room for the old and new dex at once
# during the swap, which it does not have, so the install fails with
# INSTALL_FAILED_INSUFFICIENT_STORAGE even where a fresh install would fit.
# Removing first is the only reliable sequence here.
adb uninstall "$PKG" 2>/dev/null || true
adb install "$APK"

echo "==> launch"
adb shell am start -n "$PKG/$ACTIVITY"
# The device takes around a minute to a first frame: the torrent engine boots
# and the home feed requests before the shell draws. Screenshots taken earlier
# are a blank dark frame that looks like a crash but is not one.
sleep 60

echo "==> screenshot"
adb exec-out screencap -p > tv_home.png
echo "wrote tv_home.png"

echo "==> the rail width is the observable consequence of the TV detection"
echo "    (172 dp on a 960 dp canvas, against 88 dp for a pointer device)"
echo "    measure it as: screenshot width * 385/1568, then divide by 2.0 for DPR"
