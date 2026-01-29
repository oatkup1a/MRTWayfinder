import SwiftUI

@main
struct NavMRTApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section("For passengers") {
                        NavigationLink("Guided Navigation") {
                            RouteSelectionView()  // user-oriented UI
                        }
                    }

                    Section("Developer tools") {
                        NavigationLink("RSSI Console") {
                            RSSIConsoleView()
                        }
                        // If you later add other debug views, put them here
                    }
                    Section("App") {
                        NavigationLink("Settings") { SettingsView() }
                    }

                }
                .navigationTitle("NavMRT")
            }
        }
    }
}
