# Third-party code

| Component | License | Where |
|---|---|---|
| [UxPlay](https://github.com/FDH2/UxPlay) `lib/` | GPL-3.0 (parts LGPL-2.1, from shairplay) | `Sources/CAirPlay/uxplay/lib`, license in `Sources/CAirPlay/uxplay/LICENSE` |
| playfair (FairPlay handshake, in UxPlay) | GPL-3.0 | `Sources/CAirPlay/uxplay/lib/playfair/LICENSE.md` |
| llhttp (in UxPlay) | MIT | `Sources/CAirPlay/uxplay/lib/llhttp/LICENSE-MIT` |
| [OpenSSL](https://www.openssl.org) libcrypto 3.6.4 | Apache-2.0 | built by `scripts/build-deps.sh`, linked statically |
| [libplist](https://github.com/libimobiledevice/libplist) 2.7.0 | LGPL-2.1 | built by `scripts/build-deps.sh`, linked statically |

The vendored UxPlay commit is recorded in `Sources/CAirPlay/uxplay/UPSTREAM.md`. libplist is linked statically; the complete source of VibeMirror and the build script are in this repository, so you can relink against a modified libplist.
