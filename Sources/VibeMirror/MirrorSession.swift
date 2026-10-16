import AVFoundation
import CoreImage

/// One live capture of an iOS device screen: video into a preview layer,
/// audio to the Mac's default output, single frames on demand for screenshots.
final class MirrorSession {
    let device: AVCaptureDevice
    let previewLayer: AVCaptureVideoPreviewLayer

    /// Called on the main queue with the screen size in device pixels.
    /// Fires again when the phone rotates.
    var onScreenSizeChange: ((CGSize) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "to.vibelabs.vibemirror.session")
    private let audioOutput = AVCaptureAudioPreviewOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let grabber = FrameGrabber()
    private var videoPort: AVCaptureInput.Port?
    private var formatObserver: NSObjectProtocol?

    init(device: AVCaptureDevice) throws {
        self.device = device
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw MirrorError.cannotAttach(device.localizedName)
        }
        session.addInput(input)

        audioOutput.volume = 1
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        session.commitConfiguration()

        videoPort = input.ports.first { $0.mediaType == .video }
        formatObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureInput.Port.formatDescriptionDidChangeNotification,
            object: videoPort,
            queue: .main
        ) { [weak self] _ in self?.publishScreenSize() }
    }

    deinit {
        if let formatObserver { NotificationCenter.default.removeObserver(formatObserver) }
        let session = session
        queue.async { session.stopRunning() }
    }

    func start() {
        queue.async { [session] in session.startRunning() }
        publishScreenSize()
    }

    var isMuted: Bool {
        get { audioOutput.volume == 0 }
        set { audioOutput.volume = newValue ? 0 : 1 }
    }

    /// Next video frame as a CGImage in device pixels.
    func captureFrame(_ completion: @escaping (CGImage?) -> Void) {
        grabber.request(from: videoOutput, completion: completion)
    }

    private func publishScreenSize() {
        guard let description = videoPort?.formatDescription else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(description)
        guard dims.width > 0, dims.height > 0 else { return }
        onScreenSizeChange?(CGSize(width: Int(dims.width), height: Int(dims.height)))
    }
}

enum MirrorError: LocalizedError {
    case cannotAttach(String)

    var errorDescription: String? {
        switch self {
        case .cannotAttach(let name): "Could not attach to \(name). Is another app (QuickTime, OBS) using it?"
        }
    }
}

/// Grabs exactly one frame per request. The delegate is attached only while a
/// request is pending, so the video data output costs nothing the rest of the time.
private final class FrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "to.vibelabs.vibemirror.frames")
    private let context = CIContext()
    private var pending: [(CGImage?) -> Void] = []

    func request(from output: AVCaptureVideoDataOutput, completion: @escaping (CGImage?) -> Void) {
        queue.async { [self] in
            pending.append(completion)
            if pending.count == 1 { output.setSampleBufferDelegate(self, queue: queue) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !pending.isEmpty, let pixels = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        let cgImage = context.createCGImage(image, from: image.extent)
        let callbacks = pending
        pending.removeAll()
        (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
        DispatchQueue.main.async { callbacks.forEach { $0(cgImage) } }
    }
}
