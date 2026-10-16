import AVFoundation
import CoreMediaIO

/// Finds iPhones and iPads connected over USB.
///
/// macOS hides iOS screen capture devices until a process opts in through
/// CoreMediaIO. After the opt-in, every trusted iOS device shows up as a muxed
/// (video + audio) AVCaptureDevice, the same source QuickTime Player uses for
/// "New Movie Recording".
final class DeviceMonitor {
    private(set) var devices: [AVCaptureDevice] = []
    var onChange: (([AVCaptureDevice]) -> Void)?

    private let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.external],
        mediaType: .muxed,
        position: .unspecified
    )
    private var observers: [NSObjectProtocol] = []

    init() {
        Self.allowScreenCaptureDevices()

        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func refresh() {
        let found = discovery.devices.filter(Self.isIOSScreen)
        guard found.map(\.uniqueID) != devices.map(\.uniqueID) else { return }
        devices = found
        onChange?(found)
    }

    static func isIOSScreen(_ device: AVCaptureDevice) -> Bool {
        device.hasMediaType(.muxed) && device.modelID.hasPrefix("iOS Device")
    }

    /// The opt-in QuickTime uses. Without it, iOS devices never appear in discovery.
    @discardableResult
    static func allowScreenCaptureDevices() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
        return status == kCMIOHardwareNoError
    }
}
