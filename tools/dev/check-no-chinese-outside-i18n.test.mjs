import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

function fixture(t) {
  const parent = fs.realpathSync(os.tmpdir());
  const root = fs.mkdtempSync(path.join(parent, "galaxyssi-i18n-native-test-"));
  t.after(() => {
    assert.equal(path.dirname(fs.realpathSync(root)), parent);
    assert.ok(path.basename(root).startsWith("galaxyssi-i18n-native-test-"));
    fs.rmSync(root, { recursive: true, force: true });
  });
  const write = (name, content) => {
    const target = path.join(root, name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, content);
  };
  write("tools/dev/i18n-linguistic-data.json", JSON.stringify({
    schema: "galaxyssi.i18n-linguistic-data.v1", files: []
  }));
  const checker = path.join(root, "tools/dev/check-no-chinese-outside-i18n.js");
  fs.copyFileSync(fileURLToPath(new URL("./check-no-chinese-outside-i18n.js", import.meta.url)), checker);
  const run = () => spawnSync(process.execPath, [checker], { encoding: "utf8", timeout: 10_000 });
  return { write, run };
}

test("native target artifacts are not read as source text", (t) => {
  const { write, run } = fixture(t);
  write("apps/android/memory-native/target/debug/opaque.o", "\u4e2d\u6587");
  write("apps/android/memory-native/src/lib.rs", "pub fn example() {}\n");
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Chinese text guard OK/);
});

test("native source still obeys the text policy", (t) => {
  const { write, run } = fixture(t);
  write("apps/android/memory-native/src/lib.rs", '// "\u4e2d\u6587"\n');
  const result = run();
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /apps\/android\/memory-native\/src\/lib.rs:1/);
});

test("an unrelated directory named target is not excluded", (t) => {
  const { write, run } = fixture(t);
  write("apps/example/target/source.rs", '// "\u4e2d\u6587"\n');
  const result = run();
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /apps\/example\/target\/source.rs:1/);
});
