import SwiftUI
import QuartzCore
import DictusCore

@MainActor
final class KeyboardWaveformDriver: ObservableObject {
    static let shared = KeyboardWaveformDriver()
    private let instanceID = String(UUID().uuidString.prefix(8))

    @Published private(set) var displayLevels: [Float] = Array(repeating: 0, count: 30)
    @Published private(set) var animation: WaveformAnimation = .still
    @Published private(set) var processingPhase: Double = 0
    @Published private(set) var renderTick: Int = 0

    private let barCount = 30
    private let smoothingFactor: Float = 0.3
    private let decayFactor: Float = 0.85

    private var status: DictationStatus = .idle
    private var energyLevels: [Float] = []
    private var isVisible = false
    private var activePresenterID: String?
    private var displayLink: CADisplayLink?
    private var lastTickTime: CFTimeInterval?
    /// Worst interval between two display-link callbacks since the last heartbeat, which
    /// is where it is reported (#314). A stutter well under the 500 ms `waveformStall`
    /// threshold is already enough to be felt, and this is how it becomes visible in a
    /// log without a per-frame line.
    private var maxGapSinceHeartbeat: CFTimeInterval = 0
    private var lastHeartbeatTime: Date = .distantPast

    private init() {
        logProbe("init")
    }

    deinit {
        displayLink?.invalidate()
    }

    func sync(
        presenterID: String,
        status: DictationStatus,
        energyLevels: [Float],
        isVisible: Bool
    ) {
        let ownsPresentation = activePresenterID == presenterID
        if !isVisible && !ownsPresentation && activePresenterID != nil {
            return
        }

        if isVisible {
            activePresenterID = presenterID
        } else if ownsPresentation {
            activePresenterID = nil
        }

        let previousStatus = self.status
        self.status = status
        self.energyLevels = energyLevels
        self.isVisible = isVisible
        animation = resolvedAnimation(for: status)

        // One phase drives both the transcription sine and the travelling peak, so
        // it restarts on every status change rather than only on the way out of an
        // animated state: `.transcribing -> .processing` (#267) hands the phase from
        // one curve to the other, and inheriting the sine's phase would drop the peak
        // at an arbitrary point of its travel. `ProcessingWaveform.centredPhase` is
        // zero, which starts the peak at the centre of the row and lets it sweep
        // out from there.
        if status != previousStatus {
            processingPhase = ProcessingWaveform.centredPhase
        }

        if status == .requested || status == .idle || status == .ready {
            displayLevels = Array(repeating: 0, count: barCount)
        }

        if !isVisible {
            lastTickTime = nil
            maxGapSinceHeartbeat = 0
            lastHeartbeatTime = .distantPast
        }

        updateDisplayLinkState()
    }

    /// Which animation `status` calls for.
    private func resolvedAnimation(for status: DictationStatus) -> WaveformAnimation {
        switch status {
        case .recording:
            return .micLevels
        case .transcribing:
            return .sweep
        case .processing:
            return .travellingPeak
        case .idle, .requested, .ready, .failed:
            return .still
        }
    }

    /// Whether the current animation has to be redrawn every frame.
    ///
    /// **There is deliberately no reduced-motion branch here.** An earlier round of
    /// #267 froze the travelling peak at the centre of the row when Reduce Motion
    /// was on. The maintainer tested it on device and removed it: the peak moves
    /// identically whether or not the setting is on.
    ///
    /// That is a decision, not an oversight, and it was taken with the argument
    /// against it stated -- the setting exists for people for whom a localized
    /// object crossing the screen is costly, and dropping the fallback gives up
    /// acceptance criterion 7 of the issue. To be revisited only if a user reports
    /// it. Do not reinstate the freeze as a tidy-up.
    private var needsDisplayLink: Bool {
        switch animation {
        case .micLevels, .sweep, .travellingPeak:
            return true
        case .still:
            return false
        }
    }

    private func updateDisplayLinkState() {
        let shouldRun = isVisible && needsDisplayLink

        if shouldRun {
            startDisplayLinkIfNeeded()
        } else {
            stopDisplayLink()
        }
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        link.add(to: .main, forMode: .common)
        displayLink = link

        // `isProcessing` keeps its pre-#267 meaning here -- "the bars are drawing
        // themselves rather than following the mic" -- so log lines from older
        // builds stay comparable. Which of the two self-driven animations it is
        // reads off `status=` on the probe line below.
        PersistentLog.log(.waveformAppeared(
            refreshID: renderTick,
            isProcessing: animation.isSelfDriven,
            energyCount: energyLevels.count,
            killedState: false
        ))
        logProbe("displayLinkStarted", details: "status=\(status.rawValue) energyCount=\(energyLevels.count) renderTick=\(renderTick)")
    }

    private func stopDisplayLink() {
        guard displayLink != nil else { return }

        displayLink?.invalidate()
        displayLink = nil
        lastTickTime = nil
        maxGapSinceHeartbeat = 0

        PersistentLog.log(.waveformDisappeared(
            refreshID: renderTick,
            renderTick: renderTick
        ))
        logProbe("displayLinkStopped", details: "status=\(status.rawValue) renderTick=\(renderTick)")
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        let previousTimestamp = lastTickTime
        lastTickTime = timestamp

        // The nominal frame duration stands in on the first callback only, which is the
        // one tick with no previous timestamp to measure from. Everywhere else it is
        // the wrong number: it never reports the frames that were missed (#314).
        let elapsed = previousTimestamp.map { timestamp - $0 } ?? link.duration

        if let previousTimestamp {
            let gap = timestamp - previousTimestamp
            maxGapSinceHeartbeat = max(maxGapSinceHeartbeat, gap)

            let gapMs = Int(gap * 1000)
            if gapMs > 500 {
                PersistentLog.log(.waveformStall(
                    gapMs: gapMs,
                    renderTick: renderTick,
                    energyCount: energyLevels.count
                ))
            }
        }

        switch animation {
        case .micLevels:
            tickRecording()
        case .sweep, .travellingPeak:
            processingPhase += ProcessingWaveform.phaseAdvance(for: animation, elapsedSeconds: elapsed)
        case .still:
            break
        }

        renderTick += 1
        logHeartbeatIfNeeded()
    }

