// Source and analytic checks only; no Swift/native/Android renderer executes.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPericyteCoverageStoryView.kt"], {cwd: root, encoding: "utf8"});
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const drawing = read("PericyteDrawing"), geometry = read("PericyteGeometry");
const expected = [...source.matchAll(/callout\(c, string\.health_atlas_pericyte_coverage_art_(\w+), ([^)]+)\)/g)]
  .map(m => [m[1], ...m[2].split(",").map(s => Number(s.trim().replace(/f$/, "")))]);
const actual = [...drawing.matchAll(/pericyteCallout\("(\w+)", ([^)]+)\)/g)]
  .map(m => [m[1], ...m[2].split(",").map(s => Number(s.trim()))]);
assert.equal(expected.length, 10); assert.deepEqual(actual, expected);
for (const token of ["CGRect(x: 27, y: 127, width: 306, height: 120), cornerRadius: 16", "CGRect(x: 28, y: 158, width: 304, height: 58), cornerRadius: 9", "static let wrapTraceRoute"]) assert.ok(geometry.includes(token), token);
for (const token of ["step == 1", "step == 2", "cooperation: step == 3", "clipped.clip(to: G.window)", "lumen.fill(G.window",
  "0.25 * Double(i)", "0.08 + 0.83 * t", "2.5 + 1.1 * (1 + wave(t))", "13 + 5 * (1 + wave(t - 0.25))",
  "16 + Double(i) * 90", ".degrees(43)", "y > tipY ? y - 15 : y + 5"]) assert.ok(drawing.includes(token), token);
const keys = [...new Set([...source.matchAll(/string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
let positions = 0;
for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120, wrap = .08 + .83 * t;
  assert.ok(wrap >= 0 && wrap <= 1);
  for (let i = 0; i <= 3; i++) {
    const x = 28 + 304 * ((t + .25 * i) % 1), y = i % 2 === 0 ? 172 : 203;
    assert.ok(x >= 28 && x <= 332 && y >= 158 && y <= 216); positions++;
  }
}
console.log("Source-only pericyte audit: exact sleeve/window, ten original callouts, stage/clip/rotation contracts and " + keys.length + " bilingual keys; " + positions + " analytic RBC centers. No native/pixel acceptance.");
