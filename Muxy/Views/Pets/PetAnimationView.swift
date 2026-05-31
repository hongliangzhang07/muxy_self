import AppKit
import ImageIO
import SwiftUI

struct PetAnimationView: NSViewRepresentable {
    let package: PetPackage
    let state: PetState
    let reduceMotion: Bool

    func makeNSView(context _: Context) -> PetAnimationNSView {
        let view = PetAnimationNSView()
        view.configure(package: package, state: state, reduceMotion: reduceMotion)
        return view
    }

    func updateNSView(_ nsView: PetAnimationNSView, context _: Context) {
        nsView.configure(package: package, state: state, reduceMotion: reduceMotion)
    }

    static func dismantleNSView(_ nsView: PetAnimationNSView, coordinator _: ()) {
        nsView.stop()
    }
}

final class PetAnimationNSView: NSView {
    private let spriteLayer = CALayer()
    private var fullImage: CGImage?
    private var loadedSpritesheetURL: URL?
    private var currentState: PetState = .idle
    private var frameIndex = 0
    private var timer: Timer?
    private var isReduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        spriteLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(spriteLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        spriteLayer.frame = bounds
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let hide = NSMenuItem(title: "Hide Pet", action: #selector(hidePet), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        return menu
    }

    @objc
    private func hidePet() {
        UserDefaults.standard.set(false, forKey: PetSettings.Key.enabled)
    }

    func configure(package: PetPackage, state: PetState, reduceMotion: Bool) {
        loadSpritesheet(package.spritesheetURL)
        let resolvedState = reduceMotion ? .idle : state
        let needsReset = resolvedState != currentState || reduceMotion != isReduceMotion
        let needsResume = !reduceMotion && timer == nil
        guard needsReset || needsResume else { return }
        currentState = resolvedState
        isReduceMotion = reduceMotion
        if needsReset {
            frameIndex = 0
            renderCurrentFrame()
        }
        if reduceMotion {
            stop()
        } else {
            scheduleNextFrame()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func loadSpritesheet(_ url: URL) {
        guard loadedSpritesheetURL != url else { return }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return }
        fullImage = image
        loadedSpritesheetURL = url
    }

    private func renderCurrentFrame() {
        guard let fullImage else { return }
        let cropped = fullImage.cropping(to: currentState.frameRect(at: frameIndex))
        spriteLayer.contents = cropped
    }

    private func scheduleNextFrame() {
        stop()
        let durations = currentState.durationsMs
        guard frameIndex < durations.count else { return }
        let interval = Double(durations[frameIndex]) / 1000.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.advanceFrame() }
        }
    }

    private func advanceFrame() {
        frameIndex = (frameIndex + 1) % currentState.frameCount
        renderCurrentFrame()
        scheduleNextFrame()
    }
}
