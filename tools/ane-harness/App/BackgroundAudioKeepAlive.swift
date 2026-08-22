// tools/ane-harness/App/BackgroundAudioKeepAlive.swift
//
// THROWAWAY — #268 D2.
//
// An ordinary iOS app gets suspended seconds after it leaves the foreground, so
// without this the harness could not run backgrounded at all. DictusApp stays
// alive for exactly this reason and by exactly this means — `UIBackgroundModes:
// audio` in Info.plist plus an AVAudioEngine that never stops — so reproducing
// it here is not a trick to keep the benchmark running: it is part of the state
// under test. The engine also costs the memory a real dictation costs, which the
// footprint readings should see.
import AVFoundation
import DictusCore

final class BackgroundAudioKeepAlive {

    private let engine = AVAudioEngine()
    private var player: AVAudioPlayerNode?

    enum StartError: Error, CustomStringConvertible {
        case silentBufferUnavailable
        case session(String)

        public var description: String {
            switch self {
            case .silentBufferUnavailable: return "could not build the silent buffer"
            case .session(let message): return message
            }
        }
    }

    /// Configure the session and start a silent tone.
    ///
    /// Throws rather than reporting, because a failure here does not degrade the
    /// measurement — it invalidates it. Without the audio background mode holding
    /// the process, iOS suspends the app seconds after it leaves the foreground,
    /// and whatever the benchmark then reports is not a backgrounded run.
    func start() throws -> String {
        do {
            let session = AVAudioSession.sharedInstance()
            // `.playAndRecord` mirrors DictusApp, which records. `.mixWithOthers`
            // so the harness does not stop whatever the maintainer is listening to.
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let player = AVAudioPlayerNode()
            self.player = player
            let format = engine.outputNode.inputFormat(forBus: 0)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            guard let buffer = Self.silentBuffer(format: format) else {
                throw StartError.silentBufferUnavailable
            }
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            return "audio keep-alive: running (playAndRecord, silent loop)"
        } catch let error as StartError {
            throw error
        } catch {
            throw StartError.session(error.localizedDescription)
        }
    }

    private static func silentBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            guard let data = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frames) { data[frame] = 0 }
        }
        return buffer
    }
}
