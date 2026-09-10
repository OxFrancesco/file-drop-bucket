import AppKit

/// Menu bar presence: dock side, hold delay, auto-show toggle, clear, quit.
final class StatusItemController: NSObject, NSMenuDelegate {
    var onShow: () -> Void = {}
    var onAdd: () -> Void = {}
    var onDock: (DockSide) -> Void = { _ in }
    var onAutoShow: (Bool) -> Void = { _ in }
    var onOnlyFiles: (Bool) -> Void = { _ in }
    var onDelay: (Double) -> Void = { _ in }
    var onClear: () -> Void = {}
    var onQuit: () -> Void = {}
    var settingsProvider: () -> BucketSettings = { BucketSettings() }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let delays: [Double] = [0.4, 0.8, 1.2, 1.6, 2.5]

    override init() {
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "File Bucket")
            button.imagePosition = .imageOnly
        }
        menu.delegate = self
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        let s = settingsProvider()
        menu.removeAllItems()
        menu.addItem(make("Show File Bucket", #selector(showTapped), key: ""))
        menu.addItem(make("Add Files…", #selector(addTapped)))
        menu.addItem(.separator())
        menu.addItem(section("Position"))
        menu.addItem(make("Dock at Left Edge", #selector(dockLeft), checked: s.dock == .left))
        menu.addItem(make("Dock at Right Edge", #selector(dockRight), checked: s.dock == .right))
        menu.addItem(make("Float Freely", #selector(dockFloat), checked: s.dock == .float))
        menu.addItem(.separator())
        menu.addItem(make("Appear While Dragging", #selector(toggleAutoShow), checked: s.autoShow))
        let delayMenu = NSMenu()
        for d in delays {
            let item = NSMenuItem(title: String(format: "Hold %.1f s", d), action: #selector(delayPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = d
            item.state = s.holdDelay == d ? .on : .off
            delayMenu.addItem(item)
        }
        let delayItem = NSMenuItem(title: "Hold Delay", action: nil, keyEquivalent: "")
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)
        menu.addItem(make("Only for File Drags", #selector(toggleOnlyFiles), checked: s.onlyFiles))
        menu.addItem(.separator())
        menu.addItem(make("Clear Bucket", #selector(clearTapped)))
        menu.addItem(.separator())
        menu.addItem(make("Quit File Bucket", #selector(quitTapped), key: "q"))
    }

    private func make(_ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.state = checked ? .on : .off
        return i
    }

    private func section(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        i.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return i
    }

    @objc private func showTapped() { onShow() }
    @objc private func addTapped() { onAdd() }
    @objc private func dockLeft() { onDock(.left) }
    @objc private func dockRight() { onDock(.right) }
    @objc private func dockFloat() { onDock(.float) }
    @objc private func toggleAutoShow() { onAutoShow(!settingsProvider().autoShow) }
    @objc private func toggleOnlyFiles() { onOnlyFiles(!settingsProvider().onlyFiles) }
    @objc private func delayPicked(_ sender: NSMenuItem) {
        if let d = sender.representedObject as? Double { onDelay(d) }
    }
    @objc private func clearTapped() { onClear() }
    @objc private func quitTapped() { onQuit() }
}
