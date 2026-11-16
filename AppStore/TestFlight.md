# TestFlight

Status 16. november 2026: medlemskapet i Apple Developer Program er aktivt, appen er opprettet i App Store Connect, og
versjon 1.0 er lastet opp tre ganger. Bygg 3 er det gjeldende: det har «Unofficial app»-merkingen, parameteret
`?client=ios-app` og lenken til fellesskapet. Resten av filen er på engelsk der teksten skal limes inn hos Apple.

## Every build

1. Upload (the team id is on <https://developer.apple.com/account> under Membership details):

   ```sh
   TEAM_ID=XXXXXXXXXX Tools/testflight.sh
   ```

   It archives the Release build, lets Xcode create the signing certificate, the two app identifiers
   (`no.meshnorway.map` and `no.meshnorway.map.widgets`), the app group `group.no.meshnorway.map` and the provisioning
   profiles, and uploads. If the archive fails on the widget's app-group entitlement, tick `group.no.meshnorway.map`
   under App Groups for `no.meshnorway.map.widgets` at <https://developer.apple.com/account/resources/identifiers/list>
   (needed once, on 15 November 2026). Each upload gets the next build number by itself. `--archive` stops before the upload.

   The same from Xcode: choose your team for the targets MeshtasticNorwayMap and MeshNorwayWidgets (Signing &
   Capabilities), then Product > Archive > Distribute App > TestFlight & App Store.

2. Wait for the build to finish processing (an e-mail arrives; usually 5 to 30 minutes).

## Testers

- **You, on your own devices (internal testing):** App Store Connect > the app > TestFlight > Internal Testing > + >
  add yourself. No review. Install the TestFlight app on the iPhone, sign in with the same Apple ID, and the build is
  there. A TestFlight build is signed by Apple, so it needs neither Developer Mode nor a trusted developer certificate.
- **Others (external testing):** needs a short Beta App Review of the first build, and the fields below.

## Texts for TestFlight

**Beta App Description**

Mesh Norway is an unofficial iOS app for map.868.no, the live map of the Meshtastic mesh network in Norway. It shows the map
as the site serves it, and adds notifications and widgets for the nodes you watch.

**What to Test**

- The map: pan, pinch to zoom (fingers, and a trackpad on iPad), tap nodes and links, the panels in the bar at the bottom.
- "LIVE" in the header stays green while the app is open, and comes back after the app has been in the background.
- A node's Details: "Coverage" opens LinkSim; "Import" > "Open in Meshtastic" opens the Meshtastic app if it is installed;
  the share link gives an https://map.868.no address.
- Watch a node (the star in its Details), tick "Notify me" in the node list and allow notifications.
- Add the "Watched nodes" and "Mesh today" widgets to the Home Screen and the Lock Screen; tap a node in the widget.
- Flight mode: close the app, switch flight mode on, open the app. It should open with the last data and say it is offline.
- Light and dark appearance, portrait and landscape, iPad.

**Feedback e-mail / contact:** your address.

**Beta App Review notes (external testing only):** the "Notes for App Review" text in `README.md` in this folder.

## Checked before hand-over

- A Release archive builds (without signing) and contains the app, the widget extension, the app icon and both privacy
  manifests; version 1.0, build 1; `ITSAppUsesNonExemptEncryption` is false, so no export-compliance question is asked.
- The development aids (`-diagnostics`, `-simulateOffline`) are not in the Release binary.
- Signing and the upload were done on 15 November 2026. Not yet checked: the app group on a real device.
