# TestFlight

The project is ready to archive. What is left needs your Apple account.

## Once

1. **Join the Apple Developer Program** (99 USD a year) at <https://developer.apple.com/programs/enroll/>. This Mac is
   signed in with a free Personal Team, which cannot upload to App Store Connect.
2. **Sign in with that account in Xcode** (Xcode > Settings > Accounts) and note the team id: 10 characters, shown on
   <https://developer.apple.com/account> under Membership details.
3. **Create the app record** in App Store Connect (<https://appstoreconnect.apple.com> > Apps > +):
   platform iOS, name "Mesh Norway", primary language English, bundle ID `no.meshnorway.map`, SKU of your choice
   (for example `meshnorway`). The bundle ID appears in the list after the first archive below has registered it; if it
   is not there, run step 4 with `--archive` first.

## Every build

4. Upload:

   ```sh
   TEAM_ID=XXXXXXXXXX Tools/testflight.sh
   ```

   It archives the Release build, lets Xcode create the signing certificate, the two app identifiers
   (`no.meshnorway.map` and `no.meshnorway.map.widgets`), the app group `group.no.meshnorway.map` and the provisioning
   profiles, and uploads. Each upload gets the next build number by itself. `--archive` stops before the upload.

   The same from Xcode: choose your team for the targets MeshtasticNorwayMap and MeshNorwayWidgets (Signing &
   Capabilities), then Product > Archive > Distribute App > TestFlight & App Store.

5. Wait for the build to finish processing (an e-mail arrives; usually 5 to 30 minutes).

## Testers

- **You, on your own devices (internal testing):** App Store Connect > the app > TestFlight > Internal Testing > + >
  add yourself. No review. Install the TestFlight app on the iPhone, sign in with the same Apple ID, and the build is
  there. A TestFlight build is signed by Apple, so it needs neither Developer Mode nor a trusted developer certificate.
- **Others (external testing):** needs a short Beta App Review of the first build, and the fields below.

## Texts for TestFlight

**Beta App Description**

Mesh Norway is the iOS edition of map.868.no, the live map of the Meshtastic mesh network in Norway. It shows the map
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
- Not checked, because it needs the paid team: signing, the app group on a real device, and the upload itself.
