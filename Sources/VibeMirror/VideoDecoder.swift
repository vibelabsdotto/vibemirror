import AVFoundation
import CoreImage
import VideoToolbox

/// Decodes the Annex-B H.264/H.265 stream an AirPlay client sends and shows it
/// in an AVSampleBufferDisplayLayer. All decode work runs on one serial queue.
final class VideoDecoder: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()

    /// Main queue, decoded frame size in pixels. Changes when the phone rotates.
    var onSizeChange: ((CGSize) -> Void)?

    private let queue = DispatchQueue(label: "to.vibelabs.vibemirror.video")
    private var parameterSets: [Data] = []
    private var format: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var lastSize = CGSize.zero
    private var lastFrame: CVPixelBuffer?
    private let ciContext = CIContext()

    init() {
        layer.videoGravity = .resizeAspect
    }

    func decode(_ data: Data, hevc: Bool) {
        queue.async { self.process(data, hevc: hevc) }
    }

    func reset() {
        queue.async {
            self.invalidateSession()
            self.parameterSets = []
            self.format = nil
            self.lastFrame = nil
            self.layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        }
    }

    /// Most recent decoded frame, delivered on the main queue.
    func captureFrame(_ completion: @escaping (CGImage?) -> Void) {
        queue.async {
            let image = self.lastFrame.flatMap { buffer -> CGImage? in
                let ci = CIImage(cvPixelBuffer: buffer)
                return self.ciContext.createCGImage(ci, from: ci.extent)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    // MARK: Decoding

    private func process(_ data: Data, hevc: Bool) {
        var newParameterSets: [Data] = []
        var slices: [Data] = []
        for nal in Self.splitAnnexB(data) {
            guard let header = nal.first else { continue }
            let isParameterSet = hevc
                ? (32...34).contains((header >> 1) & 0x3F)  // VPS, SPS, PPS
                : [7, 8].contains(header & 0x1F)            // SPS, PPS
            if isParameterSet { newParameterSets.append(nal) } else { slices.append(nal) }
        }

        if !newParameterSets.isEmpty, newParameterSets != parameterSets {
            parameterSets = newParameterSets
            format = Self.makeFormat(parameterSets, hevc: hevc)
            invalidateSession()
        }
        guard !slices.isEmpty, let format else { return }
        if session == nil { session = makeSession(format) }
        guard let session, let sample = Self.makeSampleBuffer(slices, format: format) else { return }

        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { [weak self] status, _, image, _, _ in
            guard status == noErr, let image, let self else { return }
            self.display(image)
        }
    }

    private func display(_ pixels: CVImageBuffer) {
        lastFrame = pixels
        let size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
        if size != lastSize {
            lastSize = size
            DispatchQueue.main.async { self.onSizeChange?(size) }
        }

        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &description)
        guard let description else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        Self.markDisplayImmediately(sample)

        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }

    private func makeSession(_ format: CMVideoFormatDescription) -> VTDecompressionSession? {
        var session: VTDecompressionSession?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: nil,
                                     imageBufferAttributes: attributes, outputCallback: nil, decompressionSessionOut: &session)
        return session
    }

    private func invalidateSession() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
    }

    // MARK: Bitstream helpers

    /// Splits on 3- or 4-byte start codes. Emulation prevention guarantees no start code inside a NAL.
    static func splitAnnexB(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var nals: [Data] = []
        var start: Int?
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                if let s = start {
                    var end = i
                    if end > s, bytes[end - 1] == 0 { end -= 1 }
                    if end > s { nals.append(Data(bytes[s..<end])) }
                }
                i += 3
                start = i
            } else {
                i += 1
            }
        }
        if let s = start, s < bytes.count { nals.append(Data(bytes[s...])) }
        return nals
    }

    private static func makeFormat(_ sets: [Data], hevc: Bool) -> CMVideoFormatDescription? {
        var format: CMVideoFormatDescription?
        let arrays = sets.map { [UInt8]($0) }
        var pointers: [UnsafePointer<UInt8>] = []
        var sizes: [Int] = []
        var buffers: [UnsafeMutableBufferPointer<UInt8>] = []
        for array in arrays {
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: array.count)
            _ = buffer.initialize(from: array)
            buffers.append(buffer)
            pointers.append(UnsafePointer(buffer.baseAddress!))
            sizes.append(array.count)
        }
        defer { buffers.forEach { $0.deallocate() } }

        let status = hevc
            ? CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: sets.count, parameterSetPointers: pointers,
                                                                 parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &format)
            : CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: sets.count, parameterSetPointers: pointers,
                                                                 parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
        return status == noErr ? format : nil
    }

    /// Converts NAL units to one length-prefixed (AVCC/HVCC) access unit.
    private static func makeSampleBuffer(_ nals: [Data], format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var payload = Data(capacity: nals.reduce(0) { $0 + $1.count + 4 })
        for nal in nals {
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
            payload.append(nal)
        }

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: payload.count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: payload.count, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = payload.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count) }
        guard copied == noErr else { return nil }

        var sample: CMSampleBuffer?
        var size = payload.count
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 0,
                                  sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        return sample
    }

    private static func markDisplayImmediately(_ sample: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
}