    private func tickRecording() {
        let targets = targetLevels()
        var updated = displayLevels

        for index in 0..<barCount {
            let target = targets[index]
            let current = updated[index]

            if target > current {
                updated[index] = current + (target - current) * smoothingFactor
            } else {
                updated[index] = target + (current - target) * decayFactor
            }

            if updated[index] < 0.005 {
                updated[index] = 0
            }
        }

        displayLevels = updated
    }

    private func logHeartbeatIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastHeartbeatTime) >= 2.0 else { return }

        let targets = targetLevels()

        let sourceLevels: [Float]
        switch animation {
        case .sweep:
            sourceLevels = (0..<barCount).map { processingEnergy(at: $0, phase: processingPhase) }
        case .travellingPeak:
            sourceLevels = ProcessingWaveform.levels(phase: processingPhase)
        case .micLevels, .still:
            sourceLevels = displayLevels
        }

        let average = sourceLevels.isEmpty ? Float(0) : sourceLevels.reduce(0, +) / Float(sourceLevels.count)
        PersistentLog.log(.waveformHeartbeat(
            renderTick: renderTick,
            avgLevel: average,
            energyCount: energyLevels.count,
            maxGapMs: Int(maxGapSinceHeartbeat * 1000)
        ))
        maxGapSinceHeartbeat = 0
        if animation == .micLevels {
            logProbe(
                "waveformShape",
                details: "target{\(waveformStatsDetails(targets))} display{\(waveformStatsDetails(displayLevels))}"
            )
        }
        lastHeartbeatTime = now
    }

    private func targetLevels() -> [Float] {
        guard !energyLevels.isEmpty else {
            return Array(repeating: 0, count: barCount)
        }

        var result = [Float]()
        result.reserveCapacity(barCount)

        for index in 0..<barCount {
            let position = Float(index) / Float(max(barCount - 1, 1))
            let arrayIndex = position * Float(energyLevels.count - 1)
            let lower = Int(arrayIndex)
            let upper = min(lower + 1, energyLevels.count - 1)
            let fraction = arrayIndex - Float(lower)
            let value = energyLevels[lower] * (1 - fraction) + energyLevels[upper] * fraction
            let thresholded = value < 0.05 ? Float(0) : value
            result.append(min(max(thresholded, 0), 1))
        }

        return result
    }

    func processingEnergy(at index: Int, phase: Double) -> Float {
        let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
        let sineValue = sin(2 * .pi * (normalizedIndex + phase))
        return Float(0.2 + 0.25 * (sineValue + 1.0))
    }

    private func logProbe(_ action: String, details: String = "") {
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardWaveformDriver",
            instanceID: instanceID,
            action: action,
            details: details
        ))
    }

    private func waveformStatsDetails(_ values: [Float]) -> String {
        guard !values.isEmpty else { return "count=0" }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let spread = maxValue - minValue
        let first = values.first ?? 0
        let middle = values[values.count / 2]
        let last = values.last ?? 0
        return String(
            format: "count=%d min=%.3f max=%.3f spread=%.3f first=%.3f mid=%.3f last=%.3f",
            values.count,
            minValue,
            maxValue,
            spread,
            first,
            middle,
            last
        )
    }
}

struct KeyboardWaveformView: View {
    let maxHeight: CGFloat
    @ObservedObject var driver: KeyboardWaveformDriver

    @Environment(\.colorScheme) private var colorScheme

    private let barCount = 30
    private let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let height = barHeight(at: index)

                Capsule()
                    .fill(resolvedBarColor(at: index))
                    .frame(height: height)
            }
        }
        .frame(height: maxHeight)
    }

    /// Height of one bar under whichever animation is running.
    ///
    /// The two self-driven animations share the 4 pt floor: it is what keeps the
    /// row reading as a waveform at rest rather than as a blank strip. The
    /// travelling peak needs it more than the sine does -- its baseline is 0.05,
    /// so most of its bars sit on that floor at any instant (#267).
    private func barHeight(at index: Int) -> CGFloat {
        let energy: Float
        let minHeight: CGFloat

        switch driver.animation {
        case .sweep:
            energy = driver.processingEnergy(at: index, phase: driver.processingPhase)
            minHeight = 4
        case .travellingPeak:
            energy = ProcessingWaveform.level(
                at: index,
                peakPosition: ProcessingWaveform.peakPosition(phase: driver.processingPhase)
            )
            minHeight = 4
        case .micLevels, .still:
            energy = index < driver.displayLevels.count ? driver.displayLevels[index] : 0
            minHeight = 2
        }

        return max(minHeight + CGFloat(energy) * (maxHeight - minHeight), minHeight)
    }

    private func resolvedBarColor(at index: Int) -> Color {
        let center = Float(barCount - 1) / 2.0
        let distanceFromCenter = abs(Float(index) - center) / center

        if distanceFromCenter < 0.4 {
            return .dictusGradientStart
        }

        let opacity = Double(1.0 - distanceFromCenter) * 0.9 + 0.15
        let barColor: Color = colorScheme == .dark ? .white : .gray
        return barColor.opacity(opacity)
    }
}
