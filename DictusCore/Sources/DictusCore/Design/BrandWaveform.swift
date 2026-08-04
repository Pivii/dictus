#if os(iOS)
// DictusCore/Sources/DictusCore/Design/BrandWaveform.swift
// Multi-bar waveform with brand-inspired colors (blue gradient center, white opacity sides).
import SwiftUI
import QuartzCore

@MainActor
final class BrandWaveformDriver: ObservableObject {
    @Published private(set) var displayLevels: [Float] = Array(repeating: 0, count: 30)
    @Published private(set) var processingPhase: Double = 0
    @Published private(set) var renderTick: Int = 0
    @Published private(set) var animation: WaveformAnimation = .micLevels

    private let barCount = 30
    private let smoothingFactor: Float = 0.3
    private let decayFactor: Float = 0.85

    private var energyLevels: [Float] = []
    private var isActive = false
    private var displayLink: CADisplayLink?
    private var lastRenderTime: Date = .distantPast
    private var lastHeartbeatTime: Date = .distantPast

    deinit {
        displayLink?.invalidate()
    }

    func update(energyLevels: [Float], animation: WaveformAnimation, isActive: Bool) {
        let previousAnimation = self.animation
        self.energyLevels = energyLevels
        self.animation = animation
        self.isActive = isActive

        // Restart the phase whenever the animation changes rather than only on the
        // way out of a self-driven one: the sine and the travelling peak share it,
        // and handing the peak the sine's phase would drop it mid-travel (#267).
        if animation != previousAnimation {
            processingPhase = ProcessingWaveform.centredPhase
        }

        if !isActive {
            displayLevels = targetLevels()
        }

        updateLoopState()
    }

    func forceStop() {
        stopLoop()
    }

    /// Whether the current animation has to be redrawn every frame.
    ///
    /// `.still` draws a fixed picture, and `Canvas` re-renders on `renderTick`, so
    /// without this a still waveform would repaint at display rate for as long as
    /// its host kept `isActive` true.
    private var needsDisplayLink: Bool {
        switch animation {
        case .micLevels, .sweep, .travellingPeak:
            return true
        case .still:
            return false
        }
    }

    private func updateLoopState() {
        if isActive && needsDisplayLink {
            startLoopIfNeeded()
        } else {
            stopLoop()
        }
    }

    private func startLoopIfNeeded() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastRenderTime = Date()
        lastHeartbeatTime = .distantPast

