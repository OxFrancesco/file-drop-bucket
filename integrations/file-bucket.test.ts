import { test, expect } from "bun:test";
import { mkdtemp, writeFile, readFile, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { runFileBucket } from "./file-bucket";

test("real CLI stages literal paths, validates before mutation, and clears references only", async () => {
  const root = await realpath(await mkdtemp(join(tmpdir(), "bucket-plugin-test-")));
  const oldHome = process.env.BUCKET_HOME;
  const oldCli = process.env.FILE_BUCKET_CLI;
  process.env.BUCKET_HOME = join(root, "store");
  process.env.FILE_BUCKET_CLI = resolve(import.meta.dir, "../build/File Bucket.app/Contents/MacOS/FileBucket");
  const name = "-quoted ' space $(touch INJECTION) ; ü.txt";
  const fixture = join(root, name);
  await writeFile(fixture, "harmless integration fixture\n");
  try {
    expect((await runFileBucket({ action: "status" }, root)).content[0]?.text).toContain("empty");
    await runFileBucket({ action: "add", paths: [name] }, root);
    await runFileBucket({ action: "add", paths: [`@${fixture}`] }, root);
    const staged: unknown = JSON.parse(await readFile(join(root, "store/manifest.json"), "utf8"));
    expect(Array.isArray(staged) && staged.length === 1).toBe(true);
    if (!Array.isArray(staged) || typeof staged[0] !== "string") throw new Error("Invalid CLI manifest");
    expect((await realpath(staged[0])).normalize("NFC")).toBe(fixture.normalize("NFC"));
    expect((await runFileBucket({ action: "status" }, root)).content[0]?.text).toContain(staged[0]);
    await expect(runFileBucket({ action: "add", paths: [root] }, root)).rejects.toThrow("regular file");
    await expect(runFileBucket({ action: "add", paths: [fixture, "missing"] }, root)).rejects.toThrow();
    await expect(runFileBucket({ action: "add", paths: [] }, root)).rejects.toThrow();
    await expect(runFileBucket({ action: "clear", paths: [fixture] }, root)).rejects.toThrow();
    await expect(runFileBucket({ action: "add", paths: ["a\0b"] }, root)).rejects.toThrow();
    await expect(readFile(join(root, "INJECTION"))).rejects.toThrow();
    const controller = new AbortController(); controller.abort();
    await expect(runFileBucket({ action: "clear" }, root, controller.signal)).rejects.toThrow();
    expect(JSON.parse(await readFile(join(root, "store/manifest.json"), "utf8"))).toEqual(staged);
    await runFileBucket({ action: "clear" }, root);
    expect(JSON.parse(await readFile(join(root, "store/manifest.json"), "utf8"))).toEqual([]);
    expect(await readFile(fixture, "utf8")).toBe("harmless integration fixture\n");
  } finally {
    if (oldHome === undefined) delete process.env.BUCKET_HOME; else process.env.BUCKET_HOME = oldHome;
    if (oldCli === undefined) delete process.env.FILE_BUCKET_CLI; else process.env.FILE_BUCKET_CLI = oldCli;
  }
});
