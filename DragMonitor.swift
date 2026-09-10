import AppKit

/// Detects a held mouse drag anywhere on the system without special permissions.
/// Polls the physical button state and cursor position; after the button has been
/// held while moving for `holdDelay` seconds, fires `onDragHold`.
final class DragMonitor {
    var enabled = true
    var holdDelay = 0.8
    var onlyFiles = true
    var onDragHold: () -> Void = {}
    var onDragFinished: () -> Void = {}
    /// Suppress detection when the press began inside our own UI (dragging rows out).
    var pressInsidePanel: (NSPoint) -> Bool = { _ in false }
    private(set) var dragInFlight = false

    private var timer: Timer?
    private var downSince: Date?
    private var downPoint = NSPoint.zero
    private var moved = false
    private var notified = false
    private var suppressed = false
    private var pbSeed = 0

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let down = NSEvent.pressedMouseButtons & 1 == 1
        let loc = NSEvent.mouseLocation
        if down && downSince == nil {
            downSince = Date()
            downPoint = loc
            moved = false
            notified = false
            suppressed = pressInsidePanel(loc)
            pbSeed = NSPasteboard(name: .drag).changeCount
        }
        guard down else {
            if downSince != nil && dragInFlight { onDragFinished() }
            downSince = nil
            dragInFlight = false
            return
        }
        guard let since = downSince else { return }
        if !moved && hypot(loc.x - downPoint.x, loc.y - downPoint.y) > 12 {
            moved = true
            NSLog("[bucket-monitor] drag in flight from %@ elapsed=%.2f", NSStringFromPoint(downPoint), Date().timeIntervalSince(since))
        }
        guard moved else { return }
        dragInFlight = true
        guard enabled, !notified, !suppressed, Date().timeIntervalSince(since) >= holdDelay else { return }
        notified = true
        let fileDrag = isFileDrag()
        NSLog("[bucket-monitor] hold reached fileDrag=%@ suppressed=%d", fileDrag.map { "\($0)" } ?? "unknown", suppressed ? 1 : 0)
        if onlyFiles && fileDrag == false {
            suppressed = true
            return
        }
        onDragHold()
    }

    /// nil when undeterminable: empty pasteboard, or a stale one (changeCount did not
    /// move since the press, meaning no live session wrote to it). Caller still shows.
    private func isFileDrag() -> Bool? {
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != pbSeed else { return nil }
        guard let types = pb.types, !types.isEmpty else { return nil }
        return types.contains(.fileURL)
    }
}
