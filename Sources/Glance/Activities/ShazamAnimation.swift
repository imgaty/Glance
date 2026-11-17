//
//  ShazamAnimation.swift
//  Glance
//
//  Created by Gaty on 17/11/2026.
//

import AppKit
import QuartzCore
import SwiftUI

/// iOS 27's own Music Recognition animations. They aren't drawn in code: `MusicRecognition.app` plays
/// Core Animation files from its `MicaAssets`, and macOS ships the very same files in ShazamKitUI, so
/// Glance plays them as they are, layer for layer, rather than drawing a likeness.
enum ShazamAnimation: String {
    /// Shazam's mark alone, beside the camera: blue, breathing, light tracing its strokes.
    case compact = "compact-listening"
    /// Opened: the white mark breathing on Shazam's blue disc, the arc glow turning round it once
    /// every 5 seconds, sparkles, and a blue halo.
    case expanded = "expanded-listening"

    private static let folder = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/ShazamKitUI.framework/Resources/MicaAssets", isDirectory: true)

    private var file: URL { Self.folder.appendingPathComponent(rawValue + ".ca", isDirectory: true) }

    /// Whether this Mac has the file.
    var available: Bool { FileManager.default.fileExists(atPath: file.path) }

    /// A fresh copy of the file's layers, or nil where this Mac can't read it.
    func layers() -> CALayer? {
        guard available,
            let package: AnyClass = NSClassFromString("CAPackage"),
            let method = class_getClassMethod(package, NSSelectorFromString("packageWithContentsOfURL:type:options:error:"))
        else { return nil }
        typealias Load = @convention(c) (AnyClass, Selector, NSURL, NSString, NSDictionary?, UnsafeMutablePointer<NSError?>?) -> NSObject?
        let load = unsafeBitCast(method_getImplementation(method), to: Load.self)
        var error: NSError?
        guard let read = load(package, method_getName(method), file as NSURL, "com.apple.coreanimation-bundle", nil, &error),
            let root = read.value(forKey: "rootLayer") as? CALayer
        else { return nil }
        return root
    }

    /// The part the view's height is fitted to, in the root layer's space: the disc, or the mark as
    /// it is halfway through breathing (1.02 to 1.06 its size).
    func fit(in root: CALayer) -> CGRect? {
        let layers = Self.all(root)
        switch self {
        case .expanded:
            guard let disc = layers.first(where: { $0.name == "Layer 6" }) else { return nil }
            return root.convert(disc.bounds, from: disc)
        case .compact:
            guard let mark = layers.first(where: { ($0 as? CAShapeLayer)?.fillColor?.alpha ?? 0 > 0 }) as? CAShapeLayer,
                let path = mark.path
            else { return nil }
            let shape = root.convert(path.boundingBoxOfPath, from: mark)
            return shape.insetBy(dx: -shape.width * 0.02, dy: -shape.height * 0.02)
        }
    }

    /// How much room it's shown in round that part, as a share of it: the expanded file's whole
    /// square, for its halo and sparkles; a little round the mark for its light.
    var reach: CGFloat { self == .expanded ? 84 / 59.416 : 1.3 }

    static func all(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(all) }
}

/// One of Apple's Music Recognition files playing, its disc or mark centred in the view and `reach`
/// times smaller than it, the rest of the view room for its halo, sparkles and light. Still, it shows
/// the file's first moment: the mark, the disc, no sparkles.
struct ShazamAnimationView: NSViewRepresentable {
    let animation: ShazamAnimation
    let playing: Bool

    func makeNSView(context: Context) -> ShazamAnimationPlayer { ShazamAnimationPlayer(animation) }

    func updateNSView(_ view: ShazamAnimationPlayer, context: Context) { view.playing = playing }
}

final class ShazamAnimationPlayer: NSView {
    private let root: CALayer?
    private let fit: CGRect
    private let reach: CGFloat
    /// The island's black that the file is made to be seen on, under its own black sheets, then
    /// added onto the notch: adding black changes nothing, so only the file's light shows on the
    /// open notch's glass.
    private let stage = CALayer()
    /// What's behind, copied under the stage: on the Mac a layer only adds onto what its own parent
    /// has drawn before it, not onto what's behind the view.
    private let behind = (NSClassFromString("CABackdropLayer") as? CALayer.Type)?.init()

    var playing = false {
        didSet { if playing != oldValue { time() } }
    }

    init(_ animation: ShazamAnimation) {
        let root = animation.layers()
        self.root = root
        fit = root.flatMap { animation.fit(in: $0) } ?? .zero
        reach = animation.reach
        super.init(frame: .zero)
        wantsLayer = true
        stage.backgroundColor = CGColor(gray: 0, alpha: 1)
        stage.compositingFilter = "plusL"
        stage.masksToBounds = true
        if let behind { layer?.addSublayer(behind) }
        layer?.addSublayer(stage)
        if let root {
            // The four blurred copies of what's under the sparkles, which make them glow: on the
            // island they copy its black, but on the Mac they copy the screen beside the stage and
            // show as a streak at its edge.
            for copy in ShazamAnimation.all(root) where NSStringFromClass(type(of: copy)) == "CABackdropLayer" {
                copy.isHidden = true
            }
            stage.addSublayer(root)
            time()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        place()
    }

    override func layout() {
        super.layout()
        place()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let root, let scale = window?.backingScaleFactor else { return }
        // Sharp at the screen's scale, then drawn smaller.
        for layer in ShazamAnimation.all(root) { layer.contentsScale = scale }
    }

    private func place() {
        guard let root, fit.height > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = bounds
        behind?.frame = bounds
        let scale = bounds.height / reach / fit.height
        root.anchorPoint = CGPoint(x: fit.midX / root.bounds.width, y: fit.midY / root.bounds.height)
        root.position = CGPoint(x: bounds.midX, y: bounds.midY)
        root.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }

    /// Playing starts the file from its beginning, as the island does when it shows it; still, it
    /// holds there.
    private func time() {
        guard let root else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.timeOffset = 0
        if playing {
            root.beginTime = layer.map { $0.convertTime(CACurrentMediaTime(), from: nil) } ?? CACurrentMediaTime()
            root.speed = 1
        } else {
            root.speed = 0
            root.beginTime = 0
        }
        CATransaction.commit()
    }
}
