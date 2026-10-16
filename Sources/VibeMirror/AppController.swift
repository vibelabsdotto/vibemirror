import AppKit
import AVFoundation

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private enum Zoom { case fit, points, pixels }

    private let monitor = DeviceMonitor()
    private let frameView = DeviceFrameView(frame: NSRect(x: 0, y: 0, width: 300, height: 620))
    private var window: NSWindow!
    private var session: MirrorSession?
    private var accessGranted = false
    private let deviceMenu = NSMenu(title: "Device")

    private let topInset: CGFloat = 28
    private let selectedDeviceKey = "selectedDeviceID"
    private let muteKey = "muted"
    private let floatKey = "keepOnTop"

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        frameView.message = "Looking for devices…"

        monitor.onChange = { [weak self] _ in self?.devicesChanged() }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                self.accessGranted = granted
                self.monitor.refresh()
                self.devicesChanged()
            }
        }
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
        case .points:
            pointsPerPixel = 1 / Self.deviceScale(for: g)
        case .pixels:
            pointsPerPixel = 1 / (window.backingScaleFactor)
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

    private static func deviceScale(for g: DeviceGeometry) -> CGFloat {
        let short = min(g.screenSize.width, g.screenSize.height)
        return g.kind != .tablet && short >= 1080 ? 3 : 2
    }

    // MARK: Devices

    private func devicesChanged() {
        rebuildDeviceMenu()
        guard accessGranted else {
            show(message: "Camera access is off.\n\nmacOS treats a connected iPhone like a camera. Allow VibeMirror under System Settings → Privacy & Security → Camera, then reopen the app.")
            return
        }

        let devices = monitor.devices
        if let current = session?.device, devices.contains(where: { $0.uniqueID == current.uniqueID }) { return }
        stopSession()

        let preferred = UserDefaults.standard.string(forKey: selectedDeviceKey)
        if let device = devices.first(where: { $0.uniqueID == preferred }) ?? devices.first {
            startSession(with: device)
        } else {
            show(message: "Connect your iPhone with a USB cable.\n\nUnlock it and tap Trust if it asks. The screen shows up here a few seconds later.")
        }
    }

    private func startSession(with device: AVCaptureDevice) {
        stopSession()
        do {
            let session = try MirrorSession(device: device)
            session.isMuted = UserDefaults.standard.bool(forKey: muteKey)
            session.onScreenSizeChange = { [weak self] size in self?.screenSizeChanged(size) }
            self.session = session
            frameView.previewLayer = session.previewLayer
            window.title = device.localizedName
            UserDefaults.standard.set(device.uniqueID, forKey: selectedDeviceKey)
            session.start()
        } catch {
            show(message: error.localizedDescription)
        }
        rebuildDeviceMenu()
    }

    private func stopSession() {
        session = nil
        frameView.previewLayer = nil
        window.title = "VibeMirror"
    }

    private func show(message: String) {
        frameView.message = message
    }

    private func screenSizeChanged(_ size: CGSize) {
        let old = frameView.geometry
        let new = DeviceGeometry(screenSize: size)
        guard new != old else { return }
        // Keep the on-screen scale; on rotation the window swaps its proportions.
        let pointsPerPixel = old.fitScale(in: frameView.bounds.size)
        frameView.geometry = new
        resizeWindow(pointsPerPixel: pointsPerPixel)
    }

    // MARK: Actions

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AVCaptureDevice else { return }
        startSession(with: device)
    }

    @objc private func refreshDevices(_ sender: Any?) {
        DeviceMonitor.allowScreenCaptureDevices()
        monitor.refresh()
        devicesChanged()
    }

    @objc private func saveScreenshot(_ sender: Any?) {
        guard let session else { NSSound.beep(); return }
        let name = session.device.localizedName
        session.captureFrame { image in
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
    }

    @objc private func zoomFit(_ sender: Any?) { apply(zoom: .fit) }
    @objc private func zoomPoints(_ sender: Any?) { apply(zoom: .points) }
    @objc private func zoomPixels(_ sender: Any?) { apply(zoom: .pixels) }

    @objc private func toggleKeepOnTop(_ sender: Any?) {
        let enabled = !UserDefaults.standard.bool(forKey: floatKey)
        UserDefaults.standard.set(enabled, forKey: floatKey)
        window.level = enabled ? .floating : .normal
    }

    @objc private func toggleMute(_ sender: Any?) {
        let muted = !UserDefaults.standard.bool(forKey: muteKey)
        UserDefaults.standard.set(muted, forKey: muteKey)
        session?.isMuted = muted
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleKeepOnTop(_:)):
            item.state = UserDefaults.standard.bool(forKey: floatKey) ? .on : .off
        case #selector(toggleMute(_:)):
            item.state = UserDefaults.standard.bool(forKey: muteKey) ? .on : .off
        case #selector(saveScreenshot(_:)):
            return session != nil
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
        view.addItem(item("Point Accurate", #selector(zoomPoints(_:)), "2"))
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
        if monitor.devices.isEmpty {
            let empty = NSMenuItem(title: "No Devices Connected", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            deviceMenu.addItem(empty)
        }
        for device in monitor.devices {
            let entry = item(device.localizedName, #selector(selectDevice(_:)), "")
            entry.representedObject = device
            entry.state = device.uniqueID == session?.device.uniqueID ? .on : .off
            deviceMenu.addItem(entry)
        }
        deviceMenu.addItem(.separator())
        deviceMenu.addItem(item("Refresh Devices", #selector(refreshDevices(_:)), "r"))
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
