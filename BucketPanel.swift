import AppKit
import QuartzCore

final class BucketPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init() {
        self.init(
            contentRect: NSRect(origin: .zero, size: BucketView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
    }
}

/// Header area that drags the floating window (when isMovable is on).
private final class DragRegion: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Translucent empty state sitting over the (empty) table.
private final class EmptyStateView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 26, weight: .light))
        icon.contentTintColor = .tertiaryLabelColor
        let title = NSTextField(labelWithString: "Drop files to keep them")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .secondaryLabelColor
        let sub = NSTextField(labelWithString: "Originals stay in place")
        sub.font = .systemFont(ofSize: 10)
        sub.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [icon, title, sub])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Accent ring shown while a drag hovers the panel.
private final class DropOverlay: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 3
        layer?.cornerRadius = 10
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .controlAccentColor
        label.alignment = .center
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: bounds.midY - 10, width: bounds.width, height: 20)
    }

    func show(count: Int) {
        label.stringValue = count > 0 ? "Release to keep \(count) file\(count == 1 ? "" : "s")" : "Release to keep"
        isHidden = false
    }
}

/// The panel content: vibrancy surface, header, file table, drop overlay.
/// The whole view is the drop destination so files can land anywhere on the bucket.
final class BucketView: NSVisualEffectView {
    static let size = NSSize(width: 300, height: 430)

    var onDropURLs: ([URL]) -> Void = { _ in }
    var onDragHover: (Bool) -> Void = { _ in }
    var onPin: () -> Void = {}
    var onClose: () -> Void = {}

    let table = NSTableView()
    private let scroll = NSScrollView()
    private let overlay = DropOverlay()
    private let emptyState = EmptyStateView()
    private let status = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")
    private let pinButton = NSButton()
    private let closeButton = NSButton()
    private var pinned = false
    private var hovering = false

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        registerForDraggedTypes([.fileURL])

        let w = Self.size.width
        let h = Self.size.height

        addSubview(DragRegion(frame: NSRect(x: 0, y: h - 46, width: w, height: 46)))

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        icon.contentTintColor = .secondaryLabelColor
        icon.frame = NSRect(x: 14, y: h - 31, width: 16, height: 16)

        let title = NSTextField(labelWithString: "File Bucket")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 38, y: h - 33, width: 120, height: 20)

        countField.font = .systemFont(ofSize: 10)
        countField.textColor = .secondaryLabelColor
        countField.alignment = .right
        countField.frame = NSRect(x: w - 138, y: h - 32, width: 76, height: 18)

        configure(button: pinButton, symbol: "pin", frame: NSRect(x: w - 58, y: h - 35, width: 24, height: 24), action: #selector(pinClicked))
        configure(button: closeButton, symbol: "xmark", frame: NSRect(x: w - 32, y: h - 35, width: 24, height: 24), action: #selector(closeClicked))

        let hairline = NSBox(frame: NSRect(x: 10, y: h - 46, width: w - 20, height: 1))
        hairline.boxType = .separator

        scroll.frame = NSRect(x: 8, y: 28, width: w - 16, height: h - 82)
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.title = "Files"
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 46
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.style = .fullWidth
        table.allowsMultipleSelection = true
        table.backgroundColor = .clear
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setAccessibilityLabel("Bucket files. Drag rows to another app")
        scroll.documentView = table

        emptyState.frame = scroll.frame

        status.font = .systemFont(ofSize: 9)
        status.textColor = .tertiaryLabelColor
        status.alignment = .center
        status.stringValue = "Drop files in · drag rows out"
        status.frame = NSRect(x: 0, y: 7, width: w, height: 14)

        overlay.frame = bounds.insetBy(dx: 6, dy: 6)

        for v in [icon, title, countField, pinButton, closeButton, hairline, scroll, emptyState, status, overlay] {
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure(button: NSButton, symbol: String, frame: NSRect, action: Selector) {
        button.frame = frame
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
    }

    @objc private func pinClicked() { onPin() }
    @objc private func closeClicked() { onClose() }

    func setPinned(_ value: Bool) {
        pinned = value
        pinButton.image = NSImage(systemSymbolName: value ? "pin.fill" : "pin", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        pinButton.contentTintColor = value ? .controlAccentColor : .secondaryLabelColor
    }

    func update(count: Int, statusText: String) {
        emptyState.isHidden = count != 0
        countField.stringValue = count == 0 ? "" : "\(count) file\(count == 1 ? "" : "s")"
        status.stringValue = statusText
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hovering = true
        onDragHover(true)
        overlay.show(count: sender.draggingPasteboard.pasteboardItems?.count ?? 0)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hovering = false
        onDragHover(false)
        overlay.isHidden = true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        hovering = false
        onDragHover(false)
        overlay.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        onDropURLs(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        overlay.isHidden = true
    }
}
