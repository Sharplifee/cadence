import CadenceCore
import SwiftUI

/// Three tabs, because there are exactly three things you do: run a
/// conversation, look back at one, and tune the thing.
struct HomeView: View {
    var body: some View {
        TabView {
            LiveView()
                .tabItem { Label("Live", systemImage: "waveform") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .background(Ink.bg)
    }
}
