import CadenceCore
import SwiftUI

@main
struct CadenceApp: App {
    init() {
        EventLog.configure(url: "https://lbvaosyfikkpvcwksiph.supabase.co", apiKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxidmFvc3lmaWtrcHZjd2tzaXBoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwMDg0MDksImV4cCI6MjA5MDU4NDQwOX0.Gh9whjmUPz4rdKYr5yo8ZHS0nSNpkQUOwdIladX6mG4", project: "looped")   // append-only event log (public.event_log)
    }
    @StateObject private var controller = SessionController()
    @StateObject private var clips = ClipReceiver()
    @StateObject private var phoneLoop = PhoneLoopRecorder()
    @AppStorage("hasEnrolled") private var hasEnrolled = false

    var body: some Scene {
        WindowGroup {
            Group {
                // Both must hold. hasEnrolled alone let the app launch into a
                // state where starting always failed.
                if hasEnrolled && controller.isEnrolled {
                    HomeView()
                } else {
                    OnboardingFlow(onComplete: { hasEnrolled = true })
                }
            }
            .environmentObject(controller)
            .environmentObject(clips)
            .environmentObject(phoneLoop)
            .task {
                WatchFileBridge.shared.receiver = clips
                // Opening the app must not touch AVAudioSession. Activating a
                // session re-evaluates the Bluetooth route, which is audible
                // as a glitch and a quality drop in whatever is playing.
                // Phone recording starts only when you ask for it, and only
                // when it would not degrade playback.
                if UserDefaults.standard.bool(forKey: "dualCapture") {
                    phoneLoop.start()
                }
            }
            .onChange(of: phoneLoop.runs.count) { _, _ in
                clips.addRuns(phoneLoop.runs)
            }
            .preferredColorScheme(.dark)
            .tint(Ink.matched)
        }
    }
}
