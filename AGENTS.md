# AGENTS.md

VibeMirror is a view-only iPhone screen mirror for macOS. It captures a USB-connected iOS device through the CoreMediaIO screen capture opt-in and shows it in a Simulator-style device frame.

## Layout

| Path | Purpose |
|---|---|
| `Sources/VibeMirror/DeviceMonitor.swift` | CoreMediaIO opt-in, device discovery |
| `Sources/VibeMirror/MirrorSession.swift` | `AVCaptureSession`, audio, screenshot frames |
| `Sources/VibeMirror/DeviceGeometry.swift` | Device frame proportions from screen size |
| `Sources/VibeMirror/DeviceFrameView.swift` | Core Animation chrome around the preview layer |
| `Sources/VibeMirror/AppController.swift` | Window, menus, zoom modes |
| `Resources/` | `Info.plist`, entitlements, icon (regenerate with `make icon`) |

## Rules

- Build and run with `make run`. `swift run` crashes on the camera prompt because the binary has no bundle.
- Check device detection with `make list` before debugging UI.
- Real capture needs a physical device on USB. Without one, verify frame layout only and say so.
- No control/input injection. View only is the scope and the reason this works in the EU.
- Swift 5 language mode, macOS 14 minimum, no third-party dependencies.
- Releases: bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, then `make release && make publish`.
