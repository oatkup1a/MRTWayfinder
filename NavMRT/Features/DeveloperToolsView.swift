import SwiftUI

struct DeveloperToolsView: View {
    var body: some View {
        List {
            Section("Diagnostics") {
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
