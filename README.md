# VibeMirror

Your iPhone screen in a Simulator-style window on your Mac. View only, over USB, and it works in the EU.

Apple's iPhone Mirroring is not available in the European Union. VibeMirror does something smaller: it shows the live screen of a USB-connected iPhone or iPad inside a device frame, plays its audio on the Mac, and takes screenshots. You can't click or type into the phone. That is by design, and it is also why this works everywhere.

## How it works

macOS has shipped a way to capture an iOS screen over USB since OS X Yosemite. QuickTime Player uses it for "New Movie Recording" with an iPhone selected. The capture devices stay hidden until an app opts in through CoreMediaIO:

```swift
var address = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
var allow: UInt32 = 1
CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, 4, &allow)
```

After that, every trusted iOS device appears as a muxed `AVCaptureDevice` (video and audio). VibeMirror feeds it into an `AVCaptureSession`, renders video with `AVCaptureVideoPreviewLayer` inside a Core Animation device frame, and routes audio through `AVCaptureAudioPreviewOutput`. No private API, no jailbreak, no app on the phone.

| | VibeMirror | Apple iPhone Mirroring |
|---|---|---|
| EU | works | blocked |
| Connection | USB cable | wireless |
| Control from Mac | no | yes |
| Phone screen while mirroring | stays on | locked |

## Requirements

- macOS 14 Sonoma or later
- An iPhone or iPad with a USB cable, unlocked, and set to trust this Mac

## Install

Download the latest zip from [Releases](https://github.com/vibelabsdotto/vibemirror/releases), unzip, and move `VibeMirror.app` to Applications. Builds are signed with a Developer ID and notarized.

On first launch VibeMirror asks for camera access. macOS files a USB iPhone under cameras, so that is the permission it checks.

## Use

Plug in the phone. The screen appears a few seconds later.

| Shortcut | Action |
|---|---|
| ⌘S | Save a screenshot (device pixels, PNG) to the Desktop |
| ⌘1 | Fit the window to the screen |
| ⌘2 | Point accurate (1 iOS point = 1 Mac point) |
| ⌘3 | Pixel accurate |
| ⌥⌘T | Keep on top |
| ⇧⌘M | Mute iPhone audio |
| ⌘R | Rescan devices |

Drag anywhere on the device to move the window. With several devices connected, pick one from the Device menu.

While VibeMirror runs, iPhone audio plays on the Mac instead of the phone. That is how the macOS capture path behaves, QuickTime does the same.

## Build

```sh
make run      # debug build, ad-hoc signed, opens the app
make list     # prints connected iOS devices and exits
make release  # universal build, Developer ID signing, notarization
make publish  # uploads the release zip to GitHub
```

Needs Xcode 16 or later. `make release` reads App Store Connect API credentials from the JSON file in `NOTARY_CONFIG` (keys `apple_key_id`, `apple_issuer_id`, `apple_key_path`).

Opening `Package.swift` in Xcode works for editing. Run through `make run`, though: macOS kills an unbundled binary that asks for the camera without an `Info.plist` usage string.

## Troubleshooting

**No device shows up.** Run `make list` or `VibeMirror.app/Contents/MacOS/VibeMirror --list`. If nothing is listed, check the cable (some are charge-only), unlock the phone and accept the trust prompt. Quit QuickTime, OBS or any other app that may hold the device.

**Black screen.** Some apps block screen capture for DRM video, for example Netflix or Apple TV+. The phone itself is fine.

**Camera prompt never appeared.** Reset it with `tccutil reset Camera to.vibelabs.vibemirror` and relaunch.

## Limits

- USB only. Wi-Fi capture would mean writing an AirPlay receiver, see [UxPlay](https://github.com/FDH2/UxPlay) for how big that gets.
- Side buttons are drawn in portrait only. The video stream says when the phone rotates, but not which way.
- The device frame is drawn from the screen resolution, not from Apple's device artwork. It fits current iPhones, SE-style home button phones and iPads.

## License

MIT
