# Pi BuddyFiles integration

`file-bucket.ts` registers the `file_bucket` agent tool. It runs alongside the existing `OpenComputerUse/index.ts` extension without changing that bridge or its shared MCP session.

## Install

From the app directory, build the app, then run:

```sh
bash integrations/install.sh
```

The installer copies the plugin to `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions/file-bucket.ts` and links `~/.local/bin/file-bucket` to this checkout's built app executable. Keep the checkout at that location. The link intentionally targets the executable, not the `bucket` shell script, whose relative-directory lookup would break through a symlink.

Run `/reload` in Pi or restart it. No OCU reconnect or server port is needed. To update a differing installed plugin, back up and remove that copy, then rerun the installer. Existing differing files are never overwritten automatically.

For another installation, set `FILE_BUCKET_CLI` to an absolute executable path before starting Pi. A leading `~/` is accepted. This variable is a path, not a command string with arguments. The default is `~/.local/bin/file-bucket`. Pi supplies its core extension imports; no extra plugin runtime dependencies are needed.

## Tool calls

```json
{"action":"status"}
{"action":"add","paths":["~/Downloads/example.pdf","./fixtures/example.txt"]}
{"action":"show"}
{"action":"clear"}
```

- `status` calls CLI `list`. It reports stored references, not whether the panel is visible. Existing references can point to missing files.
- `add` validates 1 to 100 readable regular files before invoking the CLI once. Relative paths use the session cwd. Symlinks resolve to their targets. A leading `@` is accepted for Pi file references. Shell quoting and glob expansion are not applied.
- `show` requests that macOS open the bucket panel. It does not upload, drag, or verify visibility.
- `clear` removes all bucket references. It does not delete or modify original files.

The CLI receives an argv array through `execFile`, never shell-interpolated text. Errors propagate as failed Pi tool calls. Execution has a 15-second timeout and supports cancellation. Output is limited to 2000 lines or 50 KiB; larger output is saved in a private temporary directory. Process output exceeding 4 MiB fails rather than consuming unbounded memory.

## OCU handoff

After `add`, call `show` if the panel is not open. Call `ocu_list_apps`, then `ocu_get_app_state` for BuddyFiles and the destination. Inspect fresh screenshots before choosing the row and drop coordinates. Recapture after window movement or layout changes. Only drag to a destination authorized by the user and verify receipt afterward.

Adding or showing files is not permission to upload them. This integration does not call OCU, open a browser, or automate uploads. Native drag behavior remains owned and tested by the app/OCU workflow.

## Tests

With Bun and the built app available:

```sh
cd integrations
bun install
bun test
bun run typecheck
```

The CLI test uses a temporary `BUCKET_HOME`, so it never clears the user's bucket. It checks duplicate handling, literal spaces/quotes/shell metacharacters/Unicode, missing files, directories, NUL bytes, invalid argument combinations, cancellation, and source-file survival after clear. macOS may normalize Unicode and `/private/var` paths; the test compares resolved paths.

Local verification also loaded the installed copy through Pi's actual extension loader with zero errors and confirmed registration of `file_bucket`. Strict TypeScript checking passed. `show` and native dragging were not exercised here to avoid interrupting the concurrent UI test agent. No app source files or root README were changed.
