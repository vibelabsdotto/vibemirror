# VibeMirror

Your iPhone screen in a Simulator-style window on your Mac, over Wi-Fi. View only, and it works in the EU.

Apple's iPhone Mirroring is not available in the European Union. VibeMirror does something smaller: it is an AirPlay receiver that shows your iPhone or iPad inside a device frame, plays its audio on the Mac, and takes screenshots. You can't click or type into the phone.

## Use

1. Open VibeMirror on the Mac.
2. On the iPhone, open Control Center, tap Screen Mirroring and pick **VibeMirror**.

iPhone and Mac need to be on the same network. The phone stays usable while it mirrors, and its audio plays on the Mac.

| Shortcut | Action |
|---|---|
| ⌘S | Save a screenshot (PNG) to the Desktop |
| ⌘1 | Fit the window to the screen |
| ⌘2 | Phone-sized window |
| ⌘3 | Pixel accurate |
| ⌥⌘T | Keep on top |
| ⇧⌘M | Mute audio |

Drag anywhere on the device to move the window.

A USB cable works too. Plug the phone in, unlock it, tap Trust, and VibeMirror uses the cable whenever nothing mirrors over AirPlay. That path needs camera permission, because macOS files a USB iPhone under cameras.

| | VibeMirror | Apple iPhone Mirroring |
|---|---|---|
| EU | works | blocked |
| Connection | Wi-Fi (AirPlay) or USB | Wi-Fi |
| Control from Mac | no | yes |
| Phone while mirroring | stays usable | locked |

## How it works

**Wi-Fi.** VibeMirror advertises itself over Bonjour as an AirPlay receiver, the way an Apple TV does. The AirPlay protocol (pairing, FairPlay handshake, stream decryption) comes from [UxPlay](https://github.com/FDH2/UxPlay), vendored in `Sources/CAirPlay/uxplay`. The decrypted H.264 or H.265 stream goes through VideoToolbox into an `AVSampleBufferDisplayLayer`. Audio (AAC-ELD while mirroring) is decoded with `AVAudioConverter` and played through `AVAudioEngine`.

VibeMirror asks for a 3840×2160 display. iOS scales to the requested height and adapts the width to the phone's shape, so a portrait iPhone should arrive at about 1000×2160. If your network struggles, lower it with `defaults write to.vibelabs.vibemirror airplayHeight -int 1080`.

**USB.** macOS has been able to capture an iOS screen over USB since Yosemite; QuickTime uses it for "New Movie Recording". VibeMirror opts in through CoreMediaIO (`kCMIOHardwarePropertyAllowScreenCaptureDevices`) and reads the phone as an `AVCaptureDevice`.

## Install

Download the latest zip from [Releases](https://github.com/vibelabsdotto/vibemirror/releases), unzip, and move `VibeMirror.app` to Applications. Builds are universal, signed with a Developer ID and notarized. Requires macOS 14 or later.

If the macOS firewall asks whether VibeMirror may accept incoming connections, allow it. Otherwise the iPhone can't connect.

## Build

```sh
make deps     # once: static universal libcrypto (OpenSSL) and libplist into .deps/
make run      # debug build, ad-hoc signed, opens the app
make list     # prints USB-connected iOS devices and exits
make release  # universal build, Developer ID signing, notarization
make publish  # uploads the release zip to GitHub
```

Needs Xcode 16 or later. `make release` reads App Store Connect API credentials from the JSON file in `NOTARY_CONFIG` (keys `apple_key_id`, `apple_issuer_id`, `apple_key_path`).

Run through `make run` rather than `swift run`. macOS kills an unbundled binary that asks for the camera without an `Info.plist` usage string.

## Troubleshooting

**VibeMirror doesn't show up on the iPhone.** Both devices must be on the same network, without a VPN or a guest network that isolates clients. Check that the macOS firewall allows VibeMirror. `dns-sd -B _airplay._tcp` on the Mac should list VibeMirror.

**Stutter or blocky video.** Lower `airplayHeight` as above, or move closer to the router.

**Black screen.** Some apps block mirroring for DRM video, for example Netflix.

**USB device missing.** Run `make list`. If nothing is listed, check the cable (some are charge-only), unlock the phone and accept the trust prompt.

## Limits

- Side buttons are drawn in portrait only. The stream says when the phone rotates, but not which way.
- The frame is drawn from the stream's aspect ratio, not from Apple's device artwork. It fits current iPhones, home button iPhones and iPads.
- AirPlay audio and video play as they arrive, without lip-sync correction.

## License

GPL-3.0, because VibeMirror includes UxPlay (GPL-3.0). It also bundles llhttp (MIT) and playfair (GPL-3.0) through UxPlay and links OpenSSL (Apache-2.0) and libplist (LGPL-2.1) statically. Details in [THIRD_PARTY.md](THIRD_PARTY.md).
