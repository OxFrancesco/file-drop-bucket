import { execFile } from "node:child_process";
import { access, mkdtemp, realpath, stat, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";
import { promisify } from "node:util";
import { type ExtensionAPI, truncateHead } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type, type Static } from "typebox";

const exec = promisify(execFile);
const parameters = Type.Object({
  action: StringEnum(["status", "show", "add", "clear"]),
  paths: Type.Optional(Type.Array(Type.String({ minLength: 1 }), { minItems: 1, maxItems: 100 })),
}, { additionalProperties: false });
export type FileBucketInput = Static<typeof parameters>;

function expandPath(path: string, cwd: string): string {
  if (!path || path.includes("\0")) throw new Error("Path must be nonempty and contain no NUL bytes.");
  const value = path.startsWith("@") ? path.slice(1) : path;
  if (!value) throw new Error("Empty path after @ prefix.");
  if (value.startsWith("~") && value !== "~" && !value.startsWith("~/")) {
    throw new Error("Use ~/ or an absolute path, not ~username.");
  }
  return resolve(cwd, value === "~" ? homedir() : value.startsWith("~/") ? join(homedir(), value.slice(2)) : value);
}

export async function runFileBucket(input: FileBucketInput, cwd: string, signal?: AbortSignal) {
  signal?.throwIfAborted();
  if (!["status", "show", "add", "clear"].includes(input.action)) throw new Error("Unknown bucket action.");
  if (input.action !== "add" && input.paths !== undefined) throw new Error("paths is only accepted for add.");
  const args = [input.action === "status" ? "list" : input.action];
  if (input.action === "add") {
    if (!input.paths?.length || input.paths.length > 100) throw new Error("add requires 1 to 100 paths.");
    for (const path of input.paths) {
      const canonical = await realpath(expandPath(path, cwd));
      if (!(await stat(canonical)).isFile()) throw new Error(`Not a regular file: ${path}`);
      await access(canonical, constants.R_OK);
      args.push(canonical);
    }
  }
  const configured = process.env.FILE_BUCKET_CLI ?? join(homedir(), ".local/bin/file-bucket");
  if (!isAbsolute(configured) && !configured.startsWith("~/")) {
    throw new Error("FILE_BUCKET_CLI must be an absolute executable path or start with ~/; arguments are not allowed.");
  }
  const cli = expandPath(configured, cwd);
  await access(cli, constants.X_OK);
  // No shell: filenames, spaces, quotes and metacharacters remain single argv entries.
  const { stdout, stderr } = await exec(cli, args, {
    cwd, signal, timeout: 15_000, maxBuffer: 4 * 1024 * 1024, encoding: "utf8",
  });
  const output = [stdout, stderr].filter(Boolean).join("\n");
  const truncated = truncateHead(output, { maxLines: 2000, maxBytes: 50 * 1024 });
  let text = truncated.content || (input.action === "status" ? "Bucket is empty." : `Bucket ${input.action} completed.`);
  let fullOutputPath: string | undefined;
  if (truncated.truncated) {
    fullOutputPath = join(await mkdtemp(join(tmpdir(), "pi-file-bucket-")), "output.txt");
    await writeFile(fullOutputPath, output, { mode: 0o600 });
    text += `\nOutput truncated. Full output: ${fullOutputPath}`;
  }
  text += "\nOnly bucket references are managed. Original files are not deleted. Nothing was uploaded.";
  if (input.action === "add" || input.action === "show") {
    text += "\nBefore dragging: use ocu_list_apps, then ocu_get_app_state for BuddyFiles and the destination. Inspect fresh screenshots and recapture after layout changes. Add does not open the panel; use show if needed. Drag only to a user-authorized destination, then verify receipt.";
  }
  return { content: [{ type: "text" as const, text }], details: { action: input.action, cli, fullOutputPath } };
}

export default function fileBucketExtension(pi: ExtensionAPI) {
  pi.registerTool({
    name: "file_bucket",
    label: "BuddyFiles",
    description: "Manage local BuddyFiles references: status lists paths, add accepts 1-100 regular files, show opens the panel, clear removes all references WITHOUT deleting files. No uploads or automatic drags. Output capped at 2000 lines/50 KiB; full truncated output saved privately. FILE_BUCKET_CLI configures the executable.",
    promptSnippet: "Stage local files in BuddyFiles for a separately authorized native drag.",
    promptGuidelines: [
      "Use file_bucket to add/show/status/clear local drag references; clear never deletes source files.",
      "After file_bucket add/show, use ocu_list_apps and inspect fresh ocu_get_app_state screenshots for BuddyFiles and the destination before any drag. Never infer coordinates or automatically upload staged files.",
    ],
    parameters,
    async execute(_id, input, signal, _update, ctx) {
      return runFileBucket(input, ctx.cwd, signal);
    },
  });
}
