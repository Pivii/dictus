// DictusApp/Models/DownloadConnectivityWatch.swift
// The two facts outside a transfer that say whether a stall is worth reporting (#492).
import Foundation
import Network
import UIKit
import DictusCore

/// Watches the two conditions `DownloadStallPolicy` needs — is the user looking, and is
/// there a route — and ticks a callback while a download is running.
///
/// WHY IT EXISTS (issue #492). The model transfer runs in a background `URLSession`,
/// which parks its tasks when connectivity goes away rather than failing them. No
/// delegate callback fires, so the transfer itself cannot notice that it has stopped;
/// the only way to find out is to ask somebody else. `NWPathMonitor` is that somebody
/// for the route, `UIApplication`'s lifecycle notifications for the foreground.
///
/// WHY A TICK AND NOT AN EVENT. Neither condition changing is what makes a stall
/// reportable — it is time passing while both hold and no byte arrives. A timer is the
/// only thing that observes that, and it runs only while there is a transfer to watch:
/// `BackgroundModelDownloadService` starts this when a run begins and stops it when the
/// last one ends.
///
/// WHY THE TICK IS ONLY A QUESTION. A tick is raised here and acted on elsewhere, later,
/// so what it carries is a reading of the past by the time anyone reads it. `conditions`
/// is the present, readable from any thread, and it is what the decision is taken on —
/// see `DownloadStallPolicy.conditionsHeldContinuously` for what goes wrong otherwise.
///
/// WHY `NWPathMonitor` IS RECREATED ON EVERY START. A cancelled monitor cannot be
/// restarted, and the alternative — keeping one alive for the whole process — would run
/// a system observer for the great majority of sessions that download nothing.
final class DownloadConnectivityWatch: @unchecked Sendable {

    /// How often the callback runs while a download is live.
    ///
    /// Two seconds against a 15 s grace period bounds the delay between the predicate
    /// becoming true and the user hearing about it at 17 s, and costs one wake-up every
    /// two seconds during a transfer that is already moving megabytes.
    static let tickInterval: TimeInterval = 2

    private let interval: TimeInterval
    private let onTick: @Sendable (DownloadStallConditions) -> Void

    /// Serialises every member below, and is the queue the monitor, the timer and the
    /// lifecycle handlers all report on. One thread of control, which is what makes
    /// `@unchecked Sendable` true here.
    private let queue = DispatchQueue(label: "solutions.pivi.dictus.download-connectivity")

    private var monitor: NWPathMonitor?
    private var timer: DispatchSourceTimer?
    private var lifecycleObservers: [NSObjectProtocol] = []

    /// The two conditions as they stand. Written on `queue` like everything else, but read
    /// from anywhere — which is the whole point of it, and why it is the one member that
    /// needs a lock rather than a queue.
    private var conditionsStorage = DownloadStallConditions.unknown
    private let conditionsLock = NSLock()

    /// Whether a lifecycle notification has been handled yet. The initial reading of
    /// `UIApplication.applicationState` needs a hop to the main thread, and a transition
    /// can land first; when it has, the reading is stale before it arrives and is dropped.
    private var hasObservedLifecycle = false

    init(
        interval: TimeInterval = DownloadConnectivityWatch.tickInterval,
        onTick: @escaping @Sendable (DownloadStallConditions) -> Void
    ) {
        self.interval = interval
        self.onTick = onTick
    }

    /// The conditions right now, for a caller about to act on a tick it was handed
    /// earlier. Safe to call from any thread.
    var conditions: DownloadStallConditions {
        conditionsLock.lock()
        defer { conditionsLock.unlock() }
        return conditionsStorage
    }

    /// Applies a change to the conditions. Called on `queue`, which is what serialises
    /// the read-modify-write; the lock is there for the readers on other threads.
    private func updateConditions(
        _ body: (DownloadStallConditions) -> DownloadStallConditions
    ) {
        conditionsLock.lock()
        defer { conditionsLock.unlock() }
        conditionsStorage = body(conditionsStorage)
    }

    deinit {
        monitor?.cancel()
        timer?.cancel()
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    /// Begins watching. Idempotent: a second call while running does nothing, so every
    /// caller can start it without knowing whether another download already has.
    func start() {
        queue.async { [self] in
            guard monitor == nil else { return }
            observeLifecycle()
            observeNetworkPath()
            startTicking()
        }
    }

    /// Stops watching and forgets both conditions, so the next download starts from
    /// "nothing observed yet" rather than from a reading that may be minutes old.
    func stop() {
        queue.async { [self] in
            monitor?.cancel()
            monitor = nil
            timer?.cancel()
            timer = nil
            for observer in lifecycleObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            lifecycleObservers.removeAll()
            updateConditions { _ in .unknown }
            hasObservedLifecycle = false
        }
    }

    // MARK: - Observation (private queue only)

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setForegrounded(true)
            },
            // Deliberately NOT `willResignActive`: that fires for a control centre pull
            // or a notification banner, and the user is still looking at the download.
            // Only entering the background means there is nobody to tell.
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setForegrounded(false)
            }
        ]

        // The state right now, for the download that starts without a transition to
        // announce it. Read on the main thread because `applicationState` requires it.
        DispatchQueue.main.async { [weak self] in
            let isForegrounded = UIApplication.shared.applicationState != .background
            self?.queue.async { [weak self] in
                guard let self, !hasObservedLifecycle else { return }
                updateConditions {
                    DownloadStallConditions(
                        foregroundSince: isForegrounded ? Date() : nil,
                        offlineSince: $0.offlineSince
                    )
                }
            }
        }
    }

    private func setForegrounded(_ isForegrounded: Bool) {
        queue.async { [self] in
            hasObservedLifecycle = true
            updateConditions { conditions in
                // Only the transition sets the onset — a duplicate notification must not
                // push the deadline back and hand the user another 15 s of frozen bar.
                let onset = isForegrounded ? (conditions.foregroundSince ?? Date()) : nil
                return DownloadStallConditions(
                    foregroundSince: onset,
                    offlineSince: conditions.offlineSince
                )
            }
        }
    }

    private func observeNetworkPath() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            // `.unsatisfied` is the only status that means no route at all.
            // `.requiresConnection` says a link (a VPN, an on-demand interface) can still
            // be brought up, so the transfer is not necessarily dead and this is not the
            // moment to tell the user their connection is gone.
            let isOffline = path.status == .unsatisfied
            updateConditions { conditions in
                let onset = isOffline ? (conditions.offlineSince ?? Date()) : nil
                return DownloadStallConditions(
                    foregroundSince: conditions.foregroundSince,
                    offlineSince: onset
                )
            }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    private func startTicking() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            onTick(conditions)
        }
        timer.resume()
        self.timer = timer
    }
}
