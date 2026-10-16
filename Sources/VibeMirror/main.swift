import AppKit
import AVFoundation

// `VibeMirror --list` prints the iOS devices macOS exposes, then exits.
// Useful to tell a cabling/trust problem apart from an app problem.
if CommandLine.arguments.contains("--list") {
    let monitor = DeviceMonitor()
    print("Screen capture opt-in:", DeviceMonitor.allowScreenCaptureDevices() ? "ok" : "failed")
    RunLoop.main.run(until: Date().addingTimeInterval(3))  // devices appear asynchronously
    monitor.refresh()
    if monitor.devices.isEmpty {
        print("No iOS devices found. Connect via USB, unlock, and tap Trust.")
    }
    for device in monitor.devices {
        print("\(device.localizedName)\t\(device.modelID)\t\(device.uniqueID)")
    }
    exit(0)
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
