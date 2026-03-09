// DictusApp/Audio/RawAudioCapture.swift
// Lightweight audio capture using native AVAudioEngine (no WhisperKit dependency).
// Used during cold start to record audio while WhisperKit loads in parallel.
import Foundation
@preconcurrency import AVFoundation
import DictusCore

/// Lightweight audio capture that starts in <100ms without WhisperKit.
///
/// WHY this exists:
/// WhisperKit takes 3-4s to initialize on cold start. During that time, the user
/// is waiting with no recording happening. RawAudioCapture uses a plain AVAudioEngine
/// to start recording immediately. The captured samples are later passed to
/// WhisperKit's `transcribe(audioArray:)` once it finishes loading.
///
/// WHY a separate AVAudioEngine (not WhisperKit's AudioProcessor):
/// WhisperKit's AudioProcessor requires a fully initialized WhisperKit instance.
/// We need to capture audio BEFORE WhisperKit exists. This engine is stopped
/// before WhisperKit's warmUp() to avoid two engines running simultaneously.
@MainActor
class RawAudioCapture: ObservableObject {
    /// Energy levels (0.0-1.0) for waveform visualization, matching AudioRecorder's format.
    @Published var bufferEnergy: [Float] = []

    /// Elapsed recording time in seconds.
    @Published var bufferSeconds: Double = 0

    /// Whether capture is currently active.
    private(set) var isCapturing = false

    private let engine = AVAudioEngine()

    /// Accumulated audio samples in 16kHz mono Float32 (WhisperKit's expected format).
    private var audioSamples: [Float] = []

    /// Converter from hardware sample rate (typically 48kHz) to 16kHz mono.
    /// WHY nonisolated(unsafe): This is written once from the main thread in startCapture()
    /// and read from the audio callback thread in processBuffer(). The write always completes
    /// before the audio tap is installed, so there's no race condition.
    private nonisolated(unsafe) var converter: AVAudioConverter?

    /// Target format: 16kHz mono Float32 — what WhisperKit expects.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// Start capturing audio immediately using native AVAudioEngine.
    /// Requires AVAudioSession to be configured and active beforehand.
    ///
    /// - Throws: If the audio engine fails to start.
    func startCapture() throws {
        guard !isCapturing else { return }

        audioSamples = []
        bufferEnergy = []
        bufferSeconds = 0

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        // Create converter from hardware format to 16kHz mono
        guard let conv = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw NSError(domain: "RawAudioCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter from \(hwFormat) to 16kHz mono"])
        }
        converter = conv

        // Install tap on input node to receive audio buffers
        // WHY bus 0 with hardware format: The input node's output format on bus 0
        // reflects the actual hardware format. We convert to 16kHz in the callback.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        try engine.start()
        isCapturing = true

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("RawAudioCapture started (hw: \(hwFormat.sampleRate)Hz -> 16kHz)")
        }
    }

    /// Stop capturing and return all accumulated samples in 16kHz mono Float32.
    ///
    /// - Returns: Audio samples ready for `whisperKit.transcribe(audioArray:)`.
    func stopCapture() -> [Float] {
        guard isCapturing else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        let samples = audioSamples
        audioSamples = []

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("RawAudioCapture stopped. Samples: \(samples.count), Duration: \(String(format: "%.1f", Double(samples.count) / 16000.0))s")
        }

        // Reset published state
        bufferEnergy = []
        bufferSeconds = 0

        return samples
    }

    // MARK: - Private

    /// Process incoming audio buffer: convert to 16kHz and compute energy for waveform.
    ///
    /// WHY nonisolated: This callback fires on the audio thread. We do the CPU-intensive
    /// conversion here, then dispatch UI updates and sample accumulation to main thread.
    private nonisolated func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        // Calculate how many frames we need in the output buffer
        // WHY this formula: input frames * (target rate / source rate) gives the
        // proportional number of output frames. We add 1 to avoid rounding down.
        let ratio = 16000.0 / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        // Convert from hardware format to 16kHz mono
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            if #available(iOS 14.0, *) {
                DictusLogger.app.warning("Audio conversion error: \(error.localizedDescription)")
            }
            return
        }

        // Extract Float32 samples from the converted buffer
        guard let channelData = outputBuffer.floatChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Compute RMS energy for this buffer (0.0-1.0 range)
        // WHY RMS: Root Mean Square gives a perceptually meaningful energy level,
        // matching what WhisperKit's relativeEnergy provides.
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
        // Scale to approximate WhisperKit's relativeEnergy range
        let energy = min(rms * 5.0, 1.0)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.audioSamples.append(contentsOf: samples)
            self.bufferSeconds = Double(self.audioSamples.count) / 16000.0

            // Maintain a rolling window of energy values (last 30 = matches barCount in BrandWaveform)
            self.bufferEnergy.append(energy)
            if self.bufferEnergy.count > 30 {
                self.bufferEnergy.removeFirst(self.bufferEnergy.count - 30)
            }
        }
    }
}