        PersistentLog.log(.waveformAppeared(
            refreshID: renderTick,
            isProcessing: animation.isSelfDriven,
            energyCount: energyLevels.count,
            killedState: false
        ))
    }

    private func stopLoop() {
        guard displayLink != nil else { return }

        displayLink?.invalidate()
        displayLink = nil

        PersistentLog.log(.waveformDisappeared(
            refreshID: renderTick,
            renderTick: renderTick
        ))
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        let now = Date()

        if lastRenderTime != .distantPast {
            let gapMs = Int(now.timeIntervalSince(lastRenderTime) * 1000)
            if gapMs > 500 {
                PersistentLog.log(.waveformStall(
                    gapMs: gapMs,
                    renderTick: renderTick,
                    energyCount: energyLevels.count
                ))
            }
        }
        lastRenderTime = now

        switch animation {
        case .micLevels:
            tickLevels()
        case .sweep:
            processingPhase += link.duration / 2.0
        case .travellingPeak:
            processingPhase += link.duration * ProcessingWaveform.phaseRate
        case .still:
            break
        }

        if now.timeIntervalSince(lastHeartbeatTime) >= 2.0 {
            let sourceLevels: [Float] = levels(for: animation)
            let avg = sourceLevels.isEmpty ? Float(0) : sourceLevels.reduce(0, +) / Float(sourceLevels.count)
            PersistentLog.log(.waveformHeartbeat(
                renderTick: renderTick,
                avgLevel: avg,
                energyCount: energyLevels.count
            ))
            lastHeartbeatTime = now
        }

        renderTick += 1
    }

    private func tickLevels() {
        let targets = targetLevels()
        var updated = displayLevels

        for i in 0..<barCount {
            let target = targets[i]
            let current = updated[i]

            if target > current {
                updated[i] = current + (target - current) * smoothingFactor
            } else {
                updated[i] = target + (current - target) * decayFactor
            }

            if updated[i] < 0.005 {
                updated[i] = 0
            }
        }

        displayLevels = updated
    }

    func processingEnergy(at index: Int, phase: Double) -> Float {
        let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
        let sineValue = sin(2 * .pi * (normalizedIndex + phase))
        return Float(0.2 + 0.25 * (sineValue + 1.0))
    }

    /// The bar heights the current animation is drawing, for the heartbeat log.
    private func levels(for animation: WaveformAnimation) -> [Float] {
        switch animation {
        case .sweep:
            return (0..<barCount).map { processingEnergy(at: $0, phase: processingPhase) }
        case .travellingPeak:
            return ProcessingWaveform.levels(phase: processingPhase)
        case .micLevels, .still:
            return displayLevels
        }
    }

    private func targetLevels() -> [Float] {
        guard !energyLevels.isEmpty else {
            return Array(repeating: Float(0), count: barCount)
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
}

/// Multi-bar audio waveform styled with Dictus brand colors.
///
/// WHY multi-bar instead of 3-bar logo:
/// 3 bars felt static and logo-like, not like a real audio visualizer.
/// This uses 30 bars for fluid audio feedback, but keeps brand identity through
/// the color scheme: center bars use the blue gradient, outer bars use white at
/// decreasing opacity -- echoing the logo's asymmetric bar styling.
///
/// WHY GeometryReader for bar width:
/// Bar width adapts automatically to fit available space in each context.
/// The waveform fills the space whether it appears in the recording overlay
/// (full keyboard width), the HomeView card (narrower), or RecordingView (full screen).
public struct BrandWaveform: View {
    /// Array of energy levels (0.0-1.0) for each bar. Count determines bar count.
    public let energyLevels: [Float]

    /// Fixed height of the waveform container. Bars grow within this space.
    public var maxHeight: CGFloat = 80

    /// Which animation the bars draw.
    ///
    /// WHY the two synthetic ones exist at all: after the microphone stops, the
    /// audio engine is idle but the wait is not over, and bars frozen at their last
    /// levels read as a hang. `.sweep` carries continuity from the recording state
    /// through transcription; `.travellingPeak` says the language model is running,
    /// which is a different and much longer wait (#267).
    public var animation: WaveformAnimation = .micLevels

    /// When false, pauses the TimelineView animation schedule (stops CADisplayLink).
    /// WHY: Some hosts need a hard kill switch when the view is still structurally
    /// alive for a moment (for example during keyboard overlay transitions). This
    /// must stop both live recording animation and the processing sine wave.
    public var isActive: Bool = true

    public init(energyLevels: [Float] = [], maxHeight: CGFloat = 80,
                animation: WaveformAnimation = .micLevels, isActive: Bool = true) {
        self.energyLevels = energyLevels
        self.maxHeight = maxHeight
        self.animation = animation
        self.isActive = isActive
    }

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var driver = BrandWaveformDriver()

    /// Number of bars to display.
    private let barCount = 30

    private let barSpacing: CGFloat = 2

    public var body: some View {
        waveformContent
            .onAppear {
                driver.update(
                    energyLevels: energyLevels,
                    animation: animation,
                    isActive: isActive
                )
            }
            .onDisappear {
                driver.forceStop()
            }
            .onChange(of: energyLevels) { _, newLevels in
                driver.update(
                    energyLevels: newLevels,
                    animation: animation,
                    isActive: isActive
                )
            }
            .onChange(of: animation) { _, newValue in
                driver.update(
                    energyLevels: energyLevels,
                    animation: newValue,
                    isActive: isActive
                )
            }
            .onChange(of: isActive) { _, newValue in
                driver.update(
                    energyLevels: energyLevels,
                    animation: animation,
                    isActive: newValue
                )
            }
    }

    /// Canvas-based rendering for 60fps waveform.
    ///
    /// WHY Canvas instead of ForEach + RoundedRectangle:
    /// ForEach creates 30 separate SwiftUI views, each with its own layout pass.
    /// Canvas renders all 30 bars in a single GPU draw call, which is significantly
    /// more efficient and eliminates frame drops during rapid energy level updates.
    ///
    /// WHY zero minHeight in non-processing mode:
    /// The old minHeight of 4pt caused visible micro-movements at zero energy,
    /// making the waveform appear "alive" even when silent. Setting minHeight = 0
    /// means bars completely disappear at zero energy -- perfectly still.
    private var waveformContent: some View {
        Canvas { context, size in
            _ = driver.renderTick
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 2)

            for index in 0..<barCount {
                let energy: Float
                switch driver.animation {
                case .sweep:
                    energy = driver.processingEnergy(at: index, phase: driver.processingPhase)
                case .travellingPeak:
                    energy = ProcessingWaveform.level(
                        at: index,
                        peakPosition: ProcessingWaveform.peakPosition(phase: driver.processingPhase)
                    )
                case .micLevels, .still:
                    energy = index < driver.displayLevels.count ? driver.displayLevels[index] : 0
                }

                // Minimum bar height so the waveform baseline is always visible,
                // even in complete silence. 2pt = thin line, enough to see the
                // colored bar pattern (blue center, gray edges) without looking "active".
                // The self-driven animations sit on the taller floor: the travelling
                // peak leaves most of its bars at a 0.05 baseline, so without it the
                // row all but disappears between crossings.
                let minHeight: CGFloat = driver.animation.isSelfDriven ? 4 : 2
                let height = max(minHeight + CGFloat(energy) * (maxHeight - minHeight), minHeight)

                let x = CGFloat(index) * (barWidth + barSpacing)
                let y = (size.height - height) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: max(height, 0))
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                context.fill(path, with: .color(resolvedBarColor(at: index)))
            }
        }
        .frame(height: maxHeight)
    }

    /// Brand-inspired color resolved to a plain Color for Canvas rendering.
    ///
    /// WHY plain Color instead of ShapeStyle/LinearGradient:
    /// Canvas's `context.fill(path, with:)` accepts `Shading` not `ShapeStyle`.
    /// Per-path gradients aren't practical in Canvas. Instead, center bars use the
    /// brand blue midpoint color (dictusGradientStart) which is visually close to
    /// the old top-to-bottom gradient. A minor simplification for major perf gain.
    private func resolvedBarColor(at index: Int) -> Color {
        // Distance from center (0.0 = center, 1.0 = edge)
        let center = Float(barCount - 1) / 2.0
        let distanceFromCenter = abs(Float(index) - center) / center

        // Center bars: brand blue, edge bars: white/gray with decreasing opacity
        if distanceFromCenter < 0.4 {
            // Inner 40%: solid brand blue (midpoint of old gradient)
            return .dictusGradientStart
        } else {
            // Outer 60%: adaptive color with opacity decreasing toward edges
            let opacity = Double(1.0 - distanceFromCenter) * 0.9 + 0.15
            let barColor: Color = colorScheme == .dark ? .white : .gray
            return barColor.opacity(opacity)
        }
    }
}

#Preview("Idle") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(energyLevels: Array(repeating: Float(0), count: 30))
    }
}

#Preview("Active") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(energyLevels: (0..<30).map { _ in
            Float.random(in: 0.2...0.8)
        })
    }
}

#Preview("Processing") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(maxHeight: 120, animation: .sweep)
            .opacity(0.3)
            .padding(.horizontal)
    }
}
#endif
