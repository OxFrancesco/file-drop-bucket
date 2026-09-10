import AppKit

/// Positions the bucket: floating freely, or docked to a screen edge where nothing
/// stays visible — the panel is fully ordered out, and hovering the edge band
/// slides it back in.
final class DockController {
    private let panel: BucketPanel
    var isDragInFlight: () -> Bool = { false }

    private(set) var side: DockSide = .float
    private(set) var revealed = false
    var pinned = false
    var dragHovering = false
    private var autoRevealed = false

    private let spring: WindowSpring
    private var poll: Timer?
    private var floatingFrame = NSRect(origin: .zero, size: BucketView.size)
    /// The display the bucket is docked on; a parked off-screen frame can land on
    /// an adjacent display, so the edge is tracked explicitly, not inferred.
    private var dockedScreen: NSScreen?
    private var lastInside = Date.distantPast
    private var lastReveal = Date.distantPast

    init(panel: BucketPanel) {
        self.panel = panel
        spring = WindowSpring { [weak panel] frame in panel?.setFrame(frame, display: true) }
        if let main = NSScreen.main {
            let f = main.visibleFrame
            floatingFrame = NSRect(x: f.midX - BucketView.size.width / 2, y: f.midY - BucketView.size.height / 2,
                                   width: BucketView.size.width, height: BucketView.size.height)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, self.side == .float, self.revealed, !self.spring.isRunning else { return }
            self.floatingFrame = self.panel.frame
        }
        poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func edgeScreen() -> NSScreen {
        if let dockedScreen { return dockedScreen }
        return NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func revealedFrame() -> NSRect {
        let vis = edgeScreen().visibleFrame
        let s = panel.frame.size
        let y = vis.midY - s.height / 2
        switch side {
        case .left: return NSRect(x: vis.minX + 6, y: y, width: s.width, height: s.height)
        case .right: return NSRect(x: vis.maxX - 6 - s.width, y: y, width: s.width, height: s.height)
        case .float: return floatingFrame
        }
    }

    /// Fully past the edge; may overlap a neighbouring display, but the panel is
    /// ordered out while parked so nothing is ever visible there.
    private func parkedFrame() -> NSRect {
        let vis = edgeScreen().visibleFrame
        let s = panel.frame.size
        let y = vis.midY - s.height / 2
        switch side {
        case .left: return NSRect(x: vis.minX - s.width, y: y, width: s.width, height: s.height)
        case .right: return NSRect(x: vis.maxX, y: y, width: s.width, height: s.height)
        case .float: return panel.frame
        }
    }

    /// Hover band at the very screen edge, a bit taller than the panel.
    private func hoverZone() -> NSRect {
        guard side != .float else { return .null }
        let vis = edgeScreen().visibleFrame
        let h = panel.frame.height + 80
        let y = vis.midY - h / 2
        switch side {
        case .left: return NSRect(x: vis.minX - 4, y: y, width: 34, height: h)
        case .right: return NSRect(x: vis.maxX - 30, y: y, width: 34, height: h)
        case .float: return .null
        }
    }

    func setSide(_ new: DockSide) {
        guard new != side else { return }
        if side == .float && revealed { floatingFrame = panel.frame }
        if new != .float {
            dockedScreen = panel.isVisible
                ? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
                : NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        }
        side = new
        panel.isMovable = new == .float
        if new == .float {
            if revealed {
                spring.animate(to: floatingFrame, from: panel.frame)
            } else {
                spring.stop()
                panel.alphaValue = 0
                panel.setFrame(floatingFrame, display: false)
                if !panel.isVisible { panel.orderFrontRegardless() }
                fade(to: 1) {}
            }
            revealed = true
            return
        }
        if revealed {
            spring.animate(to: revealedFrame(), from: panel.frame)
        } else {
            slideOff()
        }
    }

    func reveal(pinned pin: Bool = false, auto: Bool = false) {
        if pin { pinned = true }
        if auto { autoRevealed = true }
        NSLog("[bucket-dock] reveal side=%@ pin=%d auto=%d visible=%d", side.rawValue, pin ? 1 : 0, auto ? 1 : 0, panel.isVisible ? 1 : 0)
        lastReveal = Date()
        lastInside = Date()
        if side == .float {
            guard !panel.isVisible else { revealed = true; return }
            panel.setFrame(floatingFrame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.invalidateShadow()
            fade(to: 1) {}
        } else {
            if !panel.isVisible {
                panel.alphaValue = 1
                panel.setFrame(parkedFrame(), display: false)
                panel.orderFrontRegardless()
            }
            spring.animate(to: revealedFrame(), from: panel.frame)
        }
        revealed = true
    }

    func conceal() {
        revealed = false
        autoRevealed = false
        NSLog("[bucket-dock] conceal side=%@", side.rawValue)
        if side == .float {
            guard panel.isVisible else { return }
            fade(to: 0) { [weak self] in
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
            }
        } else {
            slideOff()
        }
    }

    /// Slide fully past the edge, then order the window out.
    private func slideOff() {
        let target = parkedFrame()
        guard panel.isVisible else {
            panel.setFrame(target, display: false)
            return
        }
        spring.animate(to: target, from: panel.frame) { [weak self] in
            guard let self, self.side != .float, !self.revealed else { return }
            self.panel.orderOut(nil)
        }
    }

    /// User explicitly closed the bucket: drop the pin and hide it.
    func userClose() {
        pinned = false
        autoRevealed = false
        conceal()
    }

    /// Called when the hold timer fires mid-drag.
    func dragHoldTriggered() {
        reveal(auto: true)
    }

    /// A drag entered the panel while a session is live.
    func noteDragEnter() {
        if !revealed { reveal(auto: true) }
    }

    /// The mouse button went up after a moving drag.
    func dragEnded() {
        guard autoRevealed, !pinned, !dragHovering else { return }
        let near = panel.frame.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation)
            || hoverZone().contains(NSEvent.mouseLocation)
        if !near { conceal() }
        autoRevealed = false
    }

    private func tick() {
        guard side != .float else { return }
        let mouse = NSEvent.mouseLocation
        if !revealed {
            if hoverZone().contains(mouse) { reveal() }
            return
        }
        guard panel.isVisible else { revealed = false; return }
        let inside = panel.frame.insetBy(dx: -10, dy: -10).contains(mouse) || hoverZone().contains(mouse)
        if inside { lastInside = Date() }
        let settled = Date().timeIntervalSince(lastInside) > 0.55
            && Date().timeIntervalSince(lastReveal) > 0.55
        if settled && !pinned && !dragHovering && !isDragInFlight() { conceal() }
    }

    private func fade(to value: CGFloat, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.01 : 0.18
            panel.animator().alphaValue = value
        }, completionHandler: completion)
    }
}
