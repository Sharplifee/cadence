import CadenceCore
import SwiftUI

@main
struct CadenceApp: App {
    @StateObject private var controller = SessionController()
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
            .preferredColorScheme(.dark)
            .tint(Ink.matched)
        }
    }
}
