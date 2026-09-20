import CadenceCore
import SwiftUI

@main
struct CadenceApp: App {
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
                // Dual capture: the phone records whenever it can get the mic
                // and the watch covers everything it cannot.
                if UserDefaults.standard.object(forKey: "dualCapture") as? Bool ?? true {
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
