# File Bucket

A native macOS file shelf that lives at the edge of your screen. Requires macOS 13 or later. No dependencies, network listener, admin install, or source-file modifications.

Start dragging any file and keep the mouse held: after a short delay the bucket slides out. Drop files on it to hold them, then drag them out later into a browser upload area, Finder, or any native drop destination. Originals never move; the bucket keeps references only.

## Build and run

```sh
cd file-drop-bucket
./build.sh
open "build/File Bucket.app"
```

The app runs as a menu-bar utility (no Dock icon). On launch the panel opens once so you know it is running, then disappears entirely — nothing is left on the edge. Hover the docked screen edge (a band roughly the panel's height, centered vertically) to slide it out; move away to slide it back. The pin keeps it open; the close button hides it again.

## Menu bar

The tray icon menu controls everything: dock at left or right edge, float freely, appear-while-dragging on/off, hold delay (0.4–2.5 s), file-drags-only filtering, clear, quit, and a standard file picker to add files.

## CLI

`bucket` in this directory talks to the same store. Safe to run while the app is open; the app picks up changes within half a second.

```sh
./bucket add "/path/with spaces/audio.wav"   # add files
./bucket list                               # print held paths
./bucket clear                              # empty the bucket (files stay)
./bucket show                               # reveal and pin the panel
./bucket dock left|right|off                # edge or floating
./bucket delay 1.2                          # seconds to hold before showing
./bucket autoshow on|off                    # reveal during a held drag
./bucket onlyfiles on|off                   # only reveal for real file drags
./bucket keepopen on|off                    # pin the panel open
./bucket config                             # print current settings
```

## How it works

- **Hold detection**: a 30 Hz timer watches `NSEvent.pressedMouseButtons` and `NSEvent.mouseLocation` — no accessibility or input-monitoring permission needed. When the button stays held while the cursor has moved past 12 pt for `holdDelay` seconds, the panel reveals. With `onlyfiles` on, the drag pasteboard's `changeCount` is compared between press and hold time so stale pasteboards cannot suppress it; a live non-file drag (text selection, tab drag) is ignored.
- **Edge dock**: concealed means the panel is ordered out — zero pixels on screen. A 50 ms poll of the cursor position watches an edge band on the docked display and slides the panel in on hover, out when you leave, unless pinned or mid-drag. The docked display is tracked explicitly so parking off-screen never bleeds onto a neighbouring monitor.
- **Drops**: the whole panel is an `NSDraggingDestination` for `public.file-url`; hovering the edge mid-drag slides it out under the session. A highlight overlay confirms before release.
- **Drags out**: rows are real `NSURL` pasteboard sources; select multiple rows with Command/Shift.
- **Motion**: a critically damped spring drives the slide; it re-targets mid-flight, so hover/drag transitions never pop. Reduce Motion swaps slides for fades.
- **Persistence**: `~/Library/Application Support/FileDropBucket/manifest.json` (canonical paths, advisory lock, atomic writes, 0700/0600 permissions) plus `settings.json` shared with the CLI. `BUCKET_HOME` overrides the directory for testing.

## Implementation

- `Store.swift`: path validation, deduplication, persistence, locking.
- `Settings.swift`: dock side, hold delay, auto-show, pin; same lock, shared with the CLI.
- `DragMonitor.swift`: permission-free held-drag detection.
- `WindowSpring.swift`: interruptible frame spring.
- `BucketPanel.swift`: non-activating vibrancy panel, table, drop overlay, empty state.
- `DockController.swift`: edge geometry, hover polling, reveal/conceal state machine.
- `StatusItem.swift`: menu bar menu.
- `main.swift`: CLI dispatch, wiring, `--drop-test` diagnostics.
- `PasteboardTest.swift`, `fixtures/`, `tests/`: native pasteboard round-trip, test files, regression suite.

## Verification

Built with Swift 6.3.3 on Apple Silicon, targeting macOS 13. `./tests/run.sh` builds, verifies the strict ad-hoc signature, and passes CLI checks for Unicode and spaces, empty files, symlink deduplication, atomic invalid batches, invalid commands and directories, private state permissions, 24 concurrent adds, missing sources, clear, and preserving source bytes. Native pasteboard validation also passes.

Verified on a live desktop: launch shows the panel pinned on the right edge; `bucket keepopen off` slides it fully off-screen (nothing visible); hovering the docked edge reveals it; a synthetic held mouse drag revealed the panel mid-flight at 0.8 s; `bucket dock off` floats it; `bucket show` re-opens it. The pin button, close button, context menu (open, reveal in Finder, remove), double-click to open, and row drag-outs are all wired to the same store the CLI uses.

Not covered by automation: a real Cocoa drag-and-drop into the panel (synthetic events cannot create an `NSDraggingSession`) — verified path only as far as the destination being registered and the store accepting drops. Try it: hold any Finder file until the bucket appears, then drop it on the panel.

For manual diagnosis, quit the app, then run:

```sh
BUCKET_DROP_TEST=1 './build/File Bucket.app/Contents/MacOS/FileBucket' --app
```

This logs monitor decisions (`[bucket-monitor]` lines) and enables the same-window drop probe. A separate receiver window can also be launched with the binary's `--drop-test` argument.
