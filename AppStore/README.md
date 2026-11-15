# App Store submission

## Before submitting

1. **Permission from the map's author.** The app shows map.868.no and uses its server. App Review guideline 5.2.2 asks
   for authorization to use a third-party service, and it is the decent thing to do. Ask Jim C K Flaten (operator contact
   on <https://map.868.no/privacy.html>) for written permission, and keep it to attach in App Review notes. Requests from
   the app carry `MeshNorway/<version>` at the end of the User-Agent, so the operator can tell them apart.
2. **The name.** The app is called "Mesh Norway", so the Meshtastic trademark is not in its title. The description and
   the About screen still say what the map shows (a Meshtastic mesh) and carry the notice that the app is not affiliated
   with Meshtastic LLC; check their trademark rules (<https://meshtastic.org/docs/legal/>) if you want to be sure that
   wording is fine. If "Mesh Norway" is taken on the App Store, a title must be unique: try "Mesh Norway Map".
   Tell him as well that the app's widgets and its background check ask the public API directly (user agents
   `MeshNorway/<version> (widget)` and `(background)`): one request per watched node, at most about hourly per device.
3. **Signing.** Open the project in Xcode, pick your team under Signing & Capabilities for all three targets, and change
   the bundle identifier `no.meshnorway.map` if you want another. Then Product > Archive and upload.
4. **Privacy policy URL.** App Store Connect requires one. The app itself collects nothing; the text in
   `privacy-policy.md` can be published on any page you control.

## App Store Connect fields

**Name:** Mesh Norway

**Subtitle:** The iOS edition of map.868.no

**Category:** Utilities (secondary: Navigation)

**Age rating:** 4+

**Price:** Free

**Promotional text**

The live map of the Norwegian Meshtastic mesh from map.868.no, on your iPhone and iPad.

**Description**

Mesh Norway is the iOS edition of map.868.no, the live map of the Meshtastic mesh network in Norway.

The app shows the map exactly as map.868.no serves it, with everything the web version has:

• Nodes, routers and gateways on the map, live, with marker clusters when zoomed out
• Radio links with their evidence, signal statistics and history
• Node details: overview, links, radio, telemetry and packets
• Time windows from 1 hour to 14 days, back through the retention period
• Mesh health, regions and long-term trends
• Watchlist and search for nodes and Norwegian place names
• Import a node into the Meshtastic app from a link or a QR code
• Coverage simulation of a node's site in LinkSim
• Light and dark themes
• Opens with the last data it received when you are offline

Made for iPhone and iPad:

• Notifications when a node you watch goes quiet, is heard again or runs low on battery, also while the app is closed
• Home Screen and Lock Screen widgets: the nodes you watch, and the mesh today
• Tap a notification or a widget to open the node on the map

The map, the service behind it and all its data are the work of the 868.no Map project, created by Jim C K Flaten and contributors. The project is open source (GPL-3.0): https://github.com/868-no/map. This app is an independent iOS edition and adds only the app around the map.

Map data © OpenStreetMap contributors, © OpenMapTiles, © Kartverket. Weather from MET Norway.

No accounts, no ads, no tracking.

Meshtastic® is a registered trademark of Meshtastic LLC. This app is not affiliated with or endorsed by Meshtastic LLC.

**Keywords**

meshtastic,mesh,lora,868,norway,norge,map,kart,radio,nodes,mqtt,off-grid

**Support URL:** a page you control (for example the app's repository)

**Marketing URL:** https://map.868.no (only with the author's permission)

**Copyright:** your name for the app; the map © its authors

## App Privacy (the questionnaire)

"Data Not Collected". The app has no accounts, analytics, ads or third-party SDKs.

## Export compliance

The app uses only the system's HTTPS. `ITSAppUsesNonExemptEncryption` is set to `NO` in the build settings.

## Notes for App Review

Suggested text:

> This app is the iOS edition of the public website https://map.868.no, a live map of the Meshtastic radio mesh in
> Norway, published with the permission of the site's author (attached). It needs no account. Beyond the website it adds
> notifications for watched nodes (also from a background refresh while the app is closed), Home Screen and Lock
> Screen widgets ("Watched nodes" and "Mesh today"), offline start with the last received data and native handling of sharing and of links to the Meshtastic app and to the LinkSim coverage simulator.
>
> To try the notifications: tap a node on the map, tap the star (☆) in its Details to watch it, then open the node list
> (first button in the bar at the bottom of the map), tick "Notify me" and allow notifications. To try the widgets: add
> the "Mesh Norway" widgets from the Home Screen's widget gallery.
