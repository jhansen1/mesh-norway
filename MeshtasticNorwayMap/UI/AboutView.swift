import SwiftUI

/// Who made the map, whose data it shows, and what this app is.
struct AboutView: View {
    let model: MapModel
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mesh Norway")
                            .font(.title2.bold())
                        Text("The iOS edition of map.868.no")
                            .foregroundStyle(.secondary)
                        Text("Version \(version)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Text("The map, the service behind it and everything it shows are the work of the \(AppConfig.upstreamProjectName) project, created by \(AppConfig.upstreamAuthor) and its contributors. This app shows that map, exactly as map.868.no serves it.")
                    Link("map.868.no", destination: AppConfig.upstreamSiteURL)
                    Link("Source code of \(AppConfig.upstreamProjectName)", destination: AppConfig.upstreamSourceURL)
                    Link("License: GNU GPL v3", destination: AppConfig.upstreamLicenseURL)
                    Link("Third-party notices", destination: AppConfig.upstreamNoticesURL)
                } header: {
                    Text("The map")
                } footer: {
                    Text("All credit for the map belongs to its authors. Questions about the data it shows go to the operator named in its privacy policy.")
                }

                Section {
                    Text("Nodes you watch on the map (the star in a node's Details) are shown in the Mesh Norway widgets. Tick \"Notify me\" in the map's node list and the app tells you when a watched node goes quiet, is heard again or runs low on battery: at once while the map is open, and from an hourly look at the site's history while it is closed.")
                } header: {
                    Text("Watched nodes")
                } footer: {
                    Text("The watchlist stays on this device. Notifications are made by the app itself; no push service is involved.")
                }

                Section("Map data") {
                    Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("© OpenMapTiles", destination: URL(string: "https://openmaptiles.org/")!)
                    Link("© Kartverket (regions, terrain, place names)", destination: URL(string: "https://www.kartverket.no/")!)
                    Link("MET Norway (weather)", destination: URL(string: "https://www.met.no/en/free-meteorological-data/Licensing-and-crediting")!)
                }

                if AppConfig.satelliteLayerAvailable {
                  Section {
                    Link(SatelliteProvider.current.attribution, destination: SatelliteProvider.current.attributionURL)
                    Link("License: \(SatelliteProvider.current.licenseName)", destination: SatelliteProvider.current.licenseURL)
                } header: {
                    Text("Satellite layer")
                } footer: {
                    Text("The satellite layer is added by this app and is not part of map.868.no.")
                  }
                }

                Section {
                    Link("LinkSim", destination: AppConfig.linkSimURL)
                } header: {
                    Text("Coverage simulation")
                } footer: {
                    Text("A node's Coverage link opens LinkSim, an external service, with the node's position and name.")
                }

                Section {
                    Link("Privacy policy of map.868.no", destination: AppConfig.upstreamPrivacyURL)
                    Button("Clear the saved offline copy", role: .destructive) {
                        model.clearSavedCopies()
                        dismiss()
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("This app has no accounts, ads or analytics and collects nothing about you. It connects only to map.868.no, also from its widgets and when it looks after watched nodes in the background. So that it can open without a connection, it keeps a copy of the map and the last data it received on this device.")
                }

                Section {
                    Text("This is an independent app. It is not affiliated with or endorsed by Meshtastic LLC. Meshtastic® is a registered trademark of Meshtastic LLC.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
