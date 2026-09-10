import AppKit

/// Critically damped spring for window frames. Re-targetable mid-flight:
/// a new animate() call continues from the current position and velocity.
final class WindowSpring {
    var omega = 14.0          // ~0.36s response
    var dampingRatio = 1.0
    var apply: (NSRect) -> Void
    private var timer: Timer?
    private var pos = CGPoint.zero
    private var vel = CGPoint.zero
    private var target = CGPoint.zero
    private var size = CGSize.zero
    private var last = Date()
    private var completion: (() -> Void)?
    private(set) var isRunning = false

    init(apply: @escaping (NSRect) -> Void) { self.apply = apply }

    func animate(to frame: NSRect, from current: NSRect, completion: (() -> Void)? = nil) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.completion = completion
            snap(to: frame)
            return
        }
        if !isRunning {
            pos = current.origin
            vel = .zero
        }
        target = frame.origin
        size = frame.size
        self.completion = completion
        last = Date()
        guard timer == nil else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    func snap(to frame: NSRect) {
        let done = completion
        stop()
        apply(frame)
        done?()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        completion = nil
    }

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(last), 1.0 / 20.0)
        last = now
        let k = omega * omega
        let c = 2 * dampingRatio * omega
        var px = pos.x, vx = vel.x, py = pos.y, vy = vel.y
        vx += (-k * (px - target.x) - c * vx) * dt
        px += vx * dt
        vy += (-k * (py - target.y) - c * vy) * dt
        py += vy * dt
        pos = CGPoint(x: px, y: py)
        vel = CGPoint(x: vx, y: vy)
        if abs(px - target.x) < 0.4 && abs(vx) < 6 && abs(py - target.y) < 0.4 && abs(vy) < 6 {
            snap(to: NSRect(origin: target, size: size))
            return
        }
        apply(NSRect(origin: pos, size: size))
    }
}
