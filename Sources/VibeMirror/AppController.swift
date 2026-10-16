import AppKit
import AVFoundation

/// Window, menus and source selection. AirPlay is the main path; a USB-connected
/// device is used only while nothing mirrors over AirPlay.
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private enum Zoom { case fit, actual, pixels }

    private let airplay = AirPlayReceiver(name: "VibeMirror")
    private let monitor = DeviceMonitor()
    private let frameView = DeviceFrameView(frame: NSRect(x: 0, y: 0, width: 300, height: 620))
    private var window: NSWindow!
    private var usbSession: MirrorSession?
    private var airplayError: String?
    private let deviceMenu = NSMenu(title: "Device")

    private let topInset: CGFloat = 28
    private let selectedDeviceKey = "selectedDeviceID"
    private let muteKey = "muted"
    private let floatKey = "keepOnTop"

    private var isMuted: Bool { UserDefaults.standard.bool(forKey: muteKey) }
    private var isAirPlayMirroring: Bool {
        if case .mirroring = airplay.state { return true }
        return false
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()

        airplay.audio.isMuted = isMuted
        airplay.video.onSizeChange = { [weak self] size in
            guard let self, self.isAirPlayMirroring else { return }
            self.screenSizeChanged(size)
        }
        airplay.onStateChange = { [weak self] _ in self?.sourcesChanged() }
        do {
            try airplay.start()
        } catch {
            airplayError = error.localizedDescription
        }

        monitor.onChange = { [weak self] _ in self?.usbDevicesChanged() }
        monitor.refresh()
        sourcesChanged()
    }

    func applicationWillTerminate(_ notification: Notification) {
        airplay.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Window

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 620 + topInset),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "VibeMirror"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.setFrameAutosaveName("MirrorWindow")
        window.level = UserDefaults.standard.bool(forKey: floatKey) ? .floating : .normal

        let content = NSView()
        content.addSubview(frameView)
        frameView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            frameView.topAnchor.constraint(equalTo: content.topAnchor, constant: topInset),
            frameView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            frameView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            frameView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content

        if !window.setFrameUsingName("MirrorWindow") {
            apply(zoom: .fit)
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let g = frameView.geometry.bounds
        return NSSize(width: frameSize.width, height: frameSize.width * g.height / g.width + topInset)
    }

    private func apply(zoom: Zoom) {
        let g = frameView.geometry
        let pointsPerPixel: CGFloat
        switch zoom {
        case .fit:
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
            pointsPerPixel = min((visible.height * 0.85 - topInset) / g.bounds.height, visible.width * 0.85 / g.bounds.width)
        case .actual:
            // AirPlay streams are scaled, so size by the typical screen width in points.
            let points: CGFloat = g.kind == .tablet ? 820 : 402
            pointsPerPixel = points / g.screenShortSide
        case .pixels:
            pointsPerPixel = 1 / window.backingScaleFactor
        }
        resizeWindow(pointsPerPixel: pointsPerPixel)
    }

    private func resizeWindow(pointsPerPixel: CGFloat) {
        let g = frameView.geometry.bounds
        let size = NSSize(width: (g.width * pointsPerPixel).rounded(), height: (g.height * pointsPerPixel).rounded() + topInset)
        var frame = window.frame
        frame.origin.y += frame.height - size.height  // keep the top edge in place
        frame.size = size
        if let visible = window.screen?.visibleFrame {
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        }
        window.setFrame(frame, display: true, animate: false)
    }

    private func screenSizeChanged(_ size: CGSize) {
        let old = frameView.geometry
        let new = DeviceGeometry(screenSize: size)
        guard new != old else { return }
        // Keep the on-screen size; on rotation the window swaps its proportions.
        let pointsPerPixel = old.fitScale(in: frameView.bounds.size) * old.screenShortSide / new.screenShortSide
        frameView.geometry = new
        resizeWindow(pointsPerPixel: pointsPerPixel)
    }

    // MARK: Sources

    private func sourcesChanged() {
        rebuildDeviceMenu()

        if case .mirroring(let client) = airplay.state {
            usbSession = nil
            frameView.contentLayer = airplay.video.layer
            window.title = client
            return
        }
        if let usbSession {
            frameView.contentLayer = usbSession.previewLayer
            window.title = usbSession.device.localizedName
            return
        }

        frameView.contentLayer = nil
        window.title = "VibeMirror"
        if let airplayError {
            frameView.message = airplayError
        } else if case .connected(let client) = airplay.state {
            frameView.message = "\(client) is connecting…"
        } else {
            frameView.message = "On your iPhone, open Control Center, tap Screen Mirroring and choose \"\(airplay.name)\".\n\niPhone and Mac need to be on the same Wi-Fi."
        }
    }

    private func usbDevicesChanged() {
        if let current = usbSession?.device, !monitor.devices.contains(where: { $0.uniqueID == current.uniqueID }) {
            usbSession = nil
        }
        guard usbSession == nil, !isAirPlayMirroring else { return sourcesChanged() }

        let preferred = UserDefaults.standard.string(forKey: selectedDeviceKey)
        if let device = monitor.devices.first(where: { $0.uniqueID == preferred }) ?? monitor.devices.first {
            startUSB(device)
        } else {
            sourcesChanged()
        }
    }

    /// macOS files a USB iPhone under cameras, so the permission is asked only once one is plugged in.
    private func startUSB(_ device: AVCaptureDevice) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.frameView.message = "Camera access is off.\n\nmacOS treats a USB iPhone like a camera. Allow VibeMirror under System Settings → Privacy & Security → Camera."
                    return
                }
                do {
                    let session = try MirrorSession(device: device)
                    session.isMuted = self.isMuted
                    session.onScreenSizeChange = { [weak self] size in
                        guard let self, self.usbSession === session, !self.isAirPlayMirroring else { return }
                        self.screenSizeChanged(size)
                    }
                    self.usbSession = session
                    UserDefaults.standard.set(device.uniqueID, forKey: self.selectedDeviceKey)
                    session.start()
                } catch {
                    self.frameView.message = error.localizedDescription
                }
                self.sourcesChanged()
            }
        }
    }

    // MARK: Actions

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AVCaptureDevice else { return }
        usbSession = nil
        startUSB(device)
    }

    @objc private func refreshDevices(_ sender: Any?) {
        DeviceMonitor.allowScreenCaptureDevices()
        monitor.refresh()
        usbDevicesChanged()
    }

    @objc private func saveScreenshot(_ sender: Any?) {
        let name = window.title
        let handler: (CGImage?) -> Void = { image in
            guard let image else { NSSound.beep(); return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let file = "VibeMirror Screenshot - \(name) - \(formatter.string(from: Date())).png"
                .replacingOccurrences(of: "/", with: "-")
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .png, properties: [:]) else { NSSound.beep(); return }
            do {
                try data.write(to: desktop.appendingPathComponent(file))
                NSSound(named: "Tink")?.play()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if isAirPlayMirroring {
            airplay.video.captureFrame(handler)
        } else if let usbSession {
            usbSession.captureFrame(handler)
        } else {
            NSSound.beep()
        }
    }

    @objc private func zoomFit(_ sender: Any?) { apply(zoom: .fit) }
    @objc private func zoomActual(_ sender: Any?) { apply(zoom: .actual) }
    @objc private func zoomPixels(_ sender: Any?) { apply(zoom: .pixels) }

    @objc private func toggleKeepOnTop(_ sender: Any?) {
        let enabled = !UserDefaults.standard.bool(forKey: floatKey)
        UserDefaults.standard.set(enabled, forKey: floatKey)
        window.level = enabled ? .floating : .normal
    }

    @objc private func toggleMute(_ sender: Any?) {
        let muted = !isMuted
        UserDefaults.standard.set(muted, forKey: muteKey)
        usbSession?.isMuted = muted
        airplay.audio.isMuted = muted
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleKeepOnTop(_:)):
            item.state = UserDefaults.standard.bool(forKey: floatKey) ? .on : .off
        case #selector(toggleMute(_:)):
            item.state = isMuted ? .on : .off
        case #selector(saveScreenshot(_:)):
            return isAirPlayMirroring || usbSession != nil
        default:
            break
        }
        return true
    }

    // MARK: Menu

    private func buildMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About VibeMirror", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide VibeMirror", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit VibeMirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: app, title: "VibeMirror")

        let file = NSMenu(title: "File")
        file.addItem(item("Save Screenshot", #selector(saveScreenshot(_:)), "s"))
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: file, title: "File")

        main.addItem(submenu: deviceMenu, title: "Device")

        let view = NSMenu(title: "Window")
        view.addItem(item("Fit Screen", #selector(zoomFit(_:)), "1"))
        view.addItem(item("Actual Size", #selector(zoomActual(_:)), "2"))
        view.addItem(item("Pixel Accurate", #selector(zoomPixels(_:)), "3"))
        view.addItem(.separator())
        let onTop = item("Keep on Top", #selector(toggleKeepOnTop(_:)), "t")
        onTop.keyEquivalentModifierMask = [.command, .option]
        view.addItem(onTop)
        let mute = item("Mute Audio", #selector(toggleMute(_:)), "m")
        mute.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(mute)
        view.addItem(.separator())
        view.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: view, title: "Window")
        NSApp.windowsMenu = view

        NSApp.mainMenu = main
        rebuildDeviceMenu()
    }

    private func rebuildDeviceMenu() {
        deviceMenu.removeAllItems()

        let airplayTitle: String
        switch airplay.state {
        case .mirroring(let client): airplayTitle = "AirPlay: \(client)"
        case .connected(let client): airplayTitle = "AirPlay: \(client) connecting"
        case .waiting: airplayTitle = "AirPlay: waiting as \"\(airplay.name)\""
        case .stopped: airplayTitle = "AirPlay: off"
        }
        let airplayItem = NSMenuItem(title: airplayTitle, action: nil, keyEquivalent: "")
        airplayItem.isEnabled = false
        airplayItem.state = isAirPlayMirroring ? .on : .off
        deviceMenu.addItem(airplayItem)

        deviceMenu.addItem(.separator())
        if monitor.devices.isEmpty {
            let empty = NSMenuItem(title: "No USB Devices", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            deviceMenu.addItem(empty)
        }
        for device in monitor.devices {
            let entry = item("USB: \(device.localizedName)", #selector(selectDevice(_:)), "")
            entry.representedObject = device
            entry.state = !isAirPlayMirroring && device.uniqueID == usbSession?.device.uniqueID ? .on : .off
            deviceMenu.addItem(entry)
        }
        deviceMenu.addItem(.separator())
        deviceMenu.addItem(item("Refresh USB Devices", #selector(refreshDevices(_:)), "r"))
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        submenu.title = title
        item.submenu = submenu
        addItem(item)
    }
}
