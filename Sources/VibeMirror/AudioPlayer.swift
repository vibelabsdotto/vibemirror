import AVFoundation

/// Decodes AirPlay audio (AAC-ELD while mirroring, AAC-LC or ALAC for audio-only)
/// and plays it through the Mac's default output.
final class AudioPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "to.vibelabs.vibemirror.audio")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let output = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private var converter: AVAudioConverter?
    private var framesPerPacket: AVAudioFrameCount = 480
    private var clientVolume: Float = 1
    private var muted = false
    private var queuedFrames: AVAudioFrameCount = 0
    /// Drop packets instead of letting latency grow when the client runs ahead of the Mac clock.
    private let maxQueuedFrames: AVAudioFrameCount = 44100 / 4

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: output)
    }

    var isMuted: Bool {
        get { queue.sync { muted } }
        set { queue.async { self.muted = newValue; self.applyVolume() } }
    }

    /// compressionType as reported by the client: 2 = ALAC, 4 = AAC-LC, 8 = AAC-ELD.
    func configure(compressionType: Int, samplesPerFrame: Int) {
        queue.async { self.makeConverter(compressionType, samplesPerFrame) }
    }

    /// AirPlay sends -30...0 dB, and -144 for mute.
    func setClientVolume(decibels: Float) {
        queue.async {
            self.clientVolume = decibels <= -144 ? 0 : pow(10, max(-30, min(0, decibels)) / 20)
            self.applyVolume()
        }
    }

    func play(_ packet: Data) {
        queue.async { self.decode(packet) }
    }

    func stop() {
        queue.async {
            self.player.stop()
            self.engine.stop()
            self.converter = nil
            self.queuedFrames = 0
        }
    }

    private func applyVolume() {
        player.volume = muted ? 0 : clientVolume
    }

    private func makeConverter(_ type: Int, _ samplesPerFrame: Int) {
        var description = AudioStreamBasicDescription()
        description.mSampleRate = 44100
        description.mChannelsPerFrame = 2
        let cookie: [UInt8]
        switch type {
        case 8:
            description.mFormatID = kAudioFormatMPEG4AAC_ELD
            description.mFramesPerPacket = 480
            cookie = [0xF8, 0xE8, 0x50, 0x00]
        case 4:
            description.mFormatID = kAudioFormatMPEG4AAC
            description.mFramesPerPacket = 1024
            cookie = [0x12, 0x10]
        case 2:
            description.mFormatID = kAudioFormatAppleLossless
            description.mFormatFlags = kAppleLosslessFormatFlag_16BitSourceData
            description.mFramesPerPacket = 352
            cookie = [0x00, 0x00, 0x00, 0x24, 0x61, 0x6C, 0x61, 0x63, 0x00, 0x00, 0x00, 0x00,
                      0x00, 0x00, 0x01, 0x60, 0x00, 0x10, 0x28, 0x0A, 0x0E, 0x02, 0x00, 0xFF,
                      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAC, 0x44]
        default:
            converter = nil
            return
        }
        if samplesPerFrame > 0 { description.mFramesPerPacket = UInt32(samplesPerFrame) }
        framesPerPacket = description.mFramesPerPacket

        guard let input = AVAudioFormat(streamDescription: &description),
              let converter = AVAudioConverter(from: input, to: output) else {
            self.converter = nil
            return
        }
        converter.magicCookie = Data(cookie)
        self.converter = converter
    }

    private func decode(_ packet: Data) {
        guard let converter, !packet.isEmpty, queuedFrames < maxQueuedFrames else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
            applyVolume()
            player.play()
        }

        let compressed = AVAudioCompressedBuffer(format: converter.inputFormat, packetCapacity: 1, maximumPacketSize: packet.count)
        packet.copyBytes(to: compressed.data.assumingMemoryBound(to: UInt8.self), count: packet.count)
        compressed.byteLength = UInt32(packet.count)
        compressed.packetCount = 1
        compressed.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))

        guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: framesPerPacket) else { return }
        var delivered = false
        let status = converter.convert(to: pcm, error: nil) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return compressed
        }
        guard status != .error, pcm.frameLength > 0 else { return }
        let frames = pcm.frameLength
        queuedFrames += frames
        player.scheduleBuffer(pcm) { [weak self] in
            self?.queue.async { self?.queuedFrames -= min(frames, self?.queuedFrames ?? 0) }
        }
    }
}
