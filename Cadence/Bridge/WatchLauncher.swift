import CadenceCore
import Foundation
import HealthKit

/// Launches the watch app from the phone, so this is one app on two devices
/// rather than two apps you have to start by hand.
///
/// `startWatchApp(toHandle:)` is the only public API that brings a watchOS app
/// to the foreground from iOS, and it works by starting a workout session.
/// That has a second benefit worth more than the first: a running
/// HKWorkoutSession gives the watch app unlimited background runtime, which
/// removes the one-hour WKExtendedRuntimeSession ceiling that would otherwise
/// cut a long dinner short.
@MainActor
public final class WatchLauncher {
    private let store = HKHealthStore()

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let types: Set = [HKObjectType.workoutType()]
        return await withCheckedContinuation { c in
            store.requestAuthorization(toShare: types, read: types) { ok, _ in
                c.resume(returning: ok)
            }
        }
    }

    /// Wakes and foregrounds the watch app. Safe to call when it is already
    /// running — the completion just reports the existing session.
    public func launchWatchApp() async throws {
        guard isAvailable else {
            throw NSError(domain: "Cadence.Watch", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "This device cannot start the watch app."])
        }
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.startWatchApp(with: config) { _, error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }
}
