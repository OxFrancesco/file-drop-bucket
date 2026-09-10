import AppKit

let store = BucketStore()
let settingsStore = SettingsStore(directory: store.directory)
let args = Array(CommandLine.arguments.dropFirst())

func cliError(_ message: String) -> NSError {
    NSError(domain: "Bucket", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
}

if let command = args.first, command != "--app", command != "--drop-test" {
    do {
        switch command {
        case "add":
            guard args.count > 1 else { throw cliError("Usage: bucket add <paths...>") }
            try store.add(Array(args.dropFirst()))
        case "clear":
            _ = try store.access { $0.removeAll() }
        case "list":
            for path in try store.access() { print(path) }
        case "show":
            let bundle = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [bundle.path]
            try task.run(); task.waitUntilExit(); exit(task.terminationStatus)
        case "dock":
            guard let value = args.dropFirst().first else { throw cliError("Usage: bucket dock <left|right|off>") }
            let side: DockSide
            switch value {
            case "left": side = .left
            case "right": side = .right
            case "off", "float", "none": side = .float
            default: throw cliError("Usage: bucket dock <left|right|off>")
            }
            settingsStore.update { $0.dock = side }
        case "delay":
            guard let value = args.dropFirst().first, let delay = Double(value), (0.1...10).contains(delay) else {
                throw cliError("Usage: bucket delay <seconds 0.1-10>")
            }
            settingsStore.update { $0.holdDelay = delay }
        case "autoshow", "onlyfiles", "keepopen":
            guard let value = args.dropFirst().first, ["on", "off"].contains(value) else {
                throw cliError("Usage: bucket \(command) <on|off>")
            }
            let on = value == "on"
            switch command {
            case "autoshow": settingsStore.update { $0.autoShow = on }
            case "onlyfiles": settingsStore.update { $0.onlyFiles = on }
            default: settingsStore.update { $0.keepOpen = on }
            }
        case "config":
            let s = settingsStore.load()
            print("dock=\(s.dock.rawValue) holdDelay=\(s.holdDelay) autoShow=\(s.autoShow) onlyFiles=\(s.onlyFiles) keepOpen=\(s.keepOpen)")
            if s.dock != .float { print("panel is \(s.keepOpen ? "pinned open" : "hidden behind the \(s.dock.rawValue) edge strip")") }
        default:
            throw cliError("Usage: bucket add <paths...> | clear | list | show | dock <left|right|off> | delay <s> | autoshow <on|off> | onlyfiles <on|off> | keepopen <on|off> | config")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("bucket: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

final class DropProbe: NSView {
    let label = NSTextField(wrappingLabelWithString: "Drop a bucket file here\nLocal test only. Nothing is uploaded.")
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        label.frame = bounds.insetBy(dx: 24, dy: 30); label.autoresizingMask = [.width, .height]
        label.font = .systemFont(ofSize: 17); addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        do {
            // Read the received URLs, not the manifest. A URL-only check cannot prove file access.
            let files = try urls.map { url -> [String: Any] in
                let data = try Data(contentsOf: url)
                return ["name": url.lastPathComponent, "size": data.count, "base64": data.base64EncodedString()]
            }
            let report = try JSONSerialization.data(withJSONObject: files, options: [.prettyPrinted, .sortedKeys])
            try report.write(to: store.directory.appendingPathComponent("drop-test.json"), options: .atomic)
            label.stringValue = "Received and read native files:\n" + urls.map(\.lastPathComponent).joined(separator: "\n")
            return true
        } catch {
            label.stringValue = "Drop failed: \(error.localizedDescription)"
            return false
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var probeWindow: NSWindow?
    var panel: BucketPanel?
    var bucketView: BucketView?
    var dock: DockController?
    var monitor: DragMonitor?
    var statusBar: StatusItemController?
    var settings = BucketSettings()
    var paths = [String]()
    var refreshTimer: Timer?

    private lazy var rowMenu: NSMenu = {
        let menu = NSMenu()
        for (title, action) in [
            ("Open", #selector(menuOpen)),
            ("Reveal in Finder", #selector(menuReveal)),
            ("Remove from Bucket", #selector(menuRemove)),
        ] as [(String, Selector)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["BUCKET_DROP_TEST"] == "1" {
            // Opt-in delivery diagnostics. No paths or file contents are logged.
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
                NSLog("[bucket-drag-test] event=%ld window=%ld hasWindow=%d", event.type.rawValue, event.windowNumber, event.window != nil ? 1 : 0)
                return event
            }
        }
        let menu = NSMenu(); let root = NSMenuItem(); menu.addItem(root)
        let submenu = NSMenu(); submenu.addItem(withTitle: "Quit File Bucket", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = submenu; NSApp.mainMenu = menu
        if args.contains("--drop-test") {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 450, height: 220), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Bucket local drop test"; window.contentView = DropProbe(frame: NSRect(x: 0, y: 0, width: 450, height: 220))
            window.isReleasedWhenClosed = false; window.makeKeyAndOrderFront(nil)
            probeWindow = window
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        buildProduct()
    }

    private func buildProduct() {
        let panel = BucketPanel()
        let view = BucketView()
        panel.contentView = view
        self.panel = panel
        self.bucketView = view

        let table = view.table
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(menuOpen)
        table.menu = rowMenu

        let dock = DockController(panel: panel)
        self.dock = dock

        let monitor = DragMonitor()
        monitor.pressInsidePanel = { [weak panel] point in
            guard let panel, panel.isVisible else { return false }
            return panel.frame.contains(point)
        }
        monitor.onDragHold = { [weak dock] in dock?.dragHoldTriggered() }
        monitor.onDragFinished = { [weak dock] in dock?.dragEnded() }
        dock.isDragInFlight = { [weak monitor] in monitor?.dragInFlight ?? false }
        monitor.start()
        self.monitor = monitor

        view.onDropURLs = { [weak self] urls in
            // Mutating the table inside performDragOperation can trap in
            // endUpdates — defer the add to the next runloop turn.
            DispatchQueue.main.async {
                self?.perform { try store.add(urls.map(\.path)) }
            }
        }
        view.onDragHover = { [weak self] hovering in
            self?.dock?.dragHovering = hovering
            if hovering { self?.dock?.noteDragEnter() }
        }
        view.onPin = { [weak self] in self?.mutateSettings { $0.keepOpen.toggle() } }
        view.table.onRemoveSelection = { [weak self] in self?.menuRemove() }

        let statusBar = StatusItemController()
        statusBar.settingsProvider = { [weak self] in self?.settings ?? BucketSettings() }
        statusBar.onShow = { [weak self] in self?.showBucket() }
        statusBar.onAdd = { [weak self] in self?.addFiles() }
        statusBar.onDock = { [weak self] side in self?.mutateSettings { $0.dock = side } }
        statusBar.onAutoShow = { [weak self] value in self?.mutateSettings { $0.autoShow = value } }
        statusBar.onOnlyFiles = { [weak self] value in self?.mutateSettings { $0.onlyFiles = value } }
        statusBar.onDelay = { [weak self] delay in self?.mutateSettings { $0.holdDelay = delay } }
        statusBar.onClear = { [weak self] in self?.perform { _ = try store.access { $0.removeAll() } } }
        statusBar.onQuit = { NSApp.terminate(nil) }
        self.statusBar = statusBar

        settings = settingsStore.load()
        applySettings()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
            self?.pollSettings()
        }
        // On launch, show the bucket pinned once so the running app is discoverable.
        mutateSettings { $0.keepOpen = true }
        dock.reveal(pinned: true)
    }

    private func showBucket() {
        mutateSettings { $0.keepOpen = true }
        dock?.reveal(pinned: true)
    }

    private func mutateSettings(_ mutation: (inout BucketSettings) -> Void) {
        settings = settingsStore.update(mutation)
        applySettings()
    }

    private func pollSettings() {
        let next = settingsStore.load()
        if next != settings {
            settings = next
            applySettings()
        }
    }

    private func applySettings() {
        monitor?.enabled = settings.autoShow
        monitor?.holdDelay = settings.holdDelay
        monitor?.onlyFiles = settings.onlyFiles
        dock?.pinned = settings.keepOpen
        bucketView?.setPinned(settings.keepOpen)
        dock?.setSide(settings.dock)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if dock != nil { showBucket() }
        return true
    }

    func refresh() {
        guard let view = bucketView else { return }
        // Never touch rows mid-drag-session; the end callback reapplies.
        guard outPaths.isEmpty else { refreshPending = true; return }
        do {
            let next = try store.access()
            if next != paths { applyRows(next, to: view.table) }
            view.update(
                count: paths.count,
                statusText: paths.isEmpty ? "Drop files in · drag rows out" : "Copy-only drags · originals stay put"
            )
        } catch {
            view.update(count: paths.count, statusText: error.localizedDescription)
        }
    }

    /// Diff the row model so drops slide in and drag-outs slide away.
    private func applyRows(_ next: [String], to table: NSTableView) {
        let old = paths
        let removed = IndexSet(old.indices.filter { !next.contains(old[$0]) })
        let survivors = Set(old.filter(next.contains))
        let inserted = IndexSet(next.indices.filter { !survivors.contains(next[$0]) })
        paths = next
        guard !removed.isEmpty || !inserted.isEmpty else {
            table.reloadData()
            return
        }
        table.beginUpdates()
        table.removeRows(at: removed, withAnimation: [.effectFade, .slideDown])
        table.insertRows(at: inserted, withAnimation: [.effectFade, .slideUp])
        table.endUpdates()
    }

    func perform(_ work: () throws -> Void) {
        do { try work(); refresh() } catch { NSAlert(error: error).runModal() }
    }

    @objc func addFiles() {
        let picker = NSOpenPanel()
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        if picker.runModal() == .OK { perform { try store.add(picker.urls.map(\.path)) } }
    }

    @objc func menuOpen() {
        guard let table = bucketView?.table else { return }
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard paths.indices.contains(row), FileManager.default.fileExists(atPath: paths[row]) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: paths[row]))
    }

    @objc func menuReveal() {
        guard let table = bucketView?.table else { return }
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard paths.indices.contains(row) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: paths[row])])
    }

    @objc func menuRemove() {
        guard let table = bucketView?.table else { return }
        var targets = Set(table.selectedRowIndexes)
        if table.clickedRow >= 0 { targets = [table.clickedRow] }
        let selected = Set(targets.compactMap { paths.indices.contains($0) ? paths[$0] : nil })
        perform { _ = try store.access { $0.removeAll { selected.contains($0) } } }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { paths.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard paths.indices.contains(row) else { return nil }
        let path = paths[row]; let url = URL(fileURLWithPath: path)
        let cell = NSTableCellView()
        let icon = NSImageView(); icon.image = NSWorkspace.shared.icon(forFile: path)
        let text = NSTextField(labelWithString: url.lastPathComponent); text.font = .systemFont(ofSize: 13, weight: .medium); text.lineBreakMode = .byTruncatingMiddle
        let detail = NSTextField(labelWithString: FileManager.default.fileExists(atPath: path) ? url.deletingLastPathComponent().path : "Missing source file")
        detail.font = .systemFont(ofSize: 10); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingMiddle
        for view in [icon, text, detail] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
        cell.textField = text; cell.imageView = icon; cell.toolTip = path
        cell.setAccessibilityElement(true); cell.setAccessibilityRole(.group); cell.setAccessibilityLabel("Drag file \(url.lastPathComponent)"); cell.setAccessibilityHelp(path)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 30), icon.heightAnchor.constraint(equalToConstant: 30),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), text.topAnchor.constraint(equalTo: cell.topAnchor, constant: 9), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            detail.leadingAnchor.constraint(equalTo: text.leadingAnchor), detail.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 2), detail.trailingAnchor.constraint(equalTo: text.trailingAnchor)
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        if ProcessInfo.processInfo.environment["BUCKET_DROP_TEST"] == "1" {
            NSLog("[bucket-drag-test] pasteboardWriter row=%ld", row)
        }
        guard paths.indices.contains(row), let path = try? store.canonical(paths[row]) else { return nil }
        return NSURL(fileURLWithPath: path)
    }

    /// Paths captured at drag start so a mid-drag list change can't shift indices.
    private var outPaths: Set<String> = []
    /// Set when a refresh arrives while a row drag session is live.
    private var refreshPending = false

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        outPaths = Set(rowIndexes.compactMap { paths.indices.contains($0) ? paths[$0] : nil })
    }

    /// A completed drop outside the panel takes the files off the shelf.
    /// Cancelled drags, and drops back onto the bucket itself, keep them.
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let leaving = outPaths
        outPaths = []
        if refreshPending {
            refreshPending = false
            DispatchQueue.main.async { self.refresh() }
        }
        guard operation != [], !leaving.isEmpty else { return }
        if let panel, panel.frame.contains(screenPoint) { return }
        // Same rule as drops: mutate the store after the session callback ends.
        DispatchQueue.main.async {
            self.perform { _ = try store.access { $0.removeAll { leaving.contains($0) } } }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
