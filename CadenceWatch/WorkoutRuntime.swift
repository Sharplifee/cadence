import CadenceCore
import Foundation
import HealthKit

/// Keeps the watch app alive for a whole conversation, and is also the
/// mechanism the phone uses to launch it.
///
/// WKExtendedRuntimeSession caps out around an hour and expires mid-dinner. An
/// HKWorkoutSession does not, and `HKHealthStore.startWatchApp(with:)` on the
/// phone starts one here — so the same object solves both the runtime ceiling
/// and the "I shouldn't have to open two apps" problem.
@MainActor
public final class WorkoutRuntime: NSObject, ObservableObject {
    @Published public private(set) var running = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    public func requestAuthorization() async {
        let types: Set = [HKObjectType.workoutType()]
        _ = try? await store.requestAuthorization(toShare: types, read: types)
    }

    public func start() {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        guard let s = try? HKWorkoutSession(healthStore: store, configuration: config) else { return }
        session = s
        builder = s.associatedWorkoutBuilder()
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        s.delegate = self
        s.startActivity(with: Date())
        builder?.beginCollection(withStart: Date()) { _, _ in }
        running = true
    }

    public func stop() {
        guard let s = session else { return }
        s.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        session = nil; builder = nil; running = false
    }
}

extension WorkoutRuntime: HKWorkoutSessionDelegate {
    nonisolated public func workoutSession(_ s: HKWorkoutSession,
                                           didChangeTo to: HKWorkoutSessionState,
                                           from: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.running = (to == .running) }
    }
    nonisolated public func workoutSession(_ s: HKWorkoutSession, didFailWithError e: Error) {
        Task { @MainActor in self.running = false }
    }
}
