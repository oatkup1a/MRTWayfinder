import SwiftUI

struct SettingsView: View {
    @AppStorage("navmrt.autostart") private var autoStartNav: Bool = true
    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = true
    @AppStorage("navmrt.dataPack") private var dataPackId: String =
        DataPackCatalog.defaultPackId
    @AppStorage("navmrt.receiverHeightMeters") private var receiverHeightMeters: Double = 1.0

    var body: some View {
        Form {
            Section("Navigation") {
                Toggle("Use mock beacons", isOn: $useMockBeacons)
                    .accessibilityLabel("Use mock beacons")
                    .accessibilityHint("Turn this off when testing with real beacon hardware")

                Toggle("Auto-start navigation", isOn: $autoStartNav)
                    .accessibilityLabel("Auto start navigation")
                    .accessibilityHint("When enabled, navigation starts automatically when you open the Navigator screen")
            }

            Section("Data Pack") {
                Picker("Dataset", selection: $dataPackId) {
                    ForEach(DataPackCatalog.packs) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .pickerStyle(.navigationLink)

                Text("Choose which bundled beacons, fingerprints, graph, and places to load.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("If the app already opened a screen that uses map data, close and relaunch the app after changing this.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Trilateration") {
                Stepper(
                    value: $receiverHeightMeters,
                    in: 0.0...2.0,
                    step: 0.1
                ) {
                    Text(
                        String(
                            format: "Phone height above floor: %.1f m",
                            receiverHeightMeters
                        )
                    )
                }

                Text("Used to correct beacon-to-phone vertical distance when beacons are on the floor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Notes") {
                Text("Mock beacon mode is useful for simulator testing and scripted demos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Auto-start is recommended for VoiceOver users so they don’t need to find the Start button.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("House Test is a compact 7 meter pack intended for trilateration and fingerprinting in a small indoor space.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
