import CadenceCore
import SwiftUI

@main
struct CadenceApp: App {
    @StateObject private var controller = SessionController()
    @AppStorage("hasEnrolled") private var hasEnrolled = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasEnrolled {
                    HomeView()
                } else {
                    OnboardingFlow(onComplete: { hasEnrolled = true })
                }
            }
            .environmentObject(controller)
            .preferredColorScheme(.dark)
            .tint(Ink.matched)
        }
    }
}
