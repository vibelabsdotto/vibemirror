import CoreGraphics

/// Simulator-style device chrome computed from the captured screen size alone.
/// All rects are in screen-pixel units; the view scales the result to fit.
struct DeviceGeometry: Equatable {
    enum Kind { case faceIDPhone, homeButtonPhone, tablet }

    let screenSize: CGSize
    let kind: Kind
    let isPortrait: Bool

    let bounds: CGRect
    let body: CGRect
    let bodyCornerRadius: CGFloat
    let rimWidth: CGFloat
    let screen: CGRect
    let screenCornerRadius: CGFloat
    let buttons: [CGRect]
    let homeButton: CGRect?

    /// Used before any device is connected (iPhone 15/16 class, 1179 x 2556).
    static let placeholder = DeviceGeometry(screenSize: CGSize(width: 1179, height: 2556))

    init(screenSize: CGSize) {
        self.screenSize = screenSize
        let short = min(screenSize.width, screenSize.height)
        let long = max(screenSize.width, screenSize.height)
        let aspect = long / short
        isPortrait = screenSize.height >= screenSize.width

        switch aspect {
        case 2.0...: kind = .faceIDPhone
        case 1.7..<2.0: kind = .homeButtonPhone
        default: kind = .tablet
        }

        // Proportions measured from Apple's device frames, relative to the short screen side.
        let bezel: CGFloat
        var forehead: CGFloat = 0
        switch kind {
        case .faceIDPhone:
            bezel = short * 0.045
            screenCornerRadius = short * 0.145
        case .homeButtonPhone:
            bezel = short * 0.06
            forehead = short * 0.30
            screenCornerRadius = 0
        case .tablet:
            bezel = short * 0.05
            screenCornerRadius = short * 0.025
        }
        rimWidth = short * 0.012

        // Body in portrait-relative terms, then flip for landscape.
        let insetShort = bezel
        let insetLong = bezel + forehead
        let bodySize = isPortrait
            ? CGSize(width: screenSize.width + 2 * insetShort, height: screenSize.height + 2 * insetLong)
            : CGSize(width: screenSize.width + 2 * insetLong, height: screenSize.height + 2 * insetShort)

        let rim = short * 0.012
        let protrusion = kind == .tablet ? 0 : short * 0.012
        let margin = protrusion + short * 0.004
        let body = CGRect(x: margin, y: margin, width: bodySize.width, height: bodySize.height)
        self.body = body
        bounds = CGRect(x: 0, y: 0, width: bodySize.width + 2 * margin, height: bodySize.height + 2 * margin)
        bodyCornerRadius = screenCornerRadius == 0 ? short * 0.16 : screenCornerRadius + bezel

        let screen = CGRect(
            x: body.minX + (isPortrait ? insetShort : insetLong),
            y: body.minY + (isPortrait ? insetLong : insetShort),
            width: screenSize.width,
            height: screenSize.height
        )
        self.screen = screen

        // Side buttons only in portrait: the stream does not tell us which way the phone turned.
        if kind != .tablet, screenSize.height >= screenSize.width {
            let h = body.height
            func left(_ from: CGFloat, _ to: CGFloat) -> CGRect {
                CGRect(x: body.minX - protrusion, y: body.minY + h * from, width: protrusion + rim, height: h * (to - from))
            }
            func right(_ from: CGFloat, _ to: CGFloat) -> CGRect {
                CGRect(x: body.maxX - rim, y: body.minY + h * from, width: protrusion + rim, height: h * (to - from))
            }
            // Top-left origin (the view is flipped): action/mute, volume up, volume down, side button.
            buttons = [left(0.17, 0.21), left(0.25, 0.32), left(0.35, 0.42), right(0.27, 0.40)]
        } else {
            buttons = []
        }

        if kind == .homeButtonPhone {
            let d = short * 0.14
            let center = screenSize.height >= screenSize.width
                ? CGPoint(x: body.midX, y: screen.maxY + forehead / 2 + bezel / 2)
                : CGPoint(x: screen.maxX + forehead / 2 + bezel / 2, y: body.midY)
            homeButton = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        } else {
            homeButton = nil
        }
    }

    /// Scale that maps device pixels to view points for a given container size.
    func fitScale(in size: CGSize) -> CGFloat {
        min(size.width / bounds.width, size.height / bounds.height)
    }
}
