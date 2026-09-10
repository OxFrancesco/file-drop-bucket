# OCU native drag fix, blocked on permission for the patched build

## Confirmed cause

Installed OCU 0.3.3, commit `41c5294cfe4735baca03f9c82b4de99d191a0b49`, defaults to `CGEvent.postToPid` for dragging. File Bucket receives down/dragged/up with `window=0`; NSTableView never invokes its NSURL pasteboard writer. A successful tool response does not establish a native drop.

Using the SAME installed backend's public `call` API with `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` passed the native receiver's exact filename, size and byte assertion. The source app was unchanged and the destination was the same-window offline native receiver. No file-input assignment or synthetic DataTransfer was used.

The existing global path already converts screenshot pixels through window scale and Quartz screen origin, prepares the source window, then posts left-down, ten interpolated left-dragged events and left-up at the HID event tap with 30 ms spacing. That path passed on this Mac. This patch therefore does NOT speculate about Retina scaling, add private event fields, or replace working timing. Both endpoints remain in the source screenshot's coordinate system. Cross-app delivery and multi-display coordinates remain unverified here.

## Backend patch

`ocu-0.3.3-native-drag.patch` and the complete changed Swift files under `source/` are portable source, not a File Bucket workaround.

- Real-app drag requires explicit `OPEN_COMPUTER_USE_ALLOW_NATIVE_DRAG=1`, or the existing broad global-pointer consent.
- Authorized drag calls the existing session-level `dragGlobally` implementation.
- Without consent, drag throws before sending input rather than pretending that PID delivery completed a native drag.
- Drag-only consent does not enable global clicks or scrolling. Existing AX checks, app restrictions, Screen Recording and Accessibility requirements remain unchanged.
- The internal OCU fixture bridge remains unchanged. Its synthetic smoke checks are not native-drop evidence.
- Three new tests cover consent, false values and click/scroll isolation.

No File Bucket app source, sa-7 integration files, or global Pi extension files were edited.

## Build and install

Requires macOS, Xcode command line tools, Swift 6.2 or newer, Git and Python 3. No package-manager dependencies.

```sh
chmod +x build.sh ocu-native-drag
./build.sh /tmp/ocu-native-drag-rebuild
# Copy only if this destination does not already exist:
mkdir -p "$HOME/Applications"
ditto '/tmp/ocu-native-drag-rebuild/dist/Open Computer Use (Dev).app' \
  "$HOME/Applications/Open Computer Use (Dev).app"
./ocu-native-drag doctor
```

The patched dev app was already copied to `~/Applications/Open Computer Use (Dev).app` on the test Mac. Its doctor result is `accessibility=missing, screenRecording=missing`. The installed production app is signed by upstream's Developer ID. Replacing it with an ad-hoc binary would change its identity, so it was NOT overwritten. No TCC database, signing identity, permission decision or OS protection was modified.

Grant Accessibility and Screen Recording to **Open Computer Use (Dev)** through System Settings. Ensure the app running Pi has its required permissions too. Run this launcher's `doctor` again and relaunch the dev app if macOS requests it.

To use the patched backend in Pi, start a fresh Pi process with the absolute path to this `ocu-native-drag` launcher as `OCU_BIN`. The existing OpenComputerUse extension already supports `OCU_BIN`. Run `/ocu-doctor`, `/ocu-reconnect`, `ocu_list_apps`, then fresh `ocu_get_app_state` captures. The currently running Pi bridge still points to the original signed backend and has NOT been reloaded. Do not confuse its working permission status with the dev build's missing permissions.

This launcher opts into moving the real pointer for every authorized `ocu_drag` call. It uses a separate agent socket namespace to avoid reusing the old release or Liny app agent. Other pointer tools keep their defaults unless the caller separately supplies the original broad global-pointer flag.

Rollback: start Pi without this `OCU_BIN`. The original release and extension were left intact. Remove the separately installed dev app only after stopping its own processes. Do not terminate unrelated OCU or Liny sessions.

## Evidence and next test

1. Original `ocu_drag` from `240,240` to `250,460` in a freshly inspected 720 by 708 source screenshot failed `python3 tests/check-drop.py`.
2. Original backend API with global-pointer opt-in and the same points passed `PASS: native drop received exact filenames and bytes: Hello bucket.txt`.
3. `evidence/original-global-native-success.png` is the resulting OCU screenshot, not evidence of a reloaded patched plugin.
4. `evidence/original-global-drop.json` contains the harmless receiver payload. `evidence/native-events.log` shows the PID-posted failure followed by window-targeted input and the pasteboard writer.
5. Patched `swift test`: 159 tests, 1 skipped, 0 failures. The three new tests pass. Separate dev app build and ad-hoc signature succeeded. These checks do not prove patched native delivery.
6. `evidence/patched-doctor.txt`: both required permissions missing. No further input was sent from that app.

After permissions are granted, quit File Bucket and run `./tests/prepare-drag.sh` from the project root in a separate terminal. This uses only isolated `build/drag-state` references. Capture and inspect source and destination before choosing new coordinates; never reuse the example points without checking screenshot size and geometry. Run the patched `ocu_drag`, then `python3 tests/check-drop.py`. Delete or move the previous drop report before every attempt so stale results cannot pass. The exact backend API alternative is:

```sh
./integrations/ocu-drag-fix/ocu-native-drag call --calls '[
 {"tool":"get_app_state","args":{"app":"local.filedropbucket.app"}},
 {"tool":"drag","args":{"app":"local.filedropbucket.app","from_x":240,"from_y":240,"to_x":250,"to_y":460}}
]'
python3 tests/check-drop.py
```

Then test the offline Chromium `tests/drop-receiver.html` with a real cross-app drag. Require `source=DataTransfer drop`, `trusted=true`, and exact fixture bytes. Do not assign a file input or manufacture a browser drop event. Test multi-file delivery separately.

**Not ready for GitHub or a claim of completed plugin repair.** The native routing cause is proven and the backend source fix builds, but the patched executable still needs permission and an end-to-end run. No commit, push or external upload was performed.
