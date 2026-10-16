import AppKit
import AVFoundation

/// Draws the device chrome and hosts the live preview layer inside the screen cutout.
final class DeviceFrameView: NSView {
    var geometry = DeviceGeometry.placeholder {
        didSet { if geometry != oldValue { needsLayout = true } }
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let previewLayer { screenLayer.insertSublayer(previewLayer, at: 0) }
            messageLayer.isHidden = previewLayer != nil
            needsLayout = true
        }
    }

    var message = "" {
        didSet { messageLayer.string = message }
    }

    private let root = CALayer()
    private let rimLayer = CALayer()
    private let bezelLayer = CALayer()
    private let screenLayer = CALayer()
    private let messageLayer = CATextLayer()
    private let homeButtonLayer = CALayer()
    private var buttonLayers: [CALayer] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = root
        wantsLayer = true

        rimLayer.backgroundColor = NSColor(calibratedWhite: 0.30, alpha: 1).cgColor
        bezelLayer.backgroundColor = NSColor.black.cgColor
        screenLayer.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1).cgColor
        screenLayer.masksToBounds = true
        homeButtonLayer.borderColor = NSColor(calibratedWhite: 0.32, alpha: 1).cgColor
        homeButtonLayer.backgroundColor = NSColor.black.cgColor

        messageLayer.alignmentMode = .center
        messageLayer.isWrapped = true
        messageLayer.foregroundColor = NSColor(calibratedWhite: 0.75, alpha: 1).cgColor
        messageLayer.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        for layer in [rimLayer, bezelLayer, screenLayer, homeButtonLayer] {
            layer.cornerCurve = .continuous
        }
        root.addSublayer(rimLayer)
        rimLayer.addSublayer(bezelLayer)
        root.addSublayer(screenLayer)
        root.addSublayer(homeButtonLayer)
        screenLayer.addSublayer(messageLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        messageLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let g = geometry
        let scale = g.fitScale(in: bounds.size)
        let origin = CGPoint(
            x: (bounds.width - g.bounds.width * scale) / 2,
            y: (bounds.height - g.bounds.height * scale) / 2
        )
        // Geometry uses a top-left origin; layers here use bottom-left.
        func convert(_ rect: CGRect) -> CGRect {
            CGRect(
                x: origin.x + rect.minX * scale,
                y: bounds.height - origin.y - rect.maxY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
        }

        syncButtonLayers(count: g.buttons.count)
        for (layer, rect) in zip(buttonLayers, g.buttons) {
            layer.frame = convert(rect)
            layer.cornerRadius = min(layer.frame.width, layer.frame.height) / 2
        }

        rimLayer.frame = convert(g.body)
        rimLayer.cornerRadius = g.bodyCornerRadius * scale
        let rim = g.rimWidth * scale
        bezelLayer.frame = rimLayer.bounds.insetBy(dx: rim, dy: rim)
        bezelLayer.cornerRadius = max(0, rimLayer.cornerRadius - rim)

        screenLayer.frame = convert(g.screen)
        screenLayer.cornerRadius = g.screenCornerRadius * scale
        previewLayer?.frame = screenLayer.bounds

        let short = min(screenLayer.bounds.width, screenLayer.bounds.height)
        let textInset = screenLayer.bounds.width * 0.12
        messageLayer.fontSize = max(11, short * 0.05)
        let textHeight = messageLayer.fontSize * 8
        messageLayer.frame = CGRect(
            x: textInset,
            y: (screenLayer.bounds.height - textHeight) / 2,
            width: screenLayer.bounds.width - 2 * textInset,
            height: textHeight
        )

        if let home = g.homeButton {
            homeButtonLayer.isHidden = false
            homeButtonLayer.frame = convert(home)
            homeButtonLayer.cornerRadius = homeButtonLayer.frame.width / 2
            homeButtonLayer.borderWidth = max(1, homeButtonLayer.frame.width * 0.05)
        } else {
            homeButtonLayer.isHidden = true
        }
    }

    private func syncButtonLayers(count: Int) {
        while buttonLayers.count < count {
            let layer = CALayer()
            layer.backgroundColor = NSColor(calibratedWhite: 0.26, alpha: 1).cgColor
            root.insertSublayer(layer, at: 0)
            buttonLayers.append(layer)
        }
        while buttonLayers.count > count {
            buttonLayers.removeLast().removeFromSuperlayer()
        }
    }
}
