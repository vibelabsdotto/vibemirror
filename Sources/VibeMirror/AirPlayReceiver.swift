import CAirPlay
import Foundation

/// AirPlay mirroring receiver. The iPhone finds it under Control Center → Screen Mirroring.
/// Protocol handling (pairing, FairPlay, decryption) comes from UxPlay's lib via CAirPlay.
final class AirPlayReceiver: @unchecked Sendable {
    enum State: Equatable {
        case stopped
        case waiting
        case connected(String)
        case mirroring(String)
    }

    let name: String
    let video = VideoDecoder()
    let audio = AudioPlayer()

    /// Main queue.
    var onStateChange: ((State) -> Void)?
    private(set) var state = State.stopped {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    private var clientName = "iPhone"
    private var dnssdSources: [DispatchSourceRead] = []
    private var lastHeartbeat = Date()
    private var watchdog: Timer?

    init(name: String) {
        self.name = name
    }

    func start() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeMirror", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let keyfile = support.appendingPathComponent("airplay.pem").path

        // The client scales to the requested height and adapts the width to the phone's shape.
        // 3840x2160 matches UxPlay's H.265 default; a portrait iPhone then arrives about 1000x2160.
        let defaults = UserDefaults.standard
        let width = defaults.integer(forKey: "airplayWidth").nonZero ?? 3840
        let height = defaults.integer(forKey: "airplayHeight").nonZero ?? 2160
        let fps = defaults.integer(forKey: "airplayFPS").nonZero ?? 60

        let status = vm_airplay_start(name, Self.stableMAC(), keyfile, Int32(width), Int32(height), Int32(fps), makeCallbacks())
        guard status == 0 else { throw AirPlayError.startFailed(Int(status)) }

        serviceBonjour()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkHeartbeat() }
        state = .waiting
    }

    func stop() {
        watchdog?.invalidate()
        dnssdSources.forEach { $0.cancel() }
        dnssdSources = []
        vm_airplay_stop()
        video.reset()
        audio.stop()
        state = .stopped
    }

    // MARK: Events (main queue)

    private func clientConnected(_ name: String) {
        clientName = name.isEmpty ? "iPhone" : name
        lastHeartbeat = Date()
        if case .waiting = state { state = .connected(clientName) }
    }

    private func mirrorRunning(_ running: Bool) {
        lastHeartbeat = Date()
        if running {
            state = .mirroring(clientName)
        } else {
            video.reset()
            audio.stop()
            if case .mirroring = state { state = .waiting }
        }
    }

    private func connectionLost() {
        video.reset()
        audio.stop()
        vm_airplay_reset()
        state = .waiting
    }

    private func checkHeartbeat() {
        // Clients send feedback every 2 s; UxPlay resets after 15 s of silence.
        if case .mirroring = state, Date().timeIntervalSince(lastHeartbeat) > 15 {
            connectionLost()
        }
    }

    private func serviceBonjour() {
        for service in [0, 1] {
            let fd = vm_airplay_dnssd_fd(Int32(service))
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak source] in
                if vm_airplay_dnssd_process(Int32(service)) != 0 { source?.cancel() }
            }
            source.resume()
            dnssdSources.append(source)
        }
    }

    // MARK: C bridge

    private func makeCallbacks() -> vm_airplay_callbacks {
        var cb = vm_airplay_callbacks()
        cb.ctx = Unmanaged.passUnretained(self).toOpaque()
        cb.client_connected = { ctx, name, model in
            let me = AirPlayReceiver.from(ctx)
            let name = name.map { String(cString: $0) } ?? ""
            DispatchQueue.main.async { me.clientConnected(name) }
        }
        cb.mirror_running = { ctx, running in
            let me = AirPlayReceiver.from(ctx)
            DispatchQueue.main.async { me.mirrorRunning(running) }
        }
        cb.video_frame = { ctx, bytes, length, hevc in
            guard let bytes, length > 0 else { return }
            AirPlayReceiver.from(ctx).video.decode(Data(bytes: bytes, count: Int(length)), hevc: hevc)
        }
        cb.audio_format = { ctx, type, samples in
            AirPlayReceiver.from(ctx).audio.configure(compressionType: Int(type), samplesPerFrame: Int(samples))
        }
        cb.audio_packet = { ctx, bytes, length in
            guard let bytes, length > 0 else { return }
            AirPlayReceiver.from(ctx).audio.play(Data(bytes: bytes, count: Int(length)))
        }
        cb.audio_volume = { ctx, decibels in
            AirPlayReceiver.from(ctx).audio.setClientVolume(decibels: decibels)
        }
        cb.heartbeat = { ctx in
            let me = AirPlayReceiver.from(ctx)
            DispatchQueue.main.async { me.lastHeartbeat = Date() }
        }
        cb.connection_lost = { ctx in
            let me = AirPlayReceiver.from(ctx)
            DispatchQueue.main.async { me.connectionLost() }
        }
        cb.log = { _, level, message in
            #if DEBUG
            if level <= 6, let message { fputs("[airplay] \(String(cString: message))\n", stderr) }
            #endif
        }
        return cb
    }

    private static func from(_ ctx: UnsafeMutableRawPointer?) -> AirPlayReceiver {
        Unmanaged<AirPlayReceiver>.fromOpaque(ctx!).takeUnretainedValue()
    }

    /// A locally administered MAC, generated once. The client uses it as the receiver's identity.
    private static func stableMAC() -> String {
        let key = "airplayDeviceID"
        if let mac = UserDefaults.standard.string(forKey: key) { return mac }
        var bytes = (0..<6).map { _ in UInt8.random(in: 0...255) }
        bytes[0] = (bytes[0] & ~0x01) | 0x02
        let mac = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        UserDefaults.standard.set(mac, forKey: key)
        return mac
    }
}

enum AirPlayError: LocalizedError {
    case startFailed(Int)

    var errorDescription: String? {
        switch self {
        case .startFailed(let code): "The AirPlay receiver could not start (error \(code))."
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
