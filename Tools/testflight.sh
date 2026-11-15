#!/bin/sh
# Archives the app and uploads it to App Store Connect, where it appears under TestFlight.
#
# Needs: membership of the Apple Developer Program (a free Personal Team cannot upload), the
# account signed in under Xcode > Settings > Accounts, and an app record for the bundle
# identifier no.meshnorway.map in App Store Connect.
#
# Usage: TEAM_ID=XXXXXXXXXX Tools/testflight.sh            archive and upload
#        TEAM_ID=XXXXXXXXXX Tools/testflight.sh --archive  archive only (to check signing)
set -eu

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer Program team id (10 characters, on developer.apple.com under Membership)}"
cd "$(dirname "$0")/.."

ARCHIVE="build/MeshNorway.xcarchive"
rm -rf "$ARCHIVE"

xcodebuild -project MeshtasticNorwayMap.xcodeproj -scheme MeshtasticNorwayMap -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates archive

if [ "${1:-}" = "--archive" ]; then
  echo "Archived to $ARCHIVE (not uploaded)."
  exit 0
fi

# The upload gives the build the next free build number for this version.
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates

echo "Uploaded. The build shows up under TestFlight in App Store Connect after processing (usually 5 to 30 minutes)."
