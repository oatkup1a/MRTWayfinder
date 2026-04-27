import SwiftUI

struct DeveloperToolsView: View {
    var body: some View {
        List {
            Section("POC Testing") {
                NavigationLink("POC Visual Navigation") {
                    POCNavigationVisualView()
                }
                NavigationLink("POC Navigation (Manual)") {
                    POCNavigationView()
                }
            }
            
            Section("Testing") {
                NavigationLink("Navigation Test") {
                    NavigationTestView()
                }
            }

            Section("Diagnostics") {
                NavigationLink("Visual Position Map") {
                    VisualPositionView()
                }
                NavigationLink("RSSI Console") {
                    RSSIConsoleView()
                }
                NavigationLink("TxPower Calibration") {
                    TxPowerCalibrationView()
                }
                NavigationLink("Fingerprint Collector") {
                    FingerprintCollectorView()
                }
            }

            Section("App") {
                NavigationLink("Settings") {
                    SettingsView()
                }
            }
        }
        .navigationTitle("Developer")
    }
}
