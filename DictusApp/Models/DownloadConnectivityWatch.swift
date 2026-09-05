// DictusApp/Models/DownloadConnectivityWatch.swift
// The two facts outside a transfer that say whether a stall is worth reporting (#492).
import Foundation
import Network
import UIKit
import DictusCore

/// What the world outside the transfer looked like at one instant.
///
/// Both values are `nil` until something real has been observed. That is deliberate:
/// "not read yet" must never look like "the user is watching" or "the network is gone",
/// because either mistake is a false alarm on the very screen this exists to protect.
struct DownloadConnectivitySnapshot: Sendable {
    /// When the app last reached the foreground, or `nil` when it is backgrounded.
    let foregroundSince: Date?
    /// When the device last lost every network path, or `nil` when it has one.
    let offlineSince: Date?
}

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
    private let onTick: @Sendable (DownloadConnectivitySnapshot) -> Void

    /// Serialises every member below, and is the queue the monitor, the timer and the
    /// lifecycle handlers all report on. One thread of control, which is what makes
    /// `@unchecked Sendable` true here.
    private let queue = DispatchQueue(label: "solutions.pivi.dictus.download-connectivity")

    private var monitor: NWPathMonitor?
    private var timer: DispatchSourceTimer?
    private var lifecycleObservers: [NSObjectProtocol] = []

    private var foregroundSince: Date?
    private var offlineSince: Date?
    /// Whether a lifecycle notification has been handled yet. The initial reading of
    /// `UIApplication.applicationState` needs a hop to the main thread, and a transition
    /// can land first; when it has, the reading is stale before it arrives and is dropped.
    private var hasObservedLifecycle = false

    init(
        interval: TimeInterval = DownloadConnectivityWatch.tickInterval,
        onTick: @escaping @Sendable (DownloadConnectivitySnapshot) -> Void
    ) {
        self.interval = interval
        self.onTick = onTick
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
            foregroundSince = nil
            offlineSince = nil
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
                foregroundSince = isForegrounded ? Date() : nil
            }
        }
    }

    private func setForegrounded(_ isForegrounded: Bool) {
        queue.async { [self] in
            hasObservedLifecycle = true
            if isForegrounded {
                // Only the transition sets the onset — a duplicate notification must not
                // push the deadline back and hand the user another 15 s of frozen bar.
                if foregroundSince == nil { foregroundSince = Date() }
            } else {
                foregroundSince = nil
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
            if isOffline {
                if offlineSince == nil { offlineSince = Date() }
            } else {
                offlineSince = nil
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
            onTick(DownloadConnectivitySnapshot(
                foregroundSince: foregroundSince,
                offlineSince: offlineSince
            ))
        }
        timer.resume()
        self.timer = timer
    }
}
