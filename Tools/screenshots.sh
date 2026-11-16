#!/bin/sh
# Takes the App Store screenshots in the simulator, from the live map.868.no.
#
# Usage: Tools/screenshots.sh "iPhone 18 Pro Max" AppStore/screenshots/iphone-6.9
#        Tools/screenshots.sh "iPad Pro 13-inch (M5)" AppStore/screenshots/ipad-13
# A third argument, light (the default) or dark, sets the appearance.
#
# App Store Connect wants 6.9-inch iPhone pictures (1320 x 2868) and 13-inch iPad pictures
# (2064 x 2752). The pictures show the mesh as it is at that moment, so no two runs are alike.
set -eu
NAME="${1:?the name of the simulator}"
OUT="${2:?the folder for the pictures}"
APPEARANCE="${3:-light}"
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)"
# The simulator of that name on the newest system installed.
DEVICE="$(xcrun simctl list devices available | grep -F "    $NAME (" | tail -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
: "${DEVICE:?no simulator called $NAME}"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" >/dev/null
xcrun simctl ui "$DEVICE" appearance "$APPEARANCE"
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi --cellularMode active

# The map, a node, the watched nodes, the trends; then the widgets onto the Home Screen.
TEST_RUNNER_SCREENSHOT_DIR="$WORK" xcodebuild test -project MeshtasticNorwayMap.xcodeproj -scheme MeshtasticNorwayMap \
  -destination "id=$DEVICE" -only-testing:MeshtasticNorwayMapUITests/ScreenshotTests \
  | grep -E "error:|Test Case|\*\* TEST" || true
cp "$WORK"/0[1-4]-*.png "$OUT"/

# The Home Screen, without the test runner's icon on it.
xcrun simctl uninstall "$DEVICE" no.meshnorway.map.uitests.xctrunner || true
sleep 20
xcrun simctl io "$DEVICE" screenshot "$OUT/05-widgets.png" 2>/dev/null

# A notification as the app words it when a watched node goes quiet (WatchRules, WatchMonitor),
# delivered by the simulator rather than waited for.
cat > "$WORK/push.apns" <<'P'
{"Simulator Target Bundle": "no.meshnorway.map",
 "aps": {"alert": {"title": "Gråkallen (868.no Map)", "body": "Not heard for about 6 h."}}}
P
xcrun simctl push "$DEVICE" no.meshnorway.map "$WORK/push.apns"
sleep 2
xcrun simctl io "$DEVICE" screenshot "$OUT/06-notification.png" 2>/dev/null

# App Store Connect refuses pictures with an alpha channel, which the simulator's own have.
for f in "$OUT/05-widgets.png" "$OUT/06-notification.png"; do
  sips -s format jpeg -s formatOptions 100 "$f" --out "$WORK/flat.jpg" >/dev/null
  sips -s format png "$WORK/flat.jpg" --out "$f" >/dev/null
done
rm -rf "$WORK"
ls -l "$OUT"
