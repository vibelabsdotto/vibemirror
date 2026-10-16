# AGENTS.md

VibeMirror is a view-only iPhone screen mirror for macOS. The main path is an AirPlay receiver (UxPlay's protocol code plus VideoToolbox and AVAudioEngine). A USB fallback captures the phone through the CoreMediaIO screen capture opt-in. Both render into a Simulator-style device frame.

## Layout

| Path | Purpose |
|---|---|
| `Sources/CAirPlay/uxplay/` | Vendored UxPlay `lib/` (GPL-3.0). Keep unmodified; record the commit in `UPSTREAM.md` when updating |
| `Sources/CAirPlay/vm_airplay.c` | C shim: starts the receiver, forwards callbacks |
| `Sources/VibeMirror/AirPlayReceiver.swift` | Receiver lifecycle, Bonjour sockets, heartbeat watchdog |
| `Sources/VibeMirror/VideoDecoder.swift` | Annex-B H.264/H.265 → VideoToolbox → display layer |
| `Sources/VibeMirror/AudioPlayer.swift` | AAC-ELD / AAC-LC / ALAC → AVAudioEngine |
| `Sources/VibeMirror/DeviceMonitor.swift`, `MirrorSession.swift` | USB capture path |
| `Sources/VibeMirror/DeviceGeometry.swift`, `DeviceFrameView.swift` | Device chrome |
| `Sources/VibeMirror/AppController.swift` | Window, menus, source selection (AirPlay before USB) |
| `scripts/build-deps.sh` | Static universal libcrypto and libplist into `.deps/` |
| `Resources/` | `Info.plist`, entitlements, icon (regenerate with `make icon`) |

## Rules

- Build and run with `make run`. `swift run` crashes on the camera prompt because the binary has no bundle.
- Debug builds print UxPlay log lines to stderr with an `[airplay]` prefix. Run the binary directly to see them.
- `dns-sd -B _airplay._tcp` shows whether the receiver is advertised.
- A real AirPlay or USB session needs a physical iPhone. Without one, verify what you can (advertisement, `/info`, decoder with a synthetic stream) and say what stayed untested.
- No control/input injection. View only is the scope.
- Swift 5 language mode, macOS 14 minimum. Never link Homebrew libraries directly; they are single-arch and built for the host macOS version.
- The project is GPL-3.0 because of UxPlay. Do not relicense.
- Releases: bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, then `make release && make publish`.
