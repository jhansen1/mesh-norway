# Mesh Norway

An unofficial iOS app for [map.868.no](https://map.868.no), the live map of the Norwegian Meshtastic mesh.

## Credit

The map, the service behind it and its web app are the **868.no Map** project by **Jim C K Flaten** and contributors:
<https://github.com/868-no/map> (GPL-3.0-only). This app is an unofficial, independent iOS shell around that map. It contains none of the
project's code: it loads the web app from map.868.no at run time, exactly as the site serves it.
The opening screen and the About screen in the app credit the authors and link to the source, the license, the third-party notices and the
site's privacy policy.

Meshtastic® is a registered trademark of Meshtastic LLC. This app is not affiliated with or endorsed by Meshtastic LLC.

## How it works

- `MapModel` owns one `WKWebView` that shows `meshmap://map.868.no/`, a private URL scheme with the site's host name.
- `UpstreamProxy` (a `WKURLSchemeHandler`) answers every request of that origin from `https://map.868.no`, streaming the
  answers, so the live event stream (SSE) and the basemap's range requests (PMTiles) work as in a browser. Because the web
  app comes from the site, the app always runs the version the server expects.
- The web app's service worker cannot run under a private scheme, so the proxy does its job (`RequestRouter`,
  `OfflineStore`): it keeps the app shell and the last API answers on disk, and the app opens with the last data it
  received when there is no connection.
- **No chrome of its own:** the map fills the screen; the edges around it take the page's theme colour. While the map
  loads, an opening screen names the app and credits the map's authors. The otherwise empty strip around the home
  indicator carries one quiet line: "Unofficial app · map.868.no by Jim C K Flaten" and an About button.
- **Satellite layer (switched off, `AppConfig.satelliteLayerAvailable`):** the code is kept for later. With it on, `StyleRewriter` adds a raster layer to the site's MapLibre styles, above the
  basemap's area fills and below its borders, roads and labels. The layer's tiles (`/__app/sat/z/x/y`) are fetched by the
  app from the provider in `AppConfig.swift` (`SatelliteProvider`). The default is Sentinel-2 cloudless 2017 by EOX
  (CC BY 4.0, no key, about 10 m per pixel). Switching the layer loads the page again; the page restores its own view.
- **Notifications for watched nodes:** WKWebView has no Notification API, so the app provides one to the page
  (`MapModel.notificationScript`): the map's own "Notify me" works, and its notifications become iOS notifications
  (`Notifier`). While the map is closed, a background refresh (`WatchMonitor`, `WatchRules`) asks the site's public API
  for each watched node's daily history and tells what changed: quiet for 6 hours (24 for a node heard less than half
  the time), heard again, battery at 20 % or less. A tapped notification opens the node on the map.
- **Widgets** (`MeshNorwayWidgets`): "Watched nodes" (hours heard today and battery for the nodes watched on the map)
  and "Mesh today" (nodes, gateways, new nodes and packets), on the Home Screen and the Lock Screen. The app hands the
  page's watchlist to the widgets through the app group `group.no.meshnorway.map` (`MeshShared`).
- Links out of the map (LinkSim coverage, source code, attributions) open in a browser sheet; Meshtastic contact links are
  handed to the system so the Meshtastic app opens them. Links the page copies or shares carry the public
  `https://map.868.no` address. The LinkSim link gets the node's public link back (`sourceUrl`), as on the site.
- No accounts, cookies, analytics or third-party SDKs. The web view has no native bridge: the page cannot call into the app.

## Differences from the web version

- "Install as an app" is not offered: the app is the installed app.
- Notifications for watched nodes also arrive while the map is closed (the website notifies only while its page is open).

## Build and test

Requires Xcode 16 or later (built with Xcode 27.2). Deployment target iOS 17.

```sh
xcodebuild -project MeshtasticNorwayMap.xcodeproj -scheme MeshtasticNorwayMap \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The unit tests need no network. The UI test drives the real app against map.868.no.

Signing needs the App Groups capability (`group.no.meshnorway.map`) for the app and the widget extension; with automatic
signing Xcode registers it when a team is chosen. The Info.plist additions (background refresh, the `meshnorway://`
link scheme) and the entitlements are in `Config/`.

`swift Tools/make-icon.swift MeshtasticNorwayMap/Assets.xcassets/AppIcon.appiconset/AppIcon.png` redraws the app icon.

## Before publishing

See [AppStore/README.md](AppStore/README.md): permissions to obtain, signing, and the App Store texts.

## License

This app's own source is released under the GNU General Public License v3.0 only (see `LICENSE`), the same license as
the 868.no Map project. It is published with the permission of the map's author, on the conditions that it is clearly
unofficial, free, and supported by its own developer.

Support and privacy policy: <https://jhansen1.github.io/mesh-norway/>
